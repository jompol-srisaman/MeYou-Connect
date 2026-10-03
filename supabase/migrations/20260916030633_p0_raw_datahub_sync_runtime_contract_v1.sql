alter table ops.raw_datahub_sync_ledger
  add column if not exists in_flight_at timestamptz,
  add column if not exists last_attempt_at timestamptz;

create or replace view ops.raw_datahub_sync_source_backlog_v as
select
  p.source_system,
  p.source_account_ref,
  count(*) filter (where p.sync_status is null) as unstaged_count,
  count(*) filter (where p.sync_status='PENDING') as pending_count,
  count(*) filter (where p.sync_status='IN_FLIGHT') as in_flight_count,
  count(*) filter (where p.sync_status='RETRY') as retry_count,
  count(*) filter (where p.sync_status='SYNCED') as synced_count,
  count(*) filter (where p.sync_status='DQ') as dq_count,
  min(p.source_received_at) filter (where p.sync_status is null or p.sync_status in ('PENDING','RETRY','IN_FLIGHT')) as oldest_open_received_at,
  max(p.source_received_at) as latest_source_received_at
from ops.raw_datahub_sync_plan_v p
group by p.source_system,p.source_account_ref;

revoke all on ops.raw_datahub_sync_source_backlog_v from public,anon,authenticated;
grant select on ops.raw_datahub_sync_source_backlog_v to service_role;

create or replace function ops.raw_datahub_sync_claim_pending(
  p_limit integer default 100,
  p_now timestamptz default now()
)
returns table(
  stable_external_key text,
  raw_input_id text,
  source_system text,
  source_account_ref text,
  source_received_at timestamptz,
  payload_checksum text,
  attempt_count integer,
  channel text,
  sender_type text,
  sender_ref text,
  content_type text,
  original_ref text,
  raw_summary text,
  classification text,
  entity_type text,
  entity_id text,
  processing_status text,
  thread_id text,
  message_id text,
  consent_signal text
)
language plpgsql
security definer
set search_path=pg_catalog,ops
as $$
declare
  v_max_retries integer;
begin
  if p_limit < 1 or p_limit > 500 then
    raise exception 'limit must be between 1 and 500';
  end if;
  select max_retries into v_max_retries from ops.worker_registry where worker_key='raw_sync';
  v_max_retries := coalesce(v_max_retries,5);

  update ops.raw_datahub_sync_ledger l
  set sync_status=case when l.attempt_count >= v_max_retries then 'DQ' else 'RETRY' end,
      next_retry_at=case when l.attempt_count >= v_max_retries then null else p_now end,
      in_flight_at=null,
      last_error_class=coalesce(l.last_error_class,'STALE_IN_FLIGHT'),
      last_error_message=coalesce(l.last_error_message,'Recovered stale IN_FLIGHT lease'),
      updated_at=p_now
  where l.sync_status='IN_FLIGHT'
    and l.in_flight_at is not null
    and l.in_flight_at < p_now - interval '10 minutes';

  return query
  with candidates as (
    select l.stable_external_key
    from ops.raw_datahub_sync_ledger l
    where l.sync_status='PENDING'
       or (l.sync_status='RETRY' and coalesce(l.next_retry_at,'epoch'::timestamptz) <= p_now)
    order by l.source_system,l.source_account_ref,l.source_received_at,l.raw_input_id
    for update skip locked
    limit p_limit
  ), claimed as (
    update ops.raw_datahub_sync_ledger l
    set sync_status='IN_FLIGHT',
        attempt_count=l.attempt_count+1,
        in_flight_at=p_now,
        last_attempt_at=p_now,
        next_retry_at=null,
        updated_at=p_now
    from candidates c
    where l.stable_external_key=c.stable_external_key
    returning l.*
  )
  select c.stable_external_key,c.raw_input_id,c.source_system,c.source_account_ref,c.source_received_at,
         c.payload_checksum,c.attempt_count,
         r.channel,r.sender_type,r.sender_ref,r.content_type,r.original_ref,r.raw_summary,
         r.classification,r.entity_type,r.entity_id,r.processing_status,r.thread_id,r.message_id,r.consent_signal
  from claimed c
  join ops.raw_inputs r on r.raw_input_id=c.raw_input_id
  order by c.source_system,c.source_account_ref,c.source_received_at,c.raw_input_id;
end;
$$;

revoke all on function ops.raw_datahub_sync_claim_pending(integer,timestamptz) from public,anon,authenticated;
grant execute on function ops.raw_datahub_sync_claim_pending(integer,timestamptz) to service_role;

create or replace function ops.raw_datahub_sync_refresh_watermark(
  p_source_system text,
  p_source_account_ref text,
  p_now timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path=pg_catalog,ops
as $$
declare
  v_row ops.raw_datahub_sync_ledger%rowtype;
begin
  select l.* into v_row
  from ops.raw_datahub_sync_ledger l
  where l.source_system=p_source_system
    and l.source_account_ref=coalesce(nullif(p_source_account_ref,''),'__UNSCOPED__')
    and l.sync_status='SYNCED'
    and not exists (
      select 1 from ops.raw_datahub_sync_ledger x
      where x.source_system=l.source_system
        and x.source_account_ref=l.source_account_ref
        and (x.source_received_at,x.raw_input_id) < (l.source_received_at,l.raw_input_id)
        and x.sync_status <> 'SYNCED'
    )
  order by l.source_received_at desc,l.raw_input_id desc
  limit 1;

  if found then
    insert into ops.raw_datahub_sync_watermarks(
      source_system,source_account_ref,last_received_at,last_raw_input_id,last_external_key,last_readback_verified_at,updated_at
    ) values (
      v_row.source_system,v_row.source_account_ref,v_row.source_received_at,v_row.raw_input_id,
      v_row.stable_external_key,v_row.readback_verified_at,p_now
    )
    on conflict(source_system,source_account_ref) do update set
      last_received_at=excluded.last_received_at,
      last_raw_input_id=excluded.last_raw_input_id,
      last_external_key=excluded.last_external_key,
      last_readback_verified_at=excluded.last_readback_verified_at,
      updated_at=excluded.updated_at;
  end if;
end;
$$;

revoke all on function ops.raw_datahub_sync_refresh_watermark(text,text,timestamptz) from public,anon,authenticated;
grant execute on function ops.raw_datahub_sync_refresh_watermark(text,text,timestamptz) to service_role;

create or replace function ops.raw_datahub_sync_mark_success(
  p_raw_input_id text,
  p_payload_checksum text,
  p_target_row_ref text,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,ops
as $$
declare
  v ops.raw_datahub_sync_ledger%rowtype;
begin
  update ops.raw_datahub_sync_ledger l
  set sync_status='SYNCED',
      target_row_ref=p_target_row_ref,
      readback_verified_at=p_now,
      in_flight_at=null,
      next_retry_at=null,
      last_error_class=null,
      last_error_message=null,
      updated_at=p_now
  where l.raw_input_id=p_raw_input_id
    and l.payload_checksum=p_payload_checksum
    and l.sync_status in ('IN_FLIGHT','SYNCED')
  returning l.* into v;

  if not found then
    raise exception 'raw sync success rejected for %, checksum/status mismatch',p_raw_input_id;
  end if;
  perform ops.raw_datahub_sync_refresh_watermark(v.source_system,v.source_account_ref,p_now);
  return jsonb_build_object('raw_input_id',v.raw_input_id,'sync_status','SYNCED','target_row_ref',p_target_row_ref,'readback_verified_at',p_now);
end;
$$;

revoke all on function ops.raw_datahub_sync_mark_success(text,text,text,timestamptz) from public,anon,authenticated;
grant execute on function ops.raw_datahub_sync_mark_success(text,text,text,timestamptz) to service_role;

create or replace function ops.raw_datahub_sync_mark_failure(
  p_raw_input_id text,
  p_error_class text,
  p_error_message text,
  p_terminal boolean default false,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,ops
as $$
declare
  v ops.raw_datahub_sync_ledger%rowtype;
  v_max_retries integer;
  v_terminal boolean;
  v_retry_seconds integer;
begin
  select max_retries into v_max_retries from ops.worker_registry where worker_key='raw_sync';
  v_max_retries:=coalesce(v_max_retries,5);
  select * into v from ops.raw_datahub_sync_ledger where raw_input_id=p_raw_input_id for update;
  if not found then raise exception 'raw sync ledger row not found for %',p_raw_input_id; end if;
  v_terminal := p_terminal or v.attempt_count >= v_max_retries;
  v_retry_seconds := least(3600,30 * (2 ^ greatest(v.attempt_count-1,0))::integer);
  update ops.raw_datahub_sync_ledger l
  set sync_status=case when v_terminal then 'DQ' else 'RETRY' end,
      next_retry_at=case when v_terminal then null else p_now + make_interval(secs=>v_retry_seconds) end,
      in_flight_at=null,
      last_error_class=left(coalesce(p_error_class,'UNKNOWN'),120),
      last_error_message=left(coalesce(p_error_message,'Unknown raw sync failure'),1000),
      updated_at=p_now
  where l.raw_input_id=p_raw_input_id;
  return jsonb_build_object('raw_input_id',p_raw_input_id,'sync_status',case when v_terminal then 'DQ' else 'RETRY' end,'attempt_count',v.attempt_count,'next_retry_at',case when v_terminal then null else p_now + make_interval(secs=>v_retry_seconds) end,'error_class',left(coalesce(p_error_class,'UNKNOWN'),120));
end;
$$;

revoke all on function ops.raw_datahub_sync_mark_failure(text,text,text,boolean,timestamptz) from public,anon,authenticated;
grant execute on function ops.raw_datahub_sync_mark_failure(text,text,text,boolean,timestamptz) to service_role;

create or replace view ops.raw_datahub_sync_runtime_status_v as
select
  (select count(*) from ops.raw_datahub_sync_plan_v where sync_status is null) as unstaged_count,
  (select count(*) from ops.raw_datahub_sync_ledger where sync_status='PENDING') as pending_count,
  (select count(*) from ops.raw_datahub_sync_ledger where sync_status='IN_FLIGHT') as in_flight_count,
  (select count(*) from ops.raw_datahub_sync_ledger where sync_status='RETRY') as retry_count,
  (select count(*) from ops.raw_datahub_sync_ledger where sync_status='SYNCED') as synced_count,
  (select count(*) from ops.raw_datahub_sync_ledger where sync_status='DQ') as dq_count,
  (select count(*) from ops.raw_datahub_sync_watermarks) as watermark_count,
  (select max(readback_verified_at) from ops.raw_datahub_sync_ledger where sync_status='SYNCED') as latest_verified_at;

revoke all on ops.raw_datahub_sync_runtime_status_v from public,anon,authenticated;
grant select on ops.raw_datahub_sync_runtime_status_v to service_role;

comment on function ops.raw_datahub_sync_claim_pending(integer,timestamptz) is 'Claims already-staged canonical Raw->Data Hub sync ledger rows using SKIP LOCKED. Does not write business Master.';
comment on function ops.raw_datahub_sync_mark_success(text,text,text,timestamptz) is 'Marks Raw sync success only after external Google Data Hub read-back verification and advances the per-source contiguous watermark.';
comment on function ops.raw_datahub_sync_mark_failure(text,text,text,boolean,timestamptz) is 'Retry/DQ transition for canonical Raw->Data Hub runtime; exponential retry, no Master effect.';
