begin;

create table if not exists ops.worker_registry (
  worker_key text primary key,
  domain text not null,
  enabled boolean not null default true,
  default_lease_seconds integer not null default 60 check (default_lease_seconds between 15 and 900),
  default_batch_size integer not null default 20 check (default_batch_size between 1 and 200),
  max_retries integer not null default 3 check (max_retries between 0 and 10),
  description text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.worker_registry(worker_key, domain, description)
select distinct r.route_key, r.domain, 'Seeded from ops.routing_rules'
from ops.routing_rules r
where r.active = true
on conflict (worker_key) do update set
  domain = excluded.domain,
  enabled = true,
  updated_at = now();

create table if not exists ops.worker_runs (
  worker_run_pk uuid primary key default gen_random_uuid(),
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  worker_key text not null references ops.worker_registry(worker_key) on delete restrict,
  worker_instance text not null,
  lease_token uuid not null default gen_random_uuid() unique,
  lease_until timestamptz not null,
  status text not null default 'CLAIMED'
    check (status in ('CLAIMED','SUCCEEDED','FAILED','ABANDONED','CANCELLED')),
  attempt_no integer not null check (attempt_no >= 1),
  error_class text,
  error_message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists worker_runs_event_idx on ops.worker_runs(event_pk, started_at desc);
create index if not exists worker_runs_active_lease_idx on ops.worker_runs(status, lease_until)
  where status = 'CLAIMED';
create index if not exists worker_runs_worker_idx on ops.worker_runs(worker_key, started_at desc);

create unique index if not exists approvals_one_pending_action_uq
  on ops.approvals(event_pk, action_type)
  where status = 'PENDING';

alter table ops.approvals add column if not exists decision_notes text;
alter table ops.approvals add column if not exists updated_at timestamptz not null default now();

create or replace function ops.retry_delay_for_attempt(p_retry_no integer)
returns interval
language sql
immutable
security invoker
set search_path = ''
as $$
  select case
    when p_retry_no <= 1 then interval '1 minute'
    when p_retry_no = 2 then interval '5 minutes'
    else interval '15 minutes'
  end;
$$;

create or replace function ops.apply_failure_transition(
  p_event_pk uuid,
  p_worker_key text,
  p_error_class text,
  p_error_message text default null,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event ops.events;
  v_worker ops.worker_registry;
  v_class text := upper(coalesce(nullif(btrim(p_error_class),''),'UNKNOWN'));
  v_new_attempt integer;
  v_state ops.event_processing_state;
  v_retry_at timestamptz;
begin
  select * into v_event from ops.events where event_pk = p_event_pk for update;
  if not found then raise exception 'unknown event_pk: %', p_event_pk; end if;

  select * into v_worker from ops.worker_registry where worker_key = p_worker_key;
  if not found then raise exception 'unknown worker_key: %', p_worker_key; end if;

  v_new_attempt := v_event.processing_attempt + 1;
  v_retry_at := null;

  if v_class = 'TRANSIENT' then
    if v_event.processing_attempt < v_worker.max_retries then
      v_state := 'RETRY_WAIT';
      v_retry_at := p_now + ops.retry_delay_for_attempt(v_new_attempt);
    else
      v_state := 'DEAD_LETTER';
    end if;
  elsif v_class in ('VALIDATION','AUTH') then
    v_state := 'NEEDS_REVIEW';
  elsif v_class = 'CONFLICT' then
    v_state := 'DQ_HOLD';
  elsif v_class = 'PRIVACY' then
    v_state := 'REJECTED';
  elsif v_class = 'BUSINESS_RULE' then
    v_state := 'APPROVAL_REQUIRED';
  else
    v_state := 'NEEDS_REVIEW';
  end if;

  update ops.events
  set processing_attempt = v_new_attempt,
      processing_state = v_state,
      next_retry_at = v_retry_at,
      last_error_class = v_class,
      last_error_message = left(p_error_message, 2000),
      updated_at = now()
  where event_pk = p_event_pk;

  if v_state = 'DEAD_LETTER' then
    insert into ops.dead_letters(event_pk, error_class, error_message, failed_at)
    values (p_event_pk, v_class, left(p_error_message,2000), p_now)
    on conflict (event_pk) do update set
      error_class = excluded.error_class,
      error_message = excluded.error_message,
      failed_at = excluded.failed_at,
      replay_status = 'PENDING',
      reviewed_by = null,
      reviewed_at = null;
  end if;

  return jsonb_build_object(
    'event_pk', p_event_pk,
    'processing_state', v_state,
    'processing_attempt', v_new_attempt,
    'next_retry_at', v_retry_at,
    'error_class', v_class
  );
end;
$$;

create or replace function ops.reap_expired_worker_runs(
  p_now timestamptz default now(),
  p_limit integer default 100
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ops.worker_runs;
  v_count integer := 0;
begin
  if p_limit < 1 or p_limit > 1000 then raise exception 'limit must be between 1 and 1000'; end if;

  for v_run in
    select * from ops.worker_runs
    where status = 'CLAIMED' and lease_until <= p_now
    order by lease_until
    for update skip locked
    limit p_limit
  loop
    update ops.worker_runs
    set status = 'ABANDONED',
        error_class = 'TRANSIENT',
        error_message = 'worker lease expired',
        finished_at = p_now
    where worker_run_pk = v_run.worker_run_pk;

    perform ops.apply_failure_transition(
      v_run.event_pk,
      v_run.worker_key,
      'TRANSIENT',
      'worker lease expired',
      p_now
    );
    v_count := v_count + 1;
  end loop;

  return v_count;
end;
$$;

create or replace function ops.claim_events(
  p_worker_key text,
  p_worker_instance text,
  p_limit integer default null,
  p_lease_seconds integer default null,
  p_now timestamptz default now()
)
returns table(
  worker_run_pk uuid,
  lease_token uuid,
  lease_until timestamptz,
  event_pk uuid,
  event_id text,
  event_type text,
  processing_state ops.event_processing_state,
  processing_attempt integer,
  route_key text,
  raw_input_id text,
  entity_type text,
  entity_id text,
  trace_id text,
  correlation_id text,
  scheduled_payload jsonb,
  latest_approval_status text,
  latest_approval_action text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_worker ops.worker_registry;
  v_event record;
  v_run ops.worker_runs;
  v_limit integer;
  v_lease integer;
begin
  if p_worker_instance is null or btrim(p_worker_instance) = '' then
    raise exception 'worker_instance is required';
  end if;

  select * into v_worker from ops.worker_registry where worker_key = p_worker_key and enabled = true;
  if not found then raise exception 'unknown or disabled worker_key: %', p_worker_key; end if;

  v_limit := coalesce(p_limit, v_worker.default_batch_size);
  v_lease := coalesce(p_lease_seconds, v_worker.default_lease_seconds);
  if v_limit < 1 or v_limit > 200 then raise exception 'limit must be between 1 and 200'; end if;
  if v_lease < 15 or v_lease > 900 then raise exception 'lease_seconds must be between 15 and 900'; end if;

  perform ops.reap_expired_worker_runs(p_now, 100);

  for v_event in
    select e.*,
           r.route_key,
           ss.payload as scheduled_payload,
           a.status as latest_approval_status,
           a.action_type as latest_approval_action
    from ops.events e
    join ops.routing_rules r on r.event_type = e.event_type and r.active = true
    left join ops.scheduled_signals ss on ss.emitted_event_pk = e.event_pk
    left join lateral (
      select ap.status, ap.action_type
      from ops.approvals ap
      where ap.event_pk = e.event_pk
      order by ap.created_at desc
      limit 1
    ) a on true
    where r.route_key = p_worker_key
      and e.processing_state in ('RECEIVED','RAW_STORED','PARSED','VALIDATED','ROUTED')
      and not exists (
        select 1 from ops.worker_runs wr
        where wr.event_pk = e.event_pk
          and wr.status = 'CLAIMED'
          and wr.lease_until > p_now
      )
    order by e.received_at, e.created_at
    for update of e skip locked
    limit v_limit
  loop
    update ops.events
    set processing_state = 'ROUTED', updated_at = now()
    where ops.events.event_pk = v_event.event_pk;

    insert into ops.worker_runs(
      event_pk, worker_key, worker_instance, lease_until, attempt_no
    ) values (
      v_event.event_pk, p_worker_key, p_worker_instance,
      p_now + make_interval(secs => v_lease),
      v_event.processing_attempt + 1
    ) returning * into v_run;

    worker_run_pk := v_run.worker_run_pk;
    lease_token := v_run.lease_token;
    lease_until := v_run.lease_until;
    event_pk := v_event.event_pk;
    event_id := v_event.event_id;
    event_type := v_event.event_type;
    processing_state := 'ROUTED';
    processing_attempt := v_event.processing_attempt;
    route_key := v_event.route_key;
    raw_input_id := v_event.raw_input_id;
    entity_type := v_event.entity_type;
    entity_id := v_event.entity_id;
    trace_id := v_event.trace_id;
    correlation_id := v_event.correlation_id;
    scheduled_payload := v_event.scheduled_payload;
    latest_approval_status := v_event.latest_approval_status;
    latest_approval_action := v_event.latest_approval_action;
    return next;
  end loop;
end;
$$;

create or replace function ops.validate_worker_lease(
  p_worker_run_pk uuid,
  p_lease_token uuid,
  p_now timestamptz default now()
)
returns ops.worker_runs
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ops.worker_runs;
begin
  select * into v_run from ops.worker_runs
  where worker_run_pk = p_worker_run_pk
    and lease_token = p_lease_token
  for update;

  if not found then raise exception 'invalid worker lease'; end if;
  if v_run.status <> 'CLAIMED' then raise exception 'worker run is not active: %', v_run.status; end if;
  if v_run.lease_until <= p_now then raise exception 'worker lease expired'; end if;
  return v_run;
end;
$$;

create or replace function ops.finish_event_success(
  p_worker_run_pk uuid,
  p_lease_token uuid,
  p_effect_type text default null,
  p_effect_key text default null,
  p_entity_type text default null,
  p_entity_id text default null,
  p_effect_ref text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ops.worker_runs;
  v_effect ops.event_effects;
begin
  v_run := ops.validate_worker_lease(p_worker_run_pk, p_lease_token, p_now);

  if p_effect_key is not null then
    if p_effect_type is null then raise exception 'effect_type required when effect_key is supplied'; end if;
    v_effect := ops.register_effect(
      v_run.event_pk, p_effect_type, p_effect_key,
      p_entity_type, p_entity_id, p_effect_ref
    );
  end if;

  update ops.events
  set processing_state = 'COMPLETED',
      next_retry_at = null,
      last_error_class = null,
      last_error_message = null,
      entity_type = coalesce(p_entity_type, entity_type),
      entity_id = coalesce(p_entity_id, entity_id),
      updated_at = now()
  where event_pk = v_run.event_pk;

  update ops.worker_runs
  set status = 'SUCCEEDED',
      finished_at = p_now,
      metadata = coalesce(p_metadata,'{}'::jsonb)
  where worker_run_pk = p_worker_run_pk;

  return jsonb_build_object(
    'event_pk', v_run.event_pk,
    'processing_state', 'COMPLETED',
    'worker_run_pk', p_worker_run_pk,
    'effect_id', case when p_effect_key is null then null else v_effect.effect_id end,
    'effect_key', case when p_effect_key is null then null else v_effect.effect_key end
  );
end;
$$;

create or replace function ops.finish_event_failure(
  p_worker_run_pk uuid,
  p_lease_token uuid,
  p_error_class text,
  p_error_message text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ops.worker_runs;
  v_result jsonb;
begin
  v_run := ops.validate_worker_lease(p_worker_run_pk, p_lease_token, p_now);

  v_result := ops.apply_failure_transition(
    v_run.event_pk, v_run.worker_key, p_error_class, p_error_message, p_now
  );

  update ops.worker_runs
  set status = 'FAILED',
      error_class = upper(coalesce(nullif(btrim(p_error_class),''),'UNKNOWN')),
      error_message = left(p_error_message,2000),
      finished_at = p_now,
      metadata = coalesce(p_metadata,'{}'::jsonb)
  where worker_run_pk = p_worker_run_pk;

  return v_result || jsonb_build_object('worker_run_pk', p_worker_run_pk);
end;
$$;

create or replace function ops.request_event_approval(
  p_worker_run_pk uuid,
  p_lease_token uuid,
  p_action_type text,
  p_requested_by text,
  p_context jsonb default '{}'::jsonb,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ops.worker_runs;
  v_approval ops.approvals;
  v_duplicate boolean := false;
begin
  v_run := ops.validate_worker_lease(p_worker_run_pk, p_lease_token, p_now);
  if p_action_type is null or btrim(p_action_type) = '' then raise exception 'action_type required'; end if;
  if p_requested_by is null or btrim(p_requested_by) = '' then raise exception 'requested_by required'; end if;

  select * into v_approval
  from ops.approvals
  where event_pk = v_run.event_pk
    and action_type = p_action_type
    and status in ('PENDING','APPROVED')
  order by created_at desc
  limit 1;

  if found then
    v_duplicate := true;
  else
    insert into ops.approvals(event_pk, action_type, requested_by, status, context, created_at, updated_at)
    values (v_run.event_pk, p_action_type, p_requested_by, 'PENDING', coalesce(p_context,'{}'::jsonb), p_now, p_now)
    returning * into v_approval;
  end if;

  update ops.events
  set processing_state = case when v_approval.status = 'APPROVED' then 'ROUTED'::ops.event_processing_state else 'APPROVAL_REQUIRED'::ops.event_processing_state end,
      updated_at = now()
  where event_pk = v_run.event_pk;

  update ops.worker_runs
  set status = 'SUCCEEDED', finished_at = p_now,
      metadata = jsonb_build_object('approval_id', v_approval.approval_id, 'approval_status', v_approval.status)
  where worker_run_pk = p_worker_run_pk;

  return jsonb_build_object(
    'approval_id', v_approval.approval_id,
    'event_pk', v_run.event_pk,
    'action_type', v_approval.action_type,
    'status', v_approval.status,
    'duplicate_approval', v_duplicate
  );
end;
$$;

create or replace function ops.decide_approval(
  p_approval_id uuid,
  p_decision text,
  p_decided_by text,
  p_notes text default null,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_approval ops.approvals;
  v_decision text := upper(coalesce(nullif(btrim(p_decision),''),''));
  v_event_state ops.event_processing_state;
begin
  if v_decision not in ('APPROVED','REJECTED') then raise exception 'decision must be APPROVED or REJECTED'; end if;
  if p_decided_by is null or btrim(p_decided_by) = '' then raise exception 'decided_by required'; end if;

  select * into v_approval from ops.approvals where approval_id = p_approval_id for update;
  if not found then raise exception 'unknown approval_id: %', p_approval_id; end if;
  if v_approval.status <> 'PENDING' then
    return jsonb_build_object('approval_id', v_approval.approval_id, 'status', v_approval.status, 'duplicate_decision', true);
  end if;

  update ops.approvals
  set status = v_decision,
      approved_by = p_decided_by,
      approved_at = p_now,
      decision_notes = p_notes,
      updated_at = p_now
  where approval_id = p_approval_id
  returning * into v_approval;

  v_event_state := case when v_decision = 'APPROVED' then 'ROUTED'::ops.event_processing_state else 'CANCELLED'::ops.event_processing_state end;

  update ops.events
  set processing_state = v_event_state, updated_at = now()
  where event_pk = v_approval.event_pk;

  return jsonb_build_object(
    'approval_id', v_approval.approval_id,
    'event_pk', v_approval.event_pk,
    'status', v_approval.status,
    'event_state', v_event_state,
    'duplicate_decision', false
  );
end;
$$;

create or replace function ops.process_retry_due(
  p_worker_run_pk uuid,
  p_lease_token uuid,
  p_now timestamptz default now()
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ops.worker_runs;
  v_signal ops.scheduled_signals;
  v_source_event_pk uuid;
  v_source ops.events;
begin
  v_run := ops.validate_worker_lease(p_worker_run_pk, p_lease_token, p_now);

  select * into v_signal
  from ops.scheduled_signals
  where emitted_event_pk = v_run.event_pk
  limit 1;

  if not found or v_signal.event_type <> 'automation.retry_due' then
    raise exception 'worker run is not an automation.retry_due signal';
  end if;

  begin
    v_source_event_pk := (v_signal.payload->>'source_event_pk')::uuid;
  exception when others then
    raise exception 'retry signal missing valid source_event_pk';
  end;

  select * into v_source from ops.events where event_pk = v_source_event_pk for update;
  if not found then raise exception 'retry source event not found'; end if;

  if v_source.processing_state = 'RETRY_WAIT' and (v_source.next_retry_at is null or v_source.next_retry_at <= p_now) then
    update ops.events
    set processing_state = 'ROUTED',
        next_retry_at = null,
        updated_at = now()
    where event_pk = v_source_event_pk;
  end if;

  update ops.events set processing_state = 'COMPLETED', updated_at = now() where event_pk = v_run.event_pk;
  update ops.worker_runs set status = 'SUCCEEDED', finished_at = p_now,
      metadata = jsonb_build_object('released_source_event_pk', v_source_event_pk)
  where worker_run_pk = p_worker_run_pk;

  return jsonb_build_object(
    'retry_signal_event_pk', v_run.event_pk,
    'source_event_pk', v_source_event_pk,
    'source_event_state', (select processing_state from ops.events where event_pk = v_source_event_pk),
    'retry_signal_state', 'COMPLETED'
  );
end;
$$;

create or replace view ops.worker_backlog_v as
select
  r.route_key as worker_key,
  r.domain,
  count(*) filter (where e.processing_state in ('RECEIVED','RAW_STORED','PARSED','VALIDATED','ROUTED')) as ready_count,
  count(*) filter (where e.processing_state = 'RETRY_WAIT') as retry_wait_count,
  count(*) filter (where e.processing_state = 'APPROVAL_REQUIRED') as approval_wait_count,
  count(*) filter (where e.processing_state = 'DEAD_LETTER') as dead_letter_count,
  min(e.received_at) filter (where e.processing_state in ('RECEIVED','RAW_STORED','PARSED','VALIDATED','ROUTED')) as oldest_ready_at
from ops.routing_rules r
left join ops.events e on e.event_type = r.event_type
where r.active = true
group by r.route_key, r.domain;

revoke execute on function ops.retry_delay_for_attempt(integer) from public, anon, authenticated;
revoke execute on function ops.apply_failure_transition(uuid,text,text,text,timestamptz) from public, anon, authenticated;
revoke execute on function ops.reap_expired_worker_runs(timestamptz,integer) from public, anon, authenticated;
revoke execute on function ops.claim_events(text,text,integer,integer,timestamptz) from public, anon, authenticated;
revoke execute on function ops.validate_worker_lease(uuid,uuid,timestamptz) from public, anon, authenticated;
revoke execute on function ops.finish_event_success(uuid,uuid,text,text,text,text,text,jsonb,timestamptz) from public, anon, authenticated;
revoke execute on function ops.finish_event_failure(uuid,uuid,text,text,jsonb,timestamptz) from public, anon, authenticated;
revoke execute on function ops.request_event_approval(uuid,uuid,text,text,jsonb,timestamptz) from public, anon, authenticated;
revoke execute on function ops.decide_approval(uuid,text,text,text,timestamptz) from public, anon, authenticated;
revoke execute on function ops.process_retry_due(uuid,uuid,timestamptz) from public, anon, authenticated;
revoke all on ops.worker_registry, ops.worker_runs from anon, authenticated;
revoke all on ops.worker_backlog_v from anon, authenticated;

grant select, insert, update, delete on ops.worker_registry, ops.worker_runs to service_role;
grant select on ops.worker_backlog_v to service_role;
grant execute on function ops.retry_delay_for_attempt(integer) to service_role;
grant execute on function ops.apply_failure_transition(uuid,text,text,text,timestamptz) to service_role;
grant execute on function ops.reap_expired_worker_runs(timestamptz,integer) to service_role;
grant execute on function ops.claim_events(text,text,integer,integer,timestamptz) to service_role;
grant execute on function ops.validate_worker_lease(uuid,uuid,timestamptz) to service_role;
grant execute on function ops.finish_event_success(uuid,uuid,text,text,text,text,text,jsonb,timestamptz) to service_role;
grant execute on function ops.finish_event_failure(uuid,uuid,text,text,jsonb,timestamptz) to service_role;
grant execute on function ops.request_event_approval(uuid,uuid,text,text,jsonb,timestamptz) to service_role;
grant execute on function ops.decide_approval(uuid,text,text,text,timestamptz) to service_role;
grant execute on function ops.process_retry_due(uuid,uuid,timestamptz) to service_role;

commit;
