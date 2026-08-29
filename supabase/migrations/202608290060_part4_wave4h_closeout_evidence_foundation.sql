create table if not exists ops.part4_output_catalog (
  output_key text primary key,
  output_category text not null,
  requirement text not null,
  required_for_test boolean not null default true,
  production_critical boolean not null default false,
  repository_path text,
  verification_mode text not null default 'MANUAL' check (verification_mode in ('AUTO','MANUAL','REPOSITORY')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.part4_evidence_records (
  evidence_key text primary key,
  evidence_status text not null check (evidence_status in ('PASS','FAIL','NOT_READY','INFO')),
  evidence_ref text,
  details jsonb not null default '{}'::jsonb,
  recorded_by text not null,
  recorded_at timestamptz not null default now()
);

create table if not exists ops.part4_closeout_check_catalog (
  check_key text primary key,
  scope text not null check (scope in ('TEST_IMPLEMENTATION','PRODUCTION_READINESS')),
  check_order integer not null,
  check_mode text not null check (check_mode in ('AUTO','EVIDENCE')),
  description text not null,
  critical boolean not null default true,
  evidence_key text,
  created_at timestamptz not null default now(),
  unique(scope, check_order)
);

create table if not exists ops.part4_closeout_runs (
  closeout_run_id uuid primary key default gen_random_uuid(),
  scope text not null check (scope in ('TEST_IMPLEMENTATION','PRODUCTION_READINESS')),
  status text not null check (status in ('PASS','NOT_READY','FAIL')),
  total_checks integer not null default 0,
  passed_checks integer not null default 0,
  failed_checks integer not null default 0,
  not_ready_checks integer not null default 0,
  created_by text not null,
  notes text,
  created_at timestamptz not null default now()
);

create table if not exists ops.part4_closeout_results (
  result_pk uuid primary key default gen_random_uuid(),
  closeout_run_id uuid not null references ops.part4_closeout_runs(closeout_run_id) on delete cascade,
  check_key text not null references ops.part4_closeout_check_catalog(check_key),
  status text not null check (status in ('PASS','FAIL','NOT_READY','INFO')),
  evidence_ref text,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(closeout_run_id, check_key)
);

create index if not exists part4_closeout_results_run_idx on ops.part4_closeout_results(closeout_run_id);
create index if not exists part4_closeout_runs_scope_created_idx on ops.part4_closeout_runs(scope, created_at desc);

insert into ops.part4_output_catalog(output_key,output_category,requirement,required_for_test,production_critical,repository_path,verification_mode,notes) values
('SQL_MIGRATIONS','Engineering','SQL migrations',true,true,'supabase/migrations/','AUTO','Canonical implementation history lives in Supabase and GitHub migrations.'),
('SCHEMA_OVERVIEW','Documentation','Schema diagram / README',true,false,'docs/PART4_SCHEMA_OVERVIEW.md','REPOSITORY','Textual schema map with Mermaid overview is acceptable for TEST closeout.'),
('RLS_TESTS','Security','RLS allow/deny tests',true,true,'supabase/migrations/','AUTO','Covered by Part 4D smoke and later hardening migrations.'),
('SYNTHETIC_SEED_TESTS','Testing','Seed / synthetic reference test data',true,false,'supabase/migrations/','AUTO','Transactional smoke migrations create and clean synthetic records.'),
('MIGRATION_TOOLING','Migration','Repeatable migration / reconciliation tooling',true,true,'supabase/migrations/','AUTO','Part 4F/4G shadow, delta and reconciliation harness.'),
('FILE_MIGRATION_VERIFIER','Migration','File migration verification utility',true,true,'scripts/part4_file_migration_verify.py','REPOSITORY','Local manifest/checksum verifier; live file migration remains a Production-readiness task.'),
('RECONCILIATION_REPORT','Migration','Reconciliation / readiness evidence report',true,true,'docs/PART4_PRODUCTION_READINESS_EVIDENCE.md','REPOSITORY','Closeout report distinguishes TEST PASS from Production NOT_READY.'),
('ROLLBACK_RUNBOOK','Operations','Rollback runbook',true,true,'docs/PART4_ROLLBACK_RUNBOOK.md','REPOSITORY','Rollback follows one-writable-master rule.'),
('ENV_SECURITY_NOTES','Security','Environment / security notes',true,true,'docs/PART4_ENVIRONMENT_SECURITY_NOTES.md','REPOSITORY','No secrets in repository; Production gates remain disabled.'),
('OPEN_ARCH_ISSUES','Architecture','Open architecture / implementation issues',true,true,'docs/PART4_OPEN_ISSUES.md','REPOSITORY','Tracks remaining Production-only evidence and operational decisions.')
on conflict(output_key) do update set
  output_category=excluded.output_category,
  requirement=excluded.requirement,
  required_for_test=excluded.required_for_test,
  production_critical=excluded.production_critical,
  repository_path=excluded.repository_path,
  verification_mode=excluded.verification_mode,
  notes=excluded.notes,
  updated_at=now();

insert into ops.part4_closeout_check_catalog(check_key,scope,check_order,check_mode,description,critical,evidence_key) values
('T_SCHEMA_SET','TEST_IMPLEMENTATION',10,'AUTO','Required Part 4 schemas exist.',true,null),
('T_PART4_MIGRATIONS','TEST_IMPLEMENTATION',20,'AUTO','All implementation waves 4A through 4G are represented in migration history.',true,null),
('T_CANONICAL_MYC_IDS','TEST_IMPLEMENTATION',30,'AUTO','Canonical business ID namespace is MYC.',true,null),
('T_SOURCE_OF_TRUTH_UNCHANGED','TEST_IMPLEMENTATION',40,'AUTO','Google Sheets + Drive remain operational Source of Truth.',true,null),
('T_SAFETY_GATES_OFF','TEST_IMPLEMENTATION',50,'AUTO','Business apply, migration apply/cutover and Production approval gates remain OFF.',true,null),
('T_STORAGE_PRIVATE','TEST_IMPLEMENTATION',60,'AUTO','Expected storage buckets exist and remain private in TEST.',true,null),
('T_PART3_INTEGRATION','TEST_IMPLEMENTATION',70,'AUTO','Part 3 routing/worker/domain/apply contracts are present.',true,null),
('T_RLS_ENABLED','TEST_IMPLEMENTATION',80,'AUTO','Business/private/finance/authz base tables have RLS enabled.',true,null),
('T_REQUIRED_OUTPUT_CATALOG','TEST_IMPLEMENTATION',90,'AUTO','Part 4 required-output catalog is complete.',true,null),
('T_REPOSITORY_OUTPUTS','TEST_IMPLEMENTATION',100,'EVIDENCE','Required Part 4 closeout files are synchronized to the engineering repository.',true,'PART4_REPOSITORY_OUTPUTS'),
('T_SECURITY_ADVISOR','TEST_IMPLEMENTATION',110,'EVIDENCE','Supabase Security Advisor has no unresolved security lint after Part 4H.',true,'PART4_SECURITY_ADVISOR'),
('P_FOUNDER_APPROVAL','PRODUCTION_READINESS',10,'AUTO','Founder has explicitly approved Production cutover.',true,null),
('P_ARCHITECT_REVIEW','PRODUCTION_READINESS',20,'EVIDENCE','Architect has reviewed the final Production cutover package.',true,'PROD_ARCHITECT_REVIEW'),
('P_FRESH_BACKUP','PRODUCTION_READINESS',30,'EVIDENCE','Fresh Part 2 backup exists immediately before cutover.',true,'PROD_FRESH_BACKUP'),
('P_CUTOVER_REHEARSAL','PRODUCTION_READINESS',40,'AUTO','A persisted cutover rehearsal has all critical checks PASS with freeze and final backup recorded.',true,null),
('P_LIVE_RECONCILIATION','PRODUCTION_READINESS',50,'EVIDENCE','Fresh live source snapshot/delta reconciliation is PASS.',true,'PROD_LIVE_RECONCILIATION'),
('P_FILE_CHECKSUMS','PRODUCTION_READINESS',60,'EVIDENCE','Migrated file objects have verified checksums and mapping report.',true,'PROD_FILE_CHECKSUMS'),
('P_RLS_PROD_ACCEPTANCE','PRODUCTION_READINESS',70,'EVIDENCE','Production-like named-user RLS allow/deny acceptance is PASS.',true,'PROD_RLS_ACCEPTANCE'),
('P_PART3_PRODLIKE','PRODUCTION_READINESS',80,'EVIDENCE','Part 3 idempotency/retry/DLQ tests pass in Production-like environment.',true,'PROD_PART3_ACCEPTANCE'),
('P_ROLLBACK_REHEARSAL','PRODUCTION_READINESS',90,'EVIDENCE','Rollback path has been rehearsed and evidence recorded.',true,'PROD_ROLLBACK_REHEARSAL'),
('P_NAMED_AUTH_MFA','PRODUCTION_READINESS',100,'EVIDENCE','Named privileged identities and MFA/step-up controls are configured where supported.',true,'PROD_NAMED_AUTH_MFA'),
('P_WRITER_SWITCH_PLAN','PRODUCTION_READINESS',110,'EVIDENCE','Final writer endpoint switch and Sheets read-only fallback plan is approved.',true,'PROD_WRITER_SWITCH_PLAN')
on conflict(check_key) do update set
  scope=excluded.scope,
  check_order=excluded.check_order,
  check_mode=excluded.check_mode,
  description=excluded.description,
  critical=excluded.critical,
  evidence_key=excluded.evidence_key;

insert into config.system_settings(setting_key,setting_value,description,source_ref) values
('part4_test_implementation_closed','false'::jsonb,'Part 4 TEST implementation closeout flag. This does not approve Production cutover.','Part4H'),
('part4_production_readiness_status','"NOT_READY"'::jsonb,'Production readiness status is independently evaluated and must not be inferred from TEST closeout.','Part4H')
on conflict(setting_key) do update set description=excluded.description, source_ref=excluded.source_ref, updated_at=now();

alter table ops.part4_output_catalog enable row level security;
alter table ops.part4_evidence_records enable row level security;
alter table ops.part4_closeout_check_catalog enable row level security;
alter table ops.part4_closeout_runs enable row level security;
alter table ops.part4_closeout_results enable row level security;

revoke all on ops.part4_output_catalog,ops.part4_evidence_records,ops.part4_closeout_check_catalog,ops.part4_closeout_runs,ops.part4_closeout_results from public,anon,authenticated;
grant select,insert,update,delete on ops.part4_output_catalog,ops.part4_evidence_records,ops.part4_closeout_check_catalog,ops.part4_closeout_runs,ops.part4_closeout_results to service_role;
