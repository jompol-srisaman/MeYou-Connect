begin;

insert into config.system_settings(setting_key,setting_value,description)
values
 ('migration_shadow_write_enabled','false'::jsonb,'Allows TEST shadow staging only; does not permit target Master writes.'),
 ('migration_target_apply_enabled','false'::jsonb,'Hard gate for any future migration apply path. Part4F provides no target-apply function.'),
 ('migration_cutover_enabled','false'::jsonb,'Production writer cutover remains disabled.')
on conflict(setting_key) do update set description=excluded.description;

create table if not exists ops.migration_entity_map (
  entity_key text primary key,
  source_sheet text not null unique,
  target_schema text not null,
  target_table text not null,
  source_pk_header text not null,
  target_pk_column text not null,
  source_of_truth text not null,
  migration_priority text,
  sensitivity text not null default 'INTERNAL',
  id_regex text,
  compare_fields text[] not null default '{}',
  target_ready boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.shadow_import_sessions (
  session_id uuid primary key default gen_random_uuid(),
  source_system text not null,
  source_file_id text,
  source_file_name text,
  source_revision text,
  snapshot_at timestamptz not null,
  status text not null default 'OPEN' check(status in ('OPEN','STAGED','VALIDATED','RECONCILED','CLOSED','FAILED','CANCELLED')),
  source_of_truth boolean not null default false,
  expected_entities text[] not null default '{}',
  metadata jsonb not null default '{}'::jsonb,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.shadow_import_rows (
  row_pk uuid primary key default gen_random_uuid(),
  session_id uuid not null references ops.shadow_import_sessions(session_id) on delete cascade,
  entity_key text not null references ops.migration_entity_map(entity_key),
  source_sheet text not null,
  source_row_number integer not null check(source_row_number >= 2),
  source_pk text,
  raw_record jsonb not null default '{}'::jsonb,
  normalized_record jsonb not null default '{}'::jsonb,
  row_hash text not null,
  validation_status text not null default 'STAGED' check(validation_status in ('STAGED','VALID','INVALID','SKIPPED')),
  validation_issues jsonb not null default '[]'::jsonb,
  staged_at timestamptz not null default now(),
  validated_at timestamptz,
  unique(session_id,source_sheet,source_row_number)
);
create index if not exists shadow_import_rows_session_idx on ops.shadow_import_rows(session_id,entity_key,validation_status);
create index if not exists shadow_import_rows_source_pk_idx on ops.shadow_import_rows(entity_key,source_pk);

create table if not exists ops.reconciliation_runs (
  run_id uuid primary key default gen_random_uuid(),
  session_id uuid not null references ops.shadow_import_sessions(session_id) on delete cascade,
  status text not null default 'RUNNING' check(status in ('RUNNING','PASS','REVIEW_REQUIRED','FAILED','CANCELLED')),
  source_row_count integer not null default 0,
  valid_row_count integer not null default 0,
  invalid_row_count integer not null default 0,
  match_count integer not null default 0,
  source_only_count integer not null default 0,
  target_only_count integer not null default 0,
  mismatch_count integer not null default 0,
  unsupported_count integer not null default 0,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_by text not null,
  notes text,
  unique(session_id,started_at)
);
create index if not exists reconciliation_runs_session_idx on ops.reconciliation_runs(session_id,started_at desc);

create table if not exists ops.reconciliation_results (
  result_pk uuid primary key default gen_random_uuid(),
  run_id uuid not null references ops.reconciliation_runs(run_id) on delete cascade,
  session_id uuid not null references ops.shadow_import_sessions(session_id) on delete cascade,
  entity_key text not null,
  source_pk text,
  target_pk text,
  result_type text not null check(result_type in ('MATCH','SOURCE_ONLY','TARGET_ONLY','FIELD_MISMATCH','INVALID_SOURCE','UNSUPPORTED')),
  severity text not null default 'INFO' check(severity in ('INFO','LOW','MEDIUM','HIGH','CRITICAL')),
  field_diffs jsonb not null default '{}'::jsonb,
  issue_code text,
  review_required boolean not null default false,
  created_at timestamptz not null default now()
);
create index if not exists reconciliation_results_run_idx on ops.reconciliation_results(run_id,result_type,severity);
create index if not exists reconciliation_results_session_idx on ops.reconciliation_results(session_id,entity_key,review_required);

alter table ops.migration_entity_map enable row level security;
alter table ops.shadow_import_sessions enable row level security;
alter table ops.shadow_import_rows enable row level security;
alter table ops.reconciliation_runs enable row level security;
alter table ops.reconciliation_results enable row level security;

revoke all on ops.migration_entity_map,ops.shadow_import_sessions,ops.shadow_import_rows,ops.reconciliation_runs,ops.reconciliation_results from anon,authenticated;
grant select,insert,update,delete on ops.migration_entity_map,ops.shadow_import_sessions,ops.shadow_import_rows,ops.reconciliation_runs,ops.reconciliation_results to service_role;

commit;