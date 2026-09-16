create table if not exists ops.raw_datahub_sync_watermarks (
  source_system text not null,
  source_account_ref text not null,
  last_received_at timestamptz,
  last_raw_input_id text,
  last_external_key text,
  last_readback_verified_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (source_system, source_account_ref)
);

create table if not exists ops.raw_datahub_sync_ledger (
  stable_external_key text primary key,
  raw_input_id text not null references ops.raw_inputs(raw_input_id) on delete restrict,
  source_system text not null,
  source_account_ref text not null,
  source_received_at timestamptz not null,
  payload_checksum text not null,
  sync_status text not null default 'PENDING' check (sync_status in ('PENDING','IN_FLIGHT','RETRY','SYNCED','DQ')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_retry_at timestamptz,
  target_sheet text not null default '19_Raw_Input_Log',
  target_row_ref text,
  readback_verified_at timestamptz,
  last_error_class text,
  last_error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (raw_input_id)
);

create index if not exists raw_datahub_sync_ledger_source_order_idx
  on ops.raw_datahub_sync_ledger(source_system, source_account_ref, source_received_at, raw_input_id);
create index if not exists raw_datahub_sync_ledger_retry_idx
  on ops.raw_datahub_sync_ledger(sync_status, next_retry_at)
  where sync_status in ('PENDING','RETRY');

alter table ops.raw_datahub_sync_watermarks enable row level security;
alter table ops.raw_datahub_sync_ledger enable row level security;
revoke all on ops.raw_datahub_sync_watermarks from public, anon, authenticated;
revoke all on ops.raw_datahub_sync_ledger from public, anon, authenticated;
grant select, insert, update on ops.raw_datahub_sync_watermarks to service_role;
grant select, insert, update on ops.raw_datahub_sync_ledger to service_role;

create or replace view ops.raw_datahub_sync_plan_v as
select
  r.raw_input_id,
  r.source_system,
  coalesce(nullif(r.source_account_ref,''), '__UNSCOPED__') as source_account_ref,
  r.received_at as source_received_at,
  encode(extensions.digest(concat_ws('|',
    'MYC_RAW_SYNC_V1',
    coalesce(r.source_system,''),
    coalesce(nullif(r.source_account_ref,''),'__UNSCOPED__'),
    coalesce(r.raw_input_id,''),
    coalesce(r.original_ref,''),
    coalesce(r.message_id,'')
  ), 'sha256'), 'hex') as stable_external_key,
  encode(extensions.digest((jsonb_build_object(
    'raw_input_id', r.raw_input_id,
    'received_at', r.received_at,
    'source_system', r.source_system,
    'source_account_ref', coalesce(nullif(r.source_account_ref,''),'__UNSCOPED__'),
    'channel', r.channel,
    'sender_type', r.sender_type,
    'sender_ref', r.sender_ref,
    'content_type', r.content_type,
    'original_ref', r.original_ref,
    'raw_summary', r.raw_summary,
    'classification', r.classification,
    'entity_type', r.entity_type,
    'entity_id', r.entity_id,
    'processing_status', r.processing_status,
    'thread_id', r.thread_id,
    'message_id', r.message_id,
    'consent_signal', r.consent_signal
  ))::text, 'sha256'), 'hex') as payload_checksum,
  l.sync_status,
  l.attempt_count,
  l.next_retry_at,
  l.target_row_ref,
  l.readback_verified_at
from ops.raw_inputs r
left join ops.raw_datahub_sync_ledger l on l.raw_input_id = r.raw_input_id;

revoke all on ops.raw_datahub_sync_plan_v from public, anon, authenticated;
grant select on ops.raw_datahub_sync_plan_v to service_role;

create or replace function ops.raw_datahub_sync_stage_batch(
  p_source_system text,
  p_source_account_ref text,
  p_batch_size integer default 100
)
returns table(stable_external_key text, raw_input_id text, source_received_at timestamptz, payload_checksum text)
language plpgsql
security definer
set search_path = pg_catalog, ops, extensions
as $$
begin
  if p_source_system is null or btrim(p_source_system) = '' then
    raise exception 'source_system is required';
  end if;
  if p_batch_size < 1 or p_batch_size > 500 then
    raise exception 'batch_size must be between 1 and 500';
  end if;

  return query
  with wm as (
    select w.last_received_at, w.last_raw_input_id
    from ops.raw_datahub_sync_watermarks w
    where w.source_system = p_source_system
      and w.source_account_ref = coalesce(nullif(p_source_account_ref,''),'__UNSCOPED__')
  ), candidates as (
    select p.*
    from ops.raw_datahub_sync_plan_v p
    left join wm on true
    where p.source_system = p_source_system
      and p.source_account_ref = coalesce(nullif(p_source_account_ref,''),'__UNSCOPED__')
      and p.sync_status is null
      and (
        wm.last_received_at is null
        or (p.source_received_at, p.raw_input_id) > (wm.last_received_at, coalesce(wm.last_raw_input_id,''))
      )
    order by p.source_received_at, p.raw_input_id
    limit p_batch_size
  ), ins as (
    insert into ops.raw_datahub_sync_ledger(
      stable_external_key, raw_input_id, source_system, source_account_ref,
      source_received_at, payload_checksum, sync_status
    )
    select c.stable_external_key, c.raw_input_id, c.source_system, c.source_account_ref,
           c.source_received_at, c.payload_checksum, 'PENDING'
    from candidates c
    on conflict do nothing
    returning ops.raw_datahub_sync_ledger.stable_external_key,
              ops.raw_datahub_sync_ledger.raw_input_id,
              ops.raw_datahub_sync_ledger.source_received_at,
              ops.raw_datahub_sync_ledger.payload_checksum
  )
  select * from ins order by source_received_at, raw_input_id;
end;
$$;

revoke all on function ops.raw_datahub_sync_stage_batch(text,text,integer) from public, anon, authenticated;
grant execute on function ops.raw_datahub_sync_stage_batch(text,text,integer) to service_role;

insert into ops.worker_registry(worker_key, domain, enabled, default_lease_seconds, default_batch_size, max_retries, description, created_at, updated_at)
values ('raw_sync','RawSync',false,300,100,5,'Canonical Supabase Raw -> Google Data Hub sync lane. Registered BLOCKED until authoritative 19_Raw_Input_Log schema and server-side Google write/read-back credential are available.',now(),now())
on conflict(worker_key) do update set
  domain=excluded.domain,
  enabled=false,
  default_lease_seconds=excluded.default_lease_seconds,
  default_batch_size=excluded.default_batch_size,
  max_retries=excluded.max_retries,
  description=excluded.description,
  updated_at=now();

comment on table ops.raw_datahub_sync_watermarks is 'Per-source verified Data Hub Raw sync cursor. Cursor advances only after external Data Hub read-back is verified by the runtime writer.';
comment on table ops.raw_datahub_sync_ledger is 'Idempotency/retry/audit ledger for canonical Raw -> Data Hub sync. No business Master effect.';
comment on view ops.raw_datahub_sync_plan_v is 'Source-aware deterministic Raw sync plan. Raw ID is not treated as a global sequence; ordering is per source by received_at + raw_input_id and idempotency uses stable external key/checksum.';

savepoint raw_sync_smoke;
do $$
declare
  n1 integer;
  n2 integer;
begin
  select count(*) into n1 from ops.raw_datahub_sync_stage_batch('LINE','LINE_OA:MYC_DATA_BOT',3);
  select count(*) into n2 from ops.raw_datahub_sync_stage_batch('LINE','LINE_OA:MYC_DATA_BOT',3);
  if n1 <> 3 then raise exception 'raw sync stage smoke expected 3 first rows, got %', n1; end if;
  if n2 <> 3 then null; end if;
  if exists (
    select stable_external_key from ops.raw_datahub_sync_ledger
    group by stable_external_key having count(*) > 1
  ) then raise exception 'duplicate stable external key detected'; end if;
  if exists (
    select raw_input_id from ops.raw_datahub_sync_ledger
    group by raw_input_id having count(*) > 1
  ) then raise exception 'duplicate raw_input_id staged'; end if;
end $$;
rollback to savepoint raw_sync_smoke;
