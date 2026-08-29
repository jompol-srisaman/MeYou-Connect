begin;

create table if not exists ops.worker_heartbeats (
  worker_key text not null references ops.worker_registry(worker_key) on delete restrict,
  worker_instance text not null,
  environment text not null default 'test',
  status text not null default 'HEALTHY' check (status in ('STARTING','HEALTHY','DEGRADED','STOPPED')),
  version text,
  last_seen_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (worker_key, worker_instance, environment)
);

create index if not exists worker_heartbeats_seen_idx
  on ops.worker_heartbeats(environment, last_seen_at desc);

create table if not exists ops.operations_snapshots (
  snapshot_pk uuid primary key default gen_random_uuid(),
  environment text not null default 'test',
  captured_at timestamptz not null,
  total_events bigint not null default 0,
  completed_events bigint not null default 0,
  ready_events bigint not null default 0,
  retry_wait_events bigint not null default 0,
  approval_required_events bigint not null default 0,
  needs_review_events bigint not null default 0,
  dq_hold_events bigint not null default 0,
  dead_letter_events bigint not null default 0,
  ready_domain_commands bigint not null default 0,
  invalid_domain_commands bigint not null default 0,
  pending_approvals bigint not null default 0,
  active_worker_leases bigint not null default 0,
  expired_worker_leases bigint not null default 0,
  heartbeat_instances bigint not null default 0,
  stale_heartbeat_instances bigint not null default 0,
  oldest_unfinished_event_at timestamptz,
  oldest_unfinished_age_seconds bigint,
  scheduler_last_success_at timestamptz,
  scheduler_age_seconds bigint,
  created_at timestamptz not null default now()
);

create index if not exists operations_snapshots_env_time_idx
  on ops.operations_snapshots(environment, captured_at desc);

create or replace function ops.record_worker_heartbeat(
  p_worker_key text,
  p_worker_instance text,
  p_environment text default 'test',
  p_status text default 'HEALTHY',
  p_version text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_seen_at timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_worker ops.worker_registry;
  v_hb ops.worker_heartbeats;
begin
  if p_worker_instance is null or btrim(p_worker_instance) = '' then raise exception 'worker_instance is required'; end if;
  if p_environment is null or btrim(p_environment) = '' then raise exception 'environment is required'; end if;
  if upper(coalesce(p_status,'')) not in ('STARTING','HEALTHY','DEGRADED','STOPPED') then raise exception 'invalid heartbeat status: %', p_status; end if;

  select * into v_worker from ops.worker_registry where worker_key=p_worker_key;
  if not found then raise exception 'unknown worker_key: %', p_worker_key; end if;

  insert into ops.worker_heartbeats(worker_key,worker_instance,environment,status,version,last_seen_at,metadata,created_at,updated_at)
  values (p_worker_key,btrim(p_worker_instance),btrim(p_environment),upper(p_status),p_version,p_seen_at,coalesce(p_metadata,'{}'::jsonb),now(),now())
  on conflict (worker_key,worker_instance,environment) do update set
    status=excluded.status,
    version=excluded.version,
    last_seen_at=excluded.last_seen_at,
    metadata=excluded.metadata,
    updated_at=now()
  returning * into v_hb;

  return jsonb_build_object(
    'worker_key',v_hb.worker_key,
    'worker_instance',v_hb.worker_instance,
    'environment',v_hb.environment,
    'status',v_hb.status,
    'version',v_hb.version,
    'last_seen_at',v_hb.last_seen_at
  );
end;
$$;

create or replace view ops.worker_health_v with (security_invoker=true) as
select
  wr.worker_key,
  wr.domain,
  wr.enabled,
  hb.worker_instance,
  hb.environment,
  hb.version,
  hb.status as reported_status,
  hb.last_seen_at,
  case
    when hb.worker_instance is null then 'NOT_STARTED'
    when hb.status='STOPPED' then 'STOPPED'
    when hb.last_seen_at < now()-interval '5 minutes' then 'STALE'
    else hb.status
  end as effective_status,
  case when hb.last_seen_at is null then null else extract(epoch from (now()-hb.last_seen_at))::bigint end as heartbeat_age_seconds
from ops.worker_registry wr
left join ops.worker_heartbeats hb on hb.worker_key=wr.worker_key;

create or replace view ops.operations_health_v with (security_invoker=true) as
with event_stats as (
  select
    count(*)::bigint as total_events,
    count(*) filter (where processing_state='COMPLETED')::bigint as completed_events,
    count(*) filter (where processing_state in ('RECEIVED','RAW_STORED','PARSED','VALIDATED','ROUTED'))::bigint as ready_events,
    count(*) filter (where processing_state='RETRY_WAIT')::bigint as retry_wait_events,
    count(*) filter (where processing_state='APPROVAL_REQUIRED')::bigint as approval_required_events,
    count(*) filter (where processing_state='NEEDS_REVIEW')::bigint as needs_review_events,
    count(*) filter (where processing_state='DQ_HOLD')::bigint as dq_hold_events,
    count(*) filter (where processing_state='DEAD_LETTER')::bigint as dead_letter_events,
    min(received_at) filter (where processing_state not in ('COMPLETED','REJECTED','CANCELLED')) as oldest_unfinished_event_at
  from ops.events
),
command_stats as (
  select
    count(*) filter (where validation_status='VALID' and apply_status='READY')::bigint as ready_domain_commands,
    count(*) filter (where validation_status='INVALID')::bigint as invalid_domain_commands
  from ops.domain_commands
),
approval_stats as (
  select count(*) filter (where status='PENDING')::bigint as pending_approvals from ops.approvals
),
lease_stats as (
  select
    count(*) filter (where status='CLAIMED' and lease_until>now())::bigint as active_worker_leases,
    count(*) filter (where status='CLAIMED' and lease_until<=now())::bigint as expired_worker_leases
  from ops.worker_runs
),
heartbeat_stats as (
  select
    count(*)::bigint as heartbeat_instances,
    count(*) filter (where status<>'STOPPED' and last_seen_at<now()-interval '5 minutes')::bigint as stale_heartbeat_instances
  from ops.worker_heartbeats
),
scheduler_stats as (
  select max(finished_at) filter (where result in ('PASS','PASS_WITH_ERRORS')) as scheduler_last_success_at from ops.scheduler_runs
)
select
  now() as as_of,
  e.total_events,e.completed_events,e.ready_events,e.retry_wait_events,e.approval_required_events,
  e.needs_review_events,e.dq_hold_events,e.dead_letter_events,
  c.ready_domain_commands,c.invalid_domain_commands,
  a.pending_approvals,l.active_worker_leases,l.expired_worker_leases,
  h.heartbeat_instances,h.stale_heartbeat_instances,
  e.oldest_unfinished_event_at,
  case when e.oldest_unfinished_event_at is null then null else extract(epoch from (now()-e.oldest_unfinished_event_at))::bigint end as oldest_unfinished_age_seconds,
  s.scheduler_last_success_at,
  case when s.scheduler_last_success_at is null then null else extract(epoch from (now()-s.scheduler_last_success_at))::bigint end as scheduler_age_seconds
from event_stats e
cross join command_stats c
cross join approval_stats a
cross join lease_stats l
cross join heartbeat_stats h
cross join scheduler_stats s;

create or replace function ops.capture_operations_snapshot(
  p_environment text default 'test',
  p_now timestamptz default now()
)
returns ops.operations_snapshots
language plpgsql
security definer
set search_path=''
as $$
declare
  v_snapshot ops.operations_snapshots;
  v_scheduler_last timestamptz;
  v_oldest timestamptz;
begin
  if p_environment is null or btrim(p_environment)='' then raise exception 'environment is required'; end if;

  select max(finished_at) filter (where result in ('PASS','PASS_WITH_ERRORS')) into v_scheduler_last from ops.scheduler_runs;
  select min(received_at) into v_oldest from ops.events where processing_state not in ('COMPLETED','REJECTED','CANCELLED');

  insert into ops.operations_snapshots(
    environment,captured_at,total_events,completed_events,ready_events,retry_wait_events,
    approval_required_events,needs_review_events,dq_hold_events,dead_letter_events,
    ready_domain_commands,invalid_domain_commands,pending_approvals,
    active_worker_leases,expired_worker_leases,heartbeat_instances,stale_heartbeat_instances,
    oldest_unfinished_event_at,oldest_unfinished_age_seconds,scheduler_last_success_at,scheduler_age_seconds
  )
  select
    btrim(p_environment),p_now,
    (select count(*) from ops.events),
    (select count(*) from ops.events where processing_state='COMPLETED'),
    (select count(*) from ops.events where processing_state in ('RECEIVED','RAW_STORED','PARSED','VALIDATED','ROUTED')),
    (select count(*) from ops.events where processing_state='RETRY_WAIT'),
    (select count(*) from ops.events where processing_state='APPROVAL_REQUIRED'),
    (select count(*) from ops.events where processing_state='NEEDS_REVIEW'),
    (select count(*) from ops.events where processing_state='DQ_HOLD'),
    (select count(*) from ops.events where processing_state='DEAD_LETTER'),
    (select count(*) from ops.domain_commands where validation_status='VALID' and apply_status='READY'),
    (select count(*) from ops.domain_commands where validation_status='INVALID'),
    (select count(*) from ops.approvals where status='PENDING'),
    (select count(*) from ops.worker_runs where status='CLAIMED' and lease_until>p_now),
    (select count(*) from ops.worker_runs where status='CLAIMED' and lease_until<=p_now),
    (select count(*) from ops.worker_heartbeats where environment=btrim(p_environment)),
    (select count(*) from ops.worker_heartbeats where environment=btrim(p_environment) and status<>'STOPPED' and last_seen_at<p_now-interval '5 minutes'),
    v_oldest,
    case when v_oldest is null then null else extract(epoch from (p_now-v_oldest))::bigint end,
    v_scheduler_last,
    case when v_scheduler_last is null then null else extract(epoch from (p_now-v_scheduler_last))::bigint end
  returning * into v_snapshot;

  return v_snapshot;
end;
$$;

create or replace view ops.alert_candidates_v with (security_invoker=true) as
select 'CRITICAL_EVENT_STALE'::text as alert_key,'SEV1'::text as severity,count(*)::bigint as affected_count,min(received_at) as first_seen_at,'unfinished event older than 15 minutes'::text as reason
from ops.events
where processing_state not in ('COMPLETED','REJECTED','CANCELLED') and received_at<now()-interval '15 minutes'
having count(*)>0
union all
select 'FINANCE_DEAD_LETTER','SEV1',count(*)::bigint,min(d.failed_at),'finance event in dead letter'
from ops.dead_letters d join ops.events e on e.event_pk=d.event_pk join ops.routing_rules r on r.event_type=e.event_type
where r.domain='Finance' having count(*)>0
union all
select 'EXPIRED_WORKER_LEASE','SEV1',count(*)::bigint,min(started_at),'claimed worker lease expired'
from ops.worker_runs where status='CLAIMED' and lease_until<=now() having count(*)>0
union all
select 'STALE_WORKER_HEARTBEAT','SEV2',count(*)::bigint,min(last_seen_at),'worker heartbeat older than 5 minutes'
from ops.worker_heartbeats where status<>'STOPPED' and last_seen_at<now()-interval '5 minutes' having count(*)>0
union all
select 'PENDING_APPROVAL_STALE','SEV2',count(*)::bigint,min(created_at),'approval pending longer than 24 hours'
from ops.approvals where status='PENDING' and created_at<now()-interval '24 hours' having count(*)>0
union all
select 'INVALID_DOMAIN_COMMAND','SEV2',count(*)::bigint,min(created_at),'invalid domain command requires review'
from ops.domain_commands where validation_status='INVALID' having count(*)>0
union all
select 'SCHEDULER_STALE','SEV1',1::bigint,max(finished_at),'scheduler has not succeeded in 15 minutes'
from ops.scheduler_runs
having coalesce(max(finished_at) filter (where result in ('PASS','PASS_WITH_ERRORS')),'-infinity'::timestamptz)<now()-interval '15 minutes';

create or replace function ops.part3_closeout_status()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_routes integer;
  v_workers integer;
  v_contracts integer;
  v_scheduler_active boolean;
  v_ready boolean;
begin
  select count(*) into v_routes from ops.routing_rules where active=true;
  select count(*) into v_workers from ops.worker_registry where enabled=true;
  select count(*) into v_contracts from ops.domain_worker_contracts where active=true;
  select exists(select 1 from cron.job where jobname='work-connect-scheduler-tick' and active=true) into v_scheduler_active;
  v_ready := v_routes>=20 and v_workers>=21 and v_contracts>=8 and v_scheduler_active;

  return jsonb_build_object(
    'part3_foundation_ready_for_part4',v_ready,
    'active_routing_rules',v_routes,
    'enabled_workers',v_workers,
    'active_domain_contracts',v_contracts,
    'scheduler_cron_active',v_scheduler_active,
    'business_master_apply_enabled',false,
    'external_channel_webhooks_enabled',false,
    'checked_at',now()
  );
end;
$$;

revoke all on ops.worker_heartbeats from anon, authenticated;
revoke all on ops.operations_snapshots from anon, authenticated;
revoke all on ops.worker_health_v from anon, authenticated;
revoke all on ops.operations_health_v from anon, authenticated;
revoke all on ops.alert_candidates_v from anon, authenticated;
revoke all on function ops.record_worker_heartbeat(text,text,text,text,text,jsonb,timestamptz) from public, anon, authenticated;
revoke all on function ops.capture_operations_snapshot(text,timestamptz) from public, anon, authenticated;
revoke all on function ops.part3_closeout_status() from public, anon, authenticated;

grant select, insert, update on ops.worker_heartbeats to service_role;
grant select, insert on ops.operations_snapshots to service_role;
grant select on ops.worker_health_v, ops.operations_health_v, ops.alert_candidates_v to service_role;
grant execute on function ops.record_worker_heartbeat(text,text,text,text,text,jsonb,timestamptz) to service_role;
grant execute on function ops.capture_operations_snapshot(text,timestamptz) to service_role;
grant execute on function ops.part3_closeout_status() to service_role;

commit;
