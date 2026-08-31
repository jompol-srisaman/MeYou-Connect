create table if not exists ops.change_risk_catalog (
  risk_key text primary key,
  risk_level text not null check (risk_level in ('LOW','MEDIUM','HIGH','CRITICAL')),
  requires_test_pass boolean not null default true,
  requires_rls_tests boolean not null default false,
  requires_security_review boolean not null default true,
  requires_rollback_plan boolean not null default true,
  requires_fresh_backup boolean not null default false,
  requires_controlled_deploy_identity boolean not null default false,
  architect_review_required boolean not null default false,
  founder_approval_required boolean not null default false,
  description text not null,
  source_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.change_risk_catalog(risk_key,risk_level,requires_test_pass,requires_rls_tests,requires_security_review,requires_rollback_plan,requires_fresh_backup,requires_controlled_deploy_identity,architect_review_required,founder_approval_required,description,source_ref)
values
('STANDARD','MEDIUM',true,false,true,true,false,false,false,false,'Normal tracked application/database change.','Part5 Blueprint §18'),
('RLS_PERMISSION','HIGH',true,true,true,true,true,true,true,false,'RLS, grants, permissions or API exposure change.','Part5 Blueprint §18'),
('FINANCE','HIGH',true,false,true,true,true,true,true,false,'Finance state/function/accounting control change.','Part5 Blueprint §18'),
('ID_ALLOCATION','HIGH',true,false,true,true,true,true,true,false,'Stable ID allocation or format control change.','Part5 Blueprint §18'),
('EVENT_IDEMPOTENCY','HIGH',true,false,true,true,true,true,true,false,'Event/idempotency/replay behavior change.','Part5 Blueprint §18'),
('STORAGE_ACCESS','HIGH',true,true,true,true,true,true,true,false,'Private/public storage access policy change.','Part5 Blueprint §18'),
('AUTH_CONFIGURATION','CRITICAL',true,true,true,true,true,true,true,true,'Authentication or privileged identity configuration change.','Part5 Blueprint §18')
on conflict (risk_key) do update set
 risk_level=excluded.risk_level,requires_test_pass=excluded.requires_test_pass,requires_rls_tests=excluded.requires_rls_tests,
 requires_security_review=excluded.requires_security_review,requires_rollback_plan=excluded.requires_rollback_plan,
 requires_fresh_backup=excluded.requires_fresh_backup,requires_controlled_deploy_identity=excluded.requires_controlled_deploy_identity,
 architect_review_required=excluded.architect_review_required,founder_approval_required=excluded.founder_approval_required,
 description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

create table if not exists ops.change_requests (
  change_pk uuid primary key default gen_random_uuid(),
  change_key text not null unique,
  environment text not null check (environment in ('TEST','PROD')),
  title text not null,
  risk_key text not null references ops.change_risk_catalog(risk_key) on delete restrict,
  change_scope text not null,
  source_control_ref text,
  migration_ref text,
  requested_by text not null,
  architect_review_status text not null default 'NOT_REQUIRED' check (architect_review_status in ('NOT_REQUIRED','PENDING','APPROVED','REJECTED')),
  founder_approval_status text not null default 'NOT_REQUIRED' check (founder_approval_status in ('NOT_REQUIRED','PENDING','APPROVED','REJECTED')),
  status text not null default 'DRAFT' check (status in ('DRAFT','UNDER_REVIEW','READY','BLOCKED','DEPLOYED','CANCELLED')),
  deployed_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint change_request_no_secret_keys check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists change_requests_environment_status_idx on ops.change_requests(environment,status,created_at desc);
create index if not exists change_requests_risk_idx on ops.change_requests(risk_key,created_at desc);

create table if not exists ops.change_evidence (
  change_evidence_pk uuid primary key default gen_random_uuid(),
  change_pk uuid not null references ops.change_requests(change_pk) on delete restrict,
  evidence_type text not null check (evidence_type in ('SOURCE_CONTROL','TEST_PASS','RLS_ALLOW','RLS_DENY','SECURITY_REVIEW','ROLLBACK_PLAN','FRESH_BACKUP','DEPLOY_IDENTITY','ARCHITECT_REVIEW','FOUNDER_APPROVAL','OTHER')),
  status text not null check (status in ('PASS','FAIL','NOT_READY','INFO')),
  evidence_ref text,
  summary text not null,
  observed_at timestamptz not null default now(),
  expires_at timestamptz,
  recorded_by text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint change_evidence_no_secret_keys check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists change_evidence_change_type_idx on ops.change_evidence(change_pk,evidence_type,observed_at desc);

create table if not exists ops.change_readiness_runs (
  readiness_run_pk uuid primary key default gen_random_uuid(),
  change_pk uuid not null references ops.change_requests(change_pk) on delete restrict,
  evaluated_at timestamptz not null default now(),
  evaluated_by text not null,
  status text not null check (status in ('PASS','NOT_READY','FAIL')),
  pass_count integer not null default 0,
  fail_count integer not null default 0,
  not_ready_count integer not null default 0,
  notes text
);
create index if not exists change_readiness_runs_change_time_idx on ops.change_readiness_runs(change_pk,evaluated_at desc);

create table if not exists ops.change_readiness_results (
  result_pk uuid primary key default gen_random_uuid(),
  readiness_run_pk uuid not null references ops.change_readiness_runs(readiness_run_pk) on delete restrict,
  check_key text not null,
  status text not null check (status in ('PASS','NOT_READY','FAIL')),
  required boolean not null default true,
  observed text,
  evidence_ref text,
  unique (readiness_run_pk,check_key)
);
create index if not exists change_readiness_results_run_idx on ops.change_readiness_results(readiness_run_pk);

create table if not exists ops.part5_closeout_runs (
  closeout_run_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment='TEST'),
  evaluated_at timestamptz not null default now(),
  evaluated_by text not null,
  status text not null check (status in ('PASS','NOT_READY','FAIL')),
  pass_count integer not null default 0,
  fail_count integer not null default 0,
  not_ready_count integer not null default 0,
  production_readiness text not null default 'NOT_READY' check (production_readiness in ('PASS','NOT_READY','FAIL')),
  notes text
);

create table if not exists ops.part5_closeout_results (
  result_pk uuid primary key default gen_random_uuid(),
  closeout_run_pk uuid not null references ops.part5_closeout_runs(closeout_run_pk) on delete restrict,
  check_key text not null,
  status text not null check (status in ('PASS','NOT_READY','FAIL')),
  observed text,
  evidence_ref text,
  unique(closeout_run_pk,check_key)
);
create index if not exists part5_closeout_results_run_idx on ops.part5_closeout_results(closeout_run_pk);

alter table ops.change_risk_catalog enable row level security;
alter table ops.change_requests enable row level security;
alter table ops.change_evidence enable row level security;
alter table ops.change_readiness_runs enable row level security;
alter table ops.change_readiness_results enable row level security;
alter table ops.part5_closeout_runs enable row level security;
alter table ops.part5_closeout_results enable row level security;

revoke all on ops.change_risk_catalog,ops.change_requests,ops.change_evidence,ops.change_readiness_runs,ops.change_readiness_results,ops.part5_closeout_runs,ops.part5_closeout_results from public,anon,authenticated;
grant select,insert,update,delete on ops.change_risk_catalog,ops.change_requests,ops.change_evidence,ops.change_readiness_runs,ops.change_readiness_results,ops.part5_closeout_runs,ops.part5_closeout_results to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('security_change_control_ready','true'::jsonb,'Part 5F change/deployment readiness control plane exists.','Part5F'),
('security_deployment_execution_enabled','false'::jsonb,'Part 5F does not execute Production deployments.','Part5F'),
('part5f_foundation_closed','false'::jsonb,'Part 5F closeout flag.','Part5F')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();