create table if not exists ops.backup_policy_catalog (
  policy_key text primary key,
  environment text not null check (environment in ('TEST','PROD','GOOGLE')),
  asset_scope text not null,
  tier text not null check (tier in ('A','B','C')),
  backup_layer smallint not null check (backup_layer between 1 and 3),
  backup_method text not null,
  portable_format text,
  cadence_minutes integer check (cadence_minutes is null or cadence_minutes > 0),
  rpo_minutes integer check (rpo_minutes is null or rpo_minutes > 0),
  rto_minutes integer check (rto_minutes is null or rto_minutes > 0),
  restore_test_interval_days integer check (restore_test_interval_days is null or restore_test_interval_days > 0),
  independent_copy_required boolean not null default true,
  active boolean not null default true,
  source_ref text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.backup_runs (
  backup_run_pk uuid primary key default gen_random_uuid(),
  policy_key text not null references ops.backup_policy_catalog(policy_key) on delete restrict,
  environment text not null check (environment in ('TEST','PROD','GOOGLE')),
  external_run_ref text,
  started_at timestamptz not null,
  completed_at timestamptz,
  source_snapshot_at timestamptz,
  target_provider text not null,
  target_location_ref text,
  backup_layer smallint not null check (backup_layer between 1 and 3),
  independent_copy boolean not null default false,
  result text not null default 'IN_PROGRESS' check (result in ('IN_PROGRESS','PASS','PASS_WITH_ISSUES','FAIL','CANCELLED')),
  expected_assets integer not null default 0 check (expected_assets >= 0),
  completed_assets integer not null default 0 check (completed_assets >= 0),
  failed_assets integer not null default 0 check (failed_assets >= 0),
  verification_status text not null default 'PENDING' check (verification_status in ('PENDING','PASS','PASS_WITH_ISSUES','FAIL')),
  verification_summary text,
  manifest_checksum_sha256 text,
  bytes_total bigint check (bytes_total is null or bytes_total >= 0),
  performed_by text not null,
  source_ref text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (completed_at is null or completed_at >= started_at),
  check (source_snapshot_at is null or source_snapshot_at <= coalesce(completed_at, now()))
);

create unique index if not exists backup_runs_external_ref_uq on ops.backup_runs(environment,external_run_ref) where external_run_ref is not null;
create index if not exists backup_runs_policy_completed_idx on ops.backup_runs(policy_key,completed_at desc);
create index if not exists backup_runs_environment_completed_idx on ops.backup_runs(environment,completed_at desc);

create table if not exists ops.backup_artifacts (
  artifact_pk uuid primary key default gen_random_uuid(),
  backup_run_pk uuid not null references ops.backup_runs(backup_run_pk) on delete restrict,
  asset_key text not null,
  provider text not null,
  storage_class text not null check (storage_class in ('SAME_ACCOUNT','OFF_ACCOUNT','INDEPENDENT','OFFLINE','TEST_SANDBOX')),
  location_ref text not null,
  checksum_sha256 text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  encrypted boolean,
  immutable_snapshot boolean not null default false,
  source_modified_at timestamptz,
  created_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique (backup_run_pk,asset_key,location_ref)
);
create index if not exists backup_artifacts_run_idx on ops.backup_artifacts(backup_run_pk);

create table if not exists ops.restore_test_runs (
  restore_test_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('TEST','PROD','GOOGLE')),
  backup_run_pk uuid references ops.backup_runs(backup_run_pk) on delete restrict,
  external_backup_run_ref text,
  external_restore_test_ref text,
  scenario text not null,
  restore_target text not null,
  started_at timestamptz not null,
  completed_at timestamptz,
  result text not null check (result in ('PASS','PASS_WITH_ISSUES','FAIL','IN_PROGRESS')),
  reconciliation_status text not null default 'PENDING' check (reconciliation_status in ('PASS','PASS_WITH_ISSUES','FAIL','PENDING')),
  rto_seconds integer check (rto_seconds is null or rto_seconds >= 0),
  stable_ids_ok boolean,
  candidate_sample_ok boolean,
  placement_sample_ok boolean,
  finance_evidence_sample_ok boolean,
  canonical_doc_sample_ok boolean,
  row_counts_ok boolean,
  finance_balanced_ok boolean,
  evidence_links_ok boolean,
  source_ref text,
  evidence_ref text,
  performed_by text not null,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (backup_run_pk is not null or external_backup_run_ref is not null),
  check (completed_at is null or completed_at >= started_at)
);
create unique index if not exists restore_test_external_ref_uq on ops.restore_test_runs(environment,external_restore_test_ref) where external_restore_test_ref is not null;
create index if not exists restore_test_backup_idx on ops.restore_test_runs(backup_run_pk);
create index if not exists restore_test_environment_completed_idx on ops.restore_test_runs(environment,completed_at desc);

create table if not exists ops.recovery_monitor_snapshots (
  recovery_snapshot_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('TEST','PROD','GOOGLE')),
  captured_at timestamptz not null default now(),
  active_tier_a_policies integer not null default 0,
  fresh_backup_policies integer not null default 0,
  fresh_independent_policies integer not null default 0,
  restore_verified_policies integer not null default 0,
  stale_or_missing_policies integer not null default 0,
  oldest_required_backup_age_minutes integer,
  latest_restore_age_days integer,
  overall_status text not null check (overall_status in ('PASS','NOT_READY','FAIL')),
  details jsonb not null default '{}'::jsonb
);
create index if not exists recovery_monitor_environment_time_idx on ops.recovery_monitor_snapshots(environment,captured_at desc);

insert into ops.backup_policy_catalog(policy_key,environment,asset_scope,tier,backup_layer,backup_method,portable_format,cadence_minutes,rpo_minutes,rto_minutes,restore_test_interval_days,independent_copy_required,source_ref,notes)
values
('TEST_DATABASE_CRITICAL','TEST','POSTGRESQL_CRITICAL','A',3,'PostgreSQL logical dump + manifest','SQL/Custom dump + manifest',1440,1440,240,30,true,'MEYOU_CONNECT_BACKUP_PORTABILITY_DR_BLUEPRINT_V1.md','TEST recovery policy. A passing run must point to an artifact outside the live database failure domain.'),
('TEST_PRIVATE_OBJECTS','TEST','PRIVATE_OBJECT_STORAGE','A',3,'Private object manifest + mirrored original bytes','Original bytes + manifest',1440,1440,240,30,true,'MEYOU_CONNECT_BACKUP_PORTABILITY_DR_BLUEPRINT_V1.md','Covers evidence/business/private backup objects when production data exists.'),
('GOOGLE_TIER_A_STRUCTURED','GOOGLE','GOOGLE_TIER_A_STRUCTURED','A',1,'Export snapshot','XLSX/CSV/MD/DOCX/PDF',10080,1440,240,30,true,'MEYOU_CONNECT_BACKUP_MANIFEST_V1','Current founder-stage Google control. Same-account copies are rollback snapshots, not independent disaster backup.')
on conflict (policy_key) do update set
  environment=excluded.environment,asset_scope=excluded.asset_scope,tier=excluded.tier,backup_layer=excluded.backup_layer,
  backup_method=excluded.backup_method,portable_format=excluded.portable_format,cadence_minutes=excluded.cadence_minutes,
  rpo_minutes=excluded.rpo_minutes,rto_minutes=excluded.rto_minutes,restore_test_interval_days=excluded.restore_test_interval_days,
  independent_copy_required=excluded.independent_copy_required,source_ref=excluded.source_ref,notes=excluded.notes,updated_at=now();

insert into ops.backup_runs(policy_key,environment,external_run_ref,started_at,completed_at,source_snapshot_at,target_provider,target_location_ref,backup_layer,independent_copy,result,expected_assets,completed_assets,failed_assets,verification_status,verification_summary,performed_by,source_ref,metadata)
values('GOOGLE_TIER_A_STRUCTURED','GOOGLE','MYC-BK-000007','2026-08-29 00:00:00+07','2026-08-29 23:59:59+07','2026-08-29 23:59:59+07','GOOGLE_DRIVE','19pSQ1aHai1jdJUAb9D-9EPbZqLozkWp-',1,false,'PASS',8,8,0,'PASS','Part 7 final closeout same-account snapshot. Not an independent disaster backup.','Chief Architect','1SG9AUu11H-5Ww_bJ4UATny71p8_sLDP9emvs5aJtehc',jsonb_build_object('source_observation','BACKUP_MANIFEST','scope','PART 7 FINAL CLOSEOUT'))
on conflict (environment,external_run_ref) where external_run_ref is not null do nothing;

insert into ops.restore_test_runs(environment,external_backup_run_ref,external_restore_test_ref,scenario,restore_target,started_at,completed_at,result,reconciliation_status,stable_ids_ok,candidate_sample_ok,placement_sample_ok,finance_evidence_sample_ok,canonical_doc_sample_ok,row_counts_ok,source_ref,evidence_ref,performed_by,notes)
values('GOOGLE','MYC-BK-000001','MYC-RT-000001','Control Index + Data Hub restore from same-account snapshot','Google Drive restore test folder','2026-08-29 00:00:00+07','2026-08-29 23:59:59+07','PASS','PASS',null,null,null,null,true,true,'1SG9AUu11H-5Ww_bJ4UATny71p8_sLDP9emvs5aJtehc','1XwoHq-Px0zkiEDE478gppURBmIzexadW','Chief Architect','Verified Control Index + Data Hub 27/27 tabs. Does not prove off-account restore or Candidate + Placement + Finance Evidence acceptance sample.')
on conflict (environment,external_restore_test_ref) where external_restore_test_ref is not null do nothing;

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('security_recovery_foundation_ready','false'::jsonb,'Part 5D backup/recovery foundation readiness','PART5_WAVE5D'),
('security_recovery_monitoring_enabled','false'::jsonb,'Internal backup freshness monitoring gate','PART5_WAVE5D'),
('security_backup_automation_enabled','false'::jsonb,'Automatic backup execution is not enabled by Part 5D','PART5_WAVE5D'),
('security_restore_automation_enabled','false'::jsonb,'Automatic restore execution is not enabled by Part 5D','PART5_WAVE5D'),
('part5d_foundation_closed','false'::jsonb,'Part 5D closeout flag','PART5_WAVE5D')
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();