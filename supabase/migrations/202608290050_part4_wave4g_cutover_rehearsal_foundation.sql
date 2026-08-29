insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('migration_rehearsal_enabled','false'::jsonb,'Enables TEST-only cutover rehearsal control plane. Does not change the operational writer.','Migration Playbook V1 / Part4G'),
('migration_freeze_rehearsal_enabled','false'::jsonb,'Enables write-freeze rehearsal checkpoints only. This does not lock Google Sheets.','Migration Playbook V1 / Part4G'),
('migration_delta_capture_enabled','false'::jsonb,'Enables TEST-only delta plan generation between controlled shadow snapshots.','Migration Playbook V1 / Part4G')
on conflict(setting_key) do update set description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

create table if not exists ops.cutover_rehearsals(
  rehearsal_id uuid primary key default gen_random_uuid(),
  rehearsal_name text not null,
  source_system text not null default 'GOOGLE_SHEETS_DRIVE',
  source_file_id text,
  baseline_session_id uuid not null references ops.shadow_import_sessions(session_id),
  final_session_id uuid references ops.shadow_import_sessions(session_id),
  baseline_source_revision text,
  freeze_source_revision text,
  final_source_revision text,
  final_backup_ref text,
  freeze_requested_at timestamptz,
  freeze_started_at timestamptz,
  freeze_ended_at timestamptz,
  freeze_acknowledged boolean not null default false,
  final_backup_recorded boolean not null default false,
  status text not null default 'PLANNED' check(status in ('PLANNED','BASELINE_LOADED','FREEZE_REHEARSAL','DELTA_READY','DELTA_APPLIED_TO_SCRATCH','RECONCILED','READY_TEST','NOT_READY','CANCELLED')),
  notes text,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.rehearsal_target_rows(
  rehearsal_target_row_id uuid primary key default gen_random_uuid(),
  rehearsal_id uuid not null references ops.cutover_rehearsals(rehearsal_id) on delete cascade,
  entity_key text not null references ops.migration_entity_map(entity_key),
  source_pk text not null,
  normalized_record jsonb not null default '{}'::jsonb,
  row_hash text not null,
  is_archived boolean not null default false,
  applied_from text not null check(applied_from in ('BASELINE','DELTA')),
  applied_at timestamptz not null default now(),
  unique(rehearsal_id,entity_key,source_pk)
);

create table if not exists ops.delta_batches(
  delta_batch_id uuid primary key default gen_random_uuid(),
  rehearsal_id uuid not null references ops.cutover_rehearsals(rehearsal_id) on delete cascade,
  batch_version integer not null,
  baseline_session_id uuid not null references ops.shadow_import_sessions(session_id),
  final_session_id uuid not null references ops.shadow_import_sessions(session_id),
  status text not null default 'PLANNED' check(status in ('PLANNED','REVIEW_REQUIRED','APPLIED_TO_SCRATCH','RECONCILED','CANCELLED')),
  insert_count integer not null default 0,
  update_count integer not null default 0,
  source_removed_count integer not null default 0,
  unchanged_count integer not null default 0,
  invalid_count integer not null default 0,
  unsupported_count integer not null default 0,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(rehearsal_id,batch_version)
);

create table if not exists ops.delta_rows(
  delta_row_id uuid primary key default gen_random_uuid(),
  delta_batch_id uuid not null references ops.delta_batches(delta_batch_id) on delete cascade,
  entity_key text not null references ops.migration_entity_map(entity_key),
  source_pk text,
  change_type text not null check(change_type in ('INSERT','UPDATE','SOURCE_REMOVED','UNCHANGED','INVALID_SOURCE','UNSUPPORTED')),
  baseline_hash text,
  final_hash text,
  baseline_record jsonb,
  final_record jsonb,
  validation_issues jsonb not null default '[]'::jsonb,
  review_required boolean not null default false,
  created_at timestamptz not null default now()
);

create unique index if not exists delta_rows_unique_business_row_idx on ops.delta_rows(delta_batch_id,entity_key,source_pk) where source_pk is not null;
create index if not exists cutover_rehearsals_baseline_idx on ops.cutover_rehearsals(baseline_session_id);
create index if not exists cutover_rehearsals_final_idx on ops.cutover_rehearsals(final_session_id);
create index if not exists rehearsal_target_rows_rehearsal_idx on ops.rehearsal_target_rows(rehearsal_id);
create index if not exists delta_batches_rehearsal_idx on ops.delta_batches(rehearsal_id);
create index if not exists delta_batches_baseline_idx on ops.delta_batches(baseline_session_id);
create index if not exists delta_batches_final_idx on ops.delta_batches(final_session_id);
create index if not exists delta_rows_batch_idx on ops.delta_rows(delta_batch_id);

alter table ops.cutover_rehearsals enable row level security;
alter table ops.rehearsal_target_rows enable row level security;
alter table ops.delta_batches enable row level security;
alter table ops.delta_rows enable row level security;

revoke all on ops.cutover_rehearsals,ops.rehearsal_target_rows,ops.delta_batches,ops.delta_rows from anon,authenticated;
grant select,insert,update,delete on ops.cutover_rehearsals,ops.rehearsal_target_rows,ops.delta_batches,ops.delta_rows to service_role;
