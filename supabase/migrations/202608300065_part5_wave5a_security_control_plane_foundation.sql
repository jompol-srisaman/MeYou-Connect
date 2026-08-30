create table if not exists ops.security_control_catalog (
  control_id text primary key,
  domain text not null,
  control_name text not null,
  current_google_stage text,
  future_full_stack text,
  owner_role text,
  evidence_required text,
  critical boolean not null default true,
  source_status text not null check (source_status in ('PLANNED','ACTIVE','NOT_APPLICABLE_NOW')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.security_control_catalog(control_id,domain,control_name,current_google_stage,future_full_stack,owner_role,evidence_required,critical,source_status,notes) values
('SEC-001','Identity','MFA for privileged/admin accounts','Founder Google account should use MFA','Enforce org/admin MFA where available','Founder','Account/security settings',true,'PLANNED',null),
('SEC-002','Identity','No shared admin identities','Use named Google account','Named Supabase/platform identities','Founder','Member list',true,'PLANNED',null),
('SEC-003','Secrets','No secrets in Drive/prompts/repo/frontend','Policy applies now','CI secret scan + secret store/env','Architect','Scan report/inventory',true,'PLANNED',null),
('SEC-004','Authorization','Default deny / least privilege','Drive Restricted + scoped connectors','Dedicated api schema + GRANT + RLS','Architect/Data Audit','RLS/grant test report',true,'PLANNED',null),
('SEC-005','Authorization','RLS allow/deny tests','N/A until DB','Automated CI tests per role','Data Audit','Test output',true,'NOT_APPLICABLE_NOW',null),
('SEC-006','API','Review exposed schemas/views/functions',null,'Inventory + revoke unintended access','Architect','API inventory',true,'NOT_APPLICABLE_NOW',null),
('SEC-007','API','Webhook signature/replay protection','Manual connector paths','Signed webhook + timestamp/replay + idempotency','Automation Owner','Acceptance tests',true,'PLANNED',null),
('SEC-008','Abuse','Rate limiting / CAPTCHA where relevant','Provider defaults','Auth limits + endpoint class limits + CAPTCHA for public auth','Platform Owner','Config/test',true,'PLANNED',null),
('SEC-009','Storage','Private-by-default evidence','Restricted Drive/Vault','Private buckets + signed access','Data Owner','Bucket policy test',true,'ACTIVE',null),
('SEC-010','Storage','Public bucket only for approved public-safe content','No public evidence links','content-public only','Content/Data Owner','Object inventory',true,'ACTIVE',null),
('SEC-011','Logging','Do not log secrets/sensitive payload','Manual/AI log discipline','Structured redacted logs','Platform Owner','Log sample review',true,'PLANNED',null),
('SEC-012','Change','High-risk changes reviewed','Architect change control','Migration/RLS/finance/security review','Architect','PR/change record',true,'ACTIVE',null),
('SEC-013','Network','TLS/SSL for DB connections','Google managed','Enforce Postgres SSL; network restrictions where feasible','Platform Owner','Platform config',true,'PLANNED',null),
('SEC-014','Backup','DB backup separate from storage backup','Part 2 active','DB logical/native + object inventory/off-platform copy','Architect','Backup manifest',true,'ACTIVE',null),
('SEC-015','Recovery','Restore test','Part 2 restore test exists','Quarterly + before/after major migration','Architect','Restore report',true,'ACTIVE',null),
('SEC-016','Finance','Protected payment actions human-approved','Founder rule active','Approval queue/server-side enforcement','Founder/Finance','Approval/evidence',true,'ACTIVE',null)
on conflict (control_id) do update set domain=excluded.domain,control_name=excluded.control_name,current_google_stage=excluded.current_google_stage,future_full_stack=excluded.future_full_stack,owner_role=excluded.owner_role,evidence_required=excluded.evidence_required,critical=excluded.critical,source_status=excluded.source_status,notes=excluded.notes,updated_at=now();

create table if not exists ops.security_gate_catalog (
  gate_id text primary key,
  gate_name text not null,
  critical boolean not null default true,
  evidence_required text not null,
  owner_role text not null,
  evaluation_mode text not null check (evaluation_mode in ('AUTO','EVIDENCE','APPROVAL')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.security_gate_catalog(gate_id,gate_name,critical,evidence_required,owner_role,evaluation_mode,notes) values
('PG-001','Critical RLS ALLOW tests pass',true,'RLS automated test report','Data Audit','EVIDENCE',null),
('PG-002','Critical RLS DENY tests pass',true,'RLS automated test report','Data Audit','EVIDENCE',null),
('PG-003','Exposed API object inventory reviewed',true,'Schema/grant/function inventory','Architect','EVIDENCE',null),
('PG-004','No secret/service key in frontend/repo/Drive/prompts',true,'Secret scan + review','Architect','EVIDENCE','No secret material is stored in this control plane.'),
('PG-005','TEST and PROD credentials separated',true,'Environment inventory','Platform Owner','EVIDENCE',null),
('PG-006','Webhook signature/replay tests pass',true,'Acceptance tests','Automation Owner','EVIDENCE',null),
('PG-007','Part 3 idempotency critical tests pass',true,'Part 3 test report','Automation Owner','AUTO',null),
('PG-008','Finance transaction/reconciliation tests pass',true,'Finance test report','Finance/Data Audit','AUTO',null),
('PG-009','Fresh backup exists',true,'Backup Manifest run','Architect','EVIDENCE',null),
('PG-010','Restore test passes',true,'Restore report','Architect','EVIDENCE',null),
('PG-011','Private storage exposure tests pass',true,'Bucket/policy tests','Data Owner','AUTO',null),
('PG-012','Incident runbook available',true,'Runbook link/version','Founder/Architect','EVIDENCE',null),
('PG-013','Critical alerts route to real owner',true,'Alert test screenshots/log','Platform Owner','EVIDENCE',null),
('PG-014','Rollback tested',true,'Rollback drill/report','Architect','AUTO','TEST can use Part 4G rehearsal; Production still requires fresh evidence.'),
('PG-015','Founder + Architect Production approval',true,'Approval record','Founder','APPROVAL',null)
on conflict (gate_id) do update set gate_name=excluded.gate_name,critical=excluded.critical,evidence_required=excluded.evidence_required,owner_role=excluded.owner_role,evaluation_mode=excluded.evaluation_mode,notes=excluded.notes,updated_at=now();

create table if not exists ops.security_evidence_records (
  evidence_pk uuid primary key default gen_random_uuid(),
  evidence_key text not null,
  environment text not null check (environment in ('TEST','PROD','GOOGLE','SHARED')),
  control_id text references ops.security_control_catalog(control_id),
  gate_id text references ops.security_gate_catalog(gate_id),
  evidence_type text not null,
  status text not null check (status in ('PASS','FAIL','NOT_READY','INFO')),
  source_type text not null,
  source_ref text,
  summary text not null,
  details jsonb not null default '{}'::jsonb,
  observed_at timestamptz not null default now(),
  expires_at timestamptz,
  recorded_by text not null,
  created_at timestamptz not null default now(),
  unique(environment,evidence_key,observed_at)
);

create index if not exists security_evidence_key_idx on ops.security_evidence_records(environment,evidence_key,observed_at desc);
create index if not exists security_evidence_gate_idx on ops.security_evidence_records(gate_id,observed_at desc) where gate_id is not null;
create index if not exists security_evidence_control_idx on ops.security_evidence_records(control_id,observed_at desc) where control_id is not null;

create table if not exists ops.privileged_identity_registry (
  identity_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('TEST','PROD','GOOGLE')),
  identity_label text not null,
  identity_type text not null check (identity_type in ('HUMAN','SERVICE')),
  auth_user_id uuid references auth.users(id) on delete set null,
  role_key text references authz.role_catalog(role_key),
  privileged boolean not null default true,
  named_identity_verified boolean not null default false,
  mfa_status text not null default 'UNKNOWN' check (mfa_status in ('UNKNOWN','VERIFIED','NOT_APPLICABLE')),
  status text not null default 'PLANNED' check (status in ('PLANNED','ACTIVE','REVOKED')),
  evidence_ref text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(environment,identity_label)
);
create index if not exists privileged_identity_auth_user_idx on ops.privileged_identity_registry(auth_user_id) where auth_user_id is not null;
create index if not exists privileged_identity_role_idx on ops.privileged_identity_registry(role_key) where role_key is not null;

create table if not exists ops.secret_inventory (
  secret_ref text primary key,
  system_name text not null,
  environment text not null check (environment in ('TEST','PROD','SHARED')),
  purpose text not null,
  scope_summary text not null,
  stored_in text not null check (stored_in in ('NOT_CREATED','ENVIRONMENT_SECRET_STORE','SUPABASE_SECRET_STORE','N8N_CREDENTIALS','CI_CD_SECRET_STORE')),
  owner_role text not null,
  last_reviewed_at timestamptz,
  rotate_trigger text not null,
  status text not null check (status in ('NOT_CREATED','ACTIVE','ROTATION_REQUIRED','REVOKED')),
  evidence_ref text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.secret_inventory(secret_ref,system_name,environment,purpose,scope_summary,stored_in,owner_role,rotate_trigger,status,notes) values
('TEMPLATE-001','Supabase','PROD','Server privileged operations','Minimum required','NOT_CREATED','Platform Owner','Exposure / access change / provider requirement','NOT_CREATED','Never store secret material in this table.'),
('TEMPLATE-002','Facebook/LINE','PROD','Channel webhook/API','Channel-specific','NOT_CREATED','Automation Owner','Exposure / scope change','NOT_CREATED','Never store secret material in this table.'),
('TEMPLATE-003','R2','PROD','Object storage access','Bucket/prefix scoped','NOT_CREATED','Storage Owner','Exposure / access change','NOT_CREATED','Never store secret material in this table.')
on conflict (secret_ref) do update set system_name=excluded.system_name,environment=excluded.environment,purpose=excluded.purpose,scope_summary=excluded.scope_summary,stored_in=excluded.stored_in,owner_role=excluded.owner_role,rotate_trigger=excluded.rotate_trigger,status=excluded.status,notes=excluded.notes,updated_at=now();

create table if not exists ops.security_events (
  security_event_pk uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  environment text not null check (environment in ('TEST','PROD','GOOGLE','SHARED')),
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  event_type text not null,
  actor_ref text,
  service_ref text,
  entity_type text,
  entity_id text,
  trace_id text,
  event_id text,
  result text,
  summary text not null,
  evidence_ref text,
  metadata jsonb not null default '{}'::jsonb,
  status text not null default 'OPEN' check (status in ('OPEN','CONTAINED','RECOVERED','CLOSED')),
  created_at timestamptz not null default now()
);
create index if not exists security_events_severity_time_idx on ops.security_events(severity,occurred_at desc);
create index if not exists security_events_status_idx on ops.security_events(status,occurred_at desc);

create table if not exists ops.security_gate_runs (
  run_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('TEST','PROD')),
  evaluator_version text not null default '5A.1',
  status text not null default 'RUNNING' check (status in ('RUNNING','PASS','FAIL','NOT_READY')),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  evaluated_by text not null,
  pass_count integer not null default 0,
  fail_count integer not null default 0,
  not_ready_count integer not null default 0,
  notes text
);
create index if not exists security_gate_runs_env_time_idx on ops.security_gate_runs(environment,started_at desc);

create table if not exists ops.security_gate_results (
  result_pk uuid primary key default gen_random_uuid(),
  run_pk uuid not null references ops.security_gate_runs(run_pk) on delete cascade,
  gate_id text not null references ops.security_gate_catalog(gate_id),
  status text not null check (status in ('PASS','FAIL','NOT_READY')),
  expected text,
  observed text,
  evidence_ref text,
  notes text,
  created_at timestamptz not null default now(),
  unique(run_pk,gate_id)
);
create index if not exists security_gate_results_gate_idx on ops.security_gate_results(gate_id,status);

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('backup-private','backup-private',false,null,null)
on conflict (id) do update set public=false;

insert into config.system_settings(setting_key,setting_value,description,source_ref) values
('part5a_foundation_closed','false'::jsonb,'Part 5A security control plane foundation closeout flag','MEYOU_CONNECT_SECURITY_RELIABILITY_OBSERVABILITY_BLUEPRINT_V1'),
('part5_production_readiness_status','"NOT_READY"'::jsonb,'Part 5 production readiness status','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
('security_production_gate_enabled','false'::jsonb,'Production security gate execution cannot enable cutover by itself','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
('security_external_alert_delivery_enabled','false'::jsonb,'External security alert delivery remains disabled until a real owner/channel is tested','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
('security_webhook_enforcement_ready','false'::jsonb,'Webhook signature/replay protection readiness','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
('security_prod_environment_verified','false'::jsonb,'TEST/PROD identity and credential separation verified','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1')
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();