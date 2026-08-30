create table if not exists ops.security_environments (
  environment text primary key check (environment in ('TEST','PROD')),
  provider text not null default 'SUPABASE',
  environment_ref text,
  lifecycle_status text not null default 'NOT_CREATED' check (lifecycle_status in ('NOT_CREATED','ACTIVE','SUSPENDED','RETIRED')),
  verified boolean not null default false,
  verified_at timestamptz,
  evidence_ref text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.credential_requirements (
  system_name text primary key,
  required_in_test boolean not null default false,
  required_in_prod boolean not null default false,
  scope_expectation text not null,
  active boolean not null default true,
  source_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.credential_bindings (
  binding_pk uuid primary key default gen_random_uuid(),
  credential_ref text not null unique,
  system_name text not null references ops.credential_requirements(system_name),
  environment text not null references ops.security_environments(environment),
  secret_inventory_ref text references ops.secret_inventory(secret_ref),
  purpose text not null,
  secret_store_type text not null check (secret_store_type in ('ENVIRONMENT_SECRET_STORE','SUPABASE_SECRET_STORE','CI_CD_SECRET_STORE','N8N_CREDENTIALS','PROVIDER_SECRET_STORE','NOT_CREATED')),
  store_reference text,
  scope_summary text not null,
  status text not null default 'NOT_CREATED' check (status in ('NOT_CREATED','REGISTERED','VERIFIED','REVOKED')),
  last_reviewed_at timestamptz,
  evidence_ref text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint credential_binding_no_secret_keys check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);

create unique index if not exists credential_bindings_active_system_env_uq
  on ops.credential_bindings(system_name,environment)
  where status in ('REGISTERED','VERIFIED');
create index if not exists credential_bindings_secret_inventory_idx on ops.credential_bindings(secret_inventory_ref);

create table if not exists ops.secret_scan_runs (
  scan_run_pk uuid primary key default gen_random_uuid(),
  scan_key text not null unique,
  environment text not null check (environment in ('TEST','PROD','SHARED')),
  scope_type text not null check (scope_type in ('GITHUB_REPOSITORY','GOOGLE_DRIVE','FRONTEND_BUILD','PROMPT_HISTORY','DATABASE_METADATA','OTHER')),
  scope_ref text not null,
  scan_method text not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  objects_scanned integer not null default 0 check (objects_scanned>=0),
  detector_count integer not null default 0 check (detector_count>=0),
  findings_total integer not null default 0 check (findings_total>=0),
  active_secret_hits integer not null default 0 check (active_secret_hits>=0),
  potential_hits integer not null default 0 check (potential_hits>=0),
  reference_only_hits integer not null default 0 check (reference_only_hits>=0),
  coverage_complete boolean not null default false,
  result text not null default 'RUNNING' check (result in ('RUNNING','PASS','FAIL','PARTIAL','CANCELLED')),
  evidence_ref text,
  notes text,
  recorded_by text not null,
  created_at timestamptz not null default now()
);

create table if not exists ops.secret_scan_findings (
  finding_pk uuid primary key default gen_random_uuid(),
  scan_run_pk uuid not null references ops.secret_scan_runs(scan_run_pk) on delete restrict,
  finding_class text not null check (finding_class in ('ACTIVE_SECRET','POTENTIAL_SECRET','KNOWN_EXPOSURE','REFERENCE_ONLY','SECRET_NAME_ONLY')),
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  detector text not null,
  location_ref text not null,
  remediation_status text not null default 'OPEN' check (remediation_status in ('OPEN','REVIEWED','FALSE_POSITIVE','ROTATION_REQUIRED','REMEDIATED')),
  evidence_ref text,
  summary text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint secret_scan_finding_no_secret_keys check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists secret_scan_findings_run_idx on ops.secret_scan_findings(scan_run_pk);
create index if not exists secret_scan_findings_status_idx on ops.secret_scan_findings(remediation_status,severity);

insert into ops.security_environments(environment,provider,environment_ref,lifecycle_status,verified,verified_at,evidence_ref,notes)
values
 ('TEST','SUPABASE','pgjmxdeafzogzsyawejs','ACTIVE',true,now(),'part5e:test_environment_existing','Current TEST project; environment reference is not a credential.'),
 ('PROD','SUPABASE',null,'NOT_CREATED',false,null,null,'Production environment must not be invented before it exists.')
on conflict (environment) do update set provider=excluded.provider, updated_at=now();

insert into ops.credential_requirements(system_name,required_in_test,required_in_prod,scope_expectation,source_ref)
values
 ('Supabase',true,true,'Separate server privileged credential per environment; server-only and least privilege where provider permits.','Part5 Blueprint §4-6'),
 ('Facebook/LINE',false,false,'Channel-specific webhook/API credential; activate requirement only when channel is activated.','Part5 Blueprint §5/8'),
 ('R2',false,false,'Bucket/prefix scoped credential; separate backup/application scope when practical.','Part5 Blueprint §20')
on conflict (system_name) do update set scope_expectation=excluded.scope_expectation,source_ref=excluded.source_ref,updated_at=now();

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
 ('security_secret_environment_foundation_ready','true'::jsonb,'Part 5E metadata-only secret/environment control plane exists.','Part5E'),
 ('security_test_prod_credentials_separated','false'::jsonb,'Must remain false until TEST and PROD verified credentials exist and are distinct.','Part5E'),
 ('security_secret_scan_review_complete','false'::jsonb,'Must remain false until required scan coverage is complete and known exposures remediated.','Part5E'),
 ('part5e_foundation_closed','false'::jsonb,'Part 5E closeout flag.','Part5E')
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

alter table ops.security_environments enable row level security;
alter table ops.credential_requirements enable row level security;
alter table ops.credential_bindings enable row level security;
alter table ops.secret_scan_runs enable row level security;
alter table ops.secret_scan_findings enable row level security;

revoke all on ops.security_environments,ops.credential_requirements,ops.credential_bindings,ops.secret_scan_runs,ops.secret_scan_findings from public,anon,authenticated;
grant select,insert,update,delete on ops.security_environments,ops.credential_requirements,ops.credential_bindings,ops.secret_scan_runs,ops.secret_scan_findings to service_role;