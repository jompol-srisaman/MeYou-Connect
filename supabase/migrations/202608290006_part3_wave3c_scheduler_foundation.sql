begin;

insert into ops.routing_rules(event_type, domain, route_key, material, evidence_expected, approval_policy)
values
  ('finance.invoice.due','Finance','ar_due_notification',false,false,'NONE')
on conflict (event_type) do update set
  domain = excluded.domain,
  route_key = excluded.route_key,
  material = excluded.material,
  evidence_expected = excluded.evidence_expected,
  approval_policy = excluded.approval_policy,
  active = true,
  updated_at = now();

create table if not exists ops.scheduled_signals (
  schedule_pk uuid primary key default gen_random_uuid(),
  schedule_key text not null unique,
  event_type text not null references ops.routing_rules(event_type) on delete restrict,
  due_at timestamptz not null,
  next_attempt_at timestamptz not null,
  source_timezone text not null default 'Asia/Bangkok',
  source_system text not null default 'scheduler',
  entity_type text,
  entity_id text,
  correlation_id text,
  causation_event_id text,
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'PENDING'
    check (status in ('PENDING','EMITTED','CANCELLED','FAILED')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  max_attempts integer not null default 5 check (max_attempts between 1 and 20),
  emitted_event_pk uuid references ops.events(event_pk) on delete restrict,
  emitted_at timestamptz,
  last_error text,
  cancelled_reason text,
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists scheduled_signals_due_idx
  on ops.scheduled_signals(status, next_attempt_at, due_at)
  where status = 'PENDING';
create index if not exists scheduled_signals_entity_idx
  on ops.scheduled_signals(entity_type, entity_id, status);
create index if not exists scheduled_signals_emitted_event_idx
  on ops.scheduled_signals(emitted_event_pk)
  where emitted_event_pk is not null;

create table if not exists ops.scheduler_runs (
  scheduler_run_pk uuid primary key default gen_random_uuid(),
  trigger_source text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  as_of timestamptz not null,
  scanned_count integer not null default 0,
  emitted_count integer not null default 0,
  failed_count integer not null default 0,
  retry_schedules_created integer not null default 0,
  result text not null default 'RUNNING'
    check (result in ('RUNNING','PASS','PASS_WITH_ERRORS','FAILED')),
  error_message text,
  created_at timestamptz not null default now()
);

create index if not exists scheduler_runs_started_idx
  on ops.scheduler_runs(started_at desc);

create or replace function ops.schedule_signal(
  p_schedule_key text,
  p_event_type text,
  p_due_at timestamptz,
  p_entity_type text default null,
  p_entity_id text default null,
  p_payload jsonb default '{}'::jsonb,
  p_source_system text default 'scheduler',
  p_source_timezone text default 'Asia/Bangkok',
  p_correlation_id text default null,
  p_causation_event_id text default null,
  p_created_by text default 'system',
  p_max_attempts integer default 5
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_rule ops.routing_rules;
  v_schedule ops.scheduled_signals;
  v_duplicate boolean := false;
begin
  if p_schedule_key is null or btrim(p_schedule_key) = '' then
    raise exception 'schedule_key is required';
  end if;
  if p_due_at is null then
    raise exception 'due_at is required';
  end if;
  if p_max_attempts < 1 or p_max_attempts > 20 then
    raise exception 'max_attempts must be between 1 and 20';
  end if;

  select * into v_rule
  from ops.routing_rules
  where event_type = p_event_type and active = true;

  if not found then
    raise exception 'unsupported or inactive scheduled event_type: %', p_event_type;
  end if;
  if v_rule.material then
    raise exception 'scheduled event_type % must be a non-material signal', p_event_type;
  end if;

  select * into v_schedule
  from ops.scheduled_signals
  where schedule_key = p_schedule_key;

  if found then
    v_duplicate := true;
    if v_schedule.status = 'PENDING' then
      update ops.scheduled_signals
      set due_at = p_due_at,
          next_attempt_at = p_due_at,
          source_timezone = coalesce(nullif(p_source_timezone,''),'Asia/Bangkok'),
          source_system = coalesce(nullif(p_source_system,''),'scheduler'),
          entity_type = p_entity_type,
          entity_id = p_entity_id,
          correlation_id = p_correlation_id,
          causation_event_id = p_causation_event_id,
          payload = coalesce(p_payload,'{}'::jsonb),
          created_by = coalesce(nullif(p_created_by,''), created_by),
          max_attempts = p_max_attempts,
          updated_at = now()
      where schedule_pk = v_schedule.schedule_pk
      returning * into v_schedule;
    end if;
  else
    insert into ops.scheduled_signals(
      schedule_key, event_type, due_at, next_attempt_at, source_timezone,
      source_system, entity_type, entity_id, correlation_id, causation_event_id,
      payload, created_by, max_attempts
    ) values (
      p_schedule_key, p_event_type, p_due_at, p_due_at,
      coalesce(nullif(p_source_timezone,''),'Asia/Bangkok'),
      coalesce(nullif(p_source_system,''),'scheduler'),
      p_entity_type, p_entity_id, p_correlation_id, p_causation_event_id,
      coalesce(p_payload,'{}'::jsonb), coalesce(nullif(p_created_by,''),'system'), p_max_attempts
    ) returning * into v_schedule;
  end if;

  return jsonb_build_object(
    'schedule_pk', v_schedule.schedule_pk,
    'schedule_key', v_schedule.schedule_key,
    'event_type', v_schedule.event_type,
    'due_at', v_schedule.due_at,
    'status', v_schedule.status,
    'duplicate_schedule', v_duplicate
  );
end;
$$;

create or replace function ops.cancel_schedule(
  p_schedule_key text,
  p_reason text,
  p_cancelled_by text default 'system'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule ops.scheduled_signals;
begin
  update ops.scheduled_signals
  set status = 'CANCELLED',
      cancelled_reason = concat_ws(' | ', nullif(p_reason,''), 'by=' || coalesce(nullif(p_cancelled_by,''),'system')),
      updated_at = now()
  where schedule_key = p_schedule_key
    and status = 'PENDING'
  returning * into v_schedule;

  if not found then
    select * into v_schedule from ops.scheduled_signals where schedule_key = p_schedule_key;
  end if;

  if not found then
    raise exception 'unknown schedule_key: %', p_schedule_key;
  end if;

  return jsonb_build_object(
    'schedule_key', v_schedule.schedule_key,
    'status', v_schedule.status,
    'cancelled_reason', v_schedule.cancelled_reason
  );
end;
$$;

create or replace function ops.schedule_followup_due(
  p_followup_ref text,
  p_due_at timestamptz,
  p_entity_type text default 'Placement',
  p_entity_id text default null,
  p_payload jsonb default '{}'::jsonb,
  p_created_by text default 'system'
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ops.schedule_signal(
    'followup:' || p_followup_ref,
    'followup.due',
    p_due_at,
    p_entity_type,
    p_entity_id,
    coalesce(p_payload,'{}'::jsonb) || jsonb_build_object('followup_ref', p_followup_ref),
    'scheduler',
    'Asia/Bangkok',
    null,
    null,
    p_created_by,
    5
  );
$$;

create or replace function ops.schedule_invoice_due(
  p_invoice_ref text,
  p_due_at timestamptz,
  p_client_id text default null,
  p_payload jsonb default '{}'::jsonb,
  p_created_by text default 'system'
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ops.schedule_signal(
    'invoice_due:' || p_invoice_ref,
    'finance.invoice.due',
    p_due_at,
    'Invoice',
    p_invoice_ref,
    coalesce(p_payload,'{}'::jsonb) || jsonb_build_object('invoice_ref', p_invoice_ref, 'client_id', p_client_id),
    'scheduler',
    'Asia/Bangkok',
    null,
    null,
    p_created_by,
    5
  );
$$;

create or replace function ops.schedule_notification(
  p_notification_key text,
  p_due_at timestamptz,
  p_entity_type text default null,
  p_entity_id text default null,
  p_payload jsonb default '{}'::jsonb,
  p_created_by text default 'system'
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select ops.schedule_signal(
    'notification:' || p_notification_key,
    'notification.requested',
    p_due_at,
    p_entity_type,
    p_entity_id,
    coalesce(p_payload,'{}'::jsonb),
    'scheduler',
    'Asia/Bangkok',
    null,
    null,
    p_created_by,
    5
  );
$$;

create or replace function ops.sync_retry_schedules(
  p_now timestamptz default now(),
  p_limit integer default 100
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_event ops.events;
  v_created integer := 0;
  v_key text;
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'limit must be between 1 and 1000';
  end if;

  for v_event in
    select *
    from ops.events
    where processing_state = 'RETRY_WAIT'
      and next_retry_at is not null
      and next_retry_at <= p_now
    order by next_retry_at, received_at
    limit p_limit
  loop
    v_key := 'retry:' || v_event.event_pk::text || ':' || v_event.processing_attempt::text || ':' || extract(epoch from v_event.next_retry_at)::bigint::text;

    insert into ops.scheduled_signals(
      schedule_key, event_type, due_at, next_attempt_at, source_timezone,
      source_system, entity_type, entity_id, correlation_id, causation_event_id,
      payload, created_by, max_attempts
    ) values (
      v_key, 'automation.retry_due', v_event.next_retry_at, v_event.next_retry_at,
      'Asia/Bangkok', 'scheduler', v_event.entity_type, v_event.entity_id,
      v_event.correlation_id, v_event.event_id,
      jsonb_build_object(
        'source_event_pk', v_event.event_pk,
        'source_event_id', v_event.event_id,
        'processing_attempt', v_event.processing_attempt,
        'retry_due_at', v_event.next_retry_at
      ),
      'scheduler', 5
    )
    on conflict (schedule_key) do nothing;

    if found then
      v_created := v_created + 1;
    end if;
  end loop;

  return v_created;
end;
$$;

create or replace function ops.run_due_schedules(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_trigger_source text default 'MANUAL'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run ops.scheduler_runs;
  v_schedule ops.scheduled_signals;
  v_event ops.events;
  v_scanned integer := 0;
  v_emitted integer := 0;
  v_failed integer := 0;
  v_attempt integer;
  v_event_id text;
  v_idempotency_key text;
begin
  if p_limit < 1 or p_limit > 1000 then
    raise exception 'limit must be between 1 and 1000';
  end if;

  insert into ops.scheduler_runs(trigger_source, as_of)
  values (coalesce(nullif(p_trigger_source,''),'MANUAL'), p_now)
  returning * into v_run;

  for v_schedule in
    select *
    from ops.scheduled_signals
    where status = 'PENDING'
      and due_at <= p_now
      and next_attempt_at <= p_now
    order by due_at, created_at
    for update skip locked
    limit p_limit
  loop
    v_scanned := v_scanned + 1;
    begin
      v_event_id := 'schedule:' || v_schedule.schedule_key;
      v_idempotency_key := 'schedule|' || v_schedule.schedule_key;

      v_event := ops.register_event(
        '2.1',
        v_schedule.source_system,
        v_event_id,
        v_idempotency_key,
        'schedule:' || v_schedule.schedule_pk::text,
        v_schedule.event_type,
        v_schedule.due_at,
        null,
        v_schedule.correlation_id,
        v_schedule.causation_event_id
      );

      update ops.events
      set entity_type = coalesce(entity_type, v_schedule.entity_type),
          entity_id = coalesce(entity_id, v_schedule.entity_id),
          updated_at = now()
      where event_pk = v_event.event_pk;

      update ops.scheduled_signals
      set status = 'EMITTED',
          emitted_event_pk = v_event.event_pk,
          emitted_at = now(),
          attempt_count = attempt_count + 1,
          last_error = null,
          updated_at = now()
      where schedule_pk = v_schedule.schedule_pk;

      v_emitted := v_emitted + 1;
    exception when others then
      v_attempt := v_schedule.attempt_count + 1;
      update ops.scheduled_signals
      set attempt_count = v_attempt,
          status = case when v_attempt >= v_schedule.max_attempts then 'FAILED' else 'PENDING' end,
          next_attempt_at = case
            when v_attempt >= v_schedule.max_attempts then next_attempt_at
            else p_now + make_interval(mins => least(60, 5 * v_attempt))
          end,
          last_error = left(sqlerrm, 2000),
          updated_at = now()
      where schedule_pk = v_schedule.schedule_pk;
      v_failed := v_failed + 1;
    end;
  end loop;

  update ops.scheduler_runs
  set finished_at = now(),
      scanned_count = v_scanned,
      emitted_count = v_emitted,
      failed_count = v_failed,
      result = case when v_failed = 0 then 'PASS' else 'PASS_WITH_ERRORS' end
  where scheduler_run_pk = v_run.scheduler_run_pk;

  return jsonb_build_object(
    'scheduler_run_pk', v_run.scheduler_run_pk,
    'trigger_source', coalesce(nullif(p_trigger_source,''),'MANUAL'),
    'as_of', p_now,
    'scanned_count', v_scanned,
    'emitted_count', v_emitted,
    'failed_count', v_failed
  );
exception when others then
  if v_run.scheduler_run_pk is not null then
    update ops.scheduler_runs
    set finished_at = now(), result = 'FAILED', error_message = left(sqlerrm, 2000)
    where scheduler_run_pk = v_run.scheduler_run_pk;
  end if;
  raise;
end;
$$;

create or replace function ops.scheduler_tick(
  p_now timestamptz default now(),
  p_limit integer default 100,
  p_trigger_source text default 'MANUAL'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_retry_created integer;
  v_result jsonb;
begin
  v_retry_created := ops.sync_retry_schedules(p_now, p_limit);
  v_result := ops.run_due_schedules(p_now, p_limit, p_trigger_source);

  update ops.scheduler_runs
  set retry_schedules_created = v_retry_created
  where scheduler_run_pk = (v_result->>'scheduler_run_pk')::uuid;

  return v_result || jsonb_build_object('retry_schedules_created', v_retry_created);
end;
$$;

create or replace function ops.get_scheduled_event_context(p_event_pk uuid)
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select jsonb_build_object(
    'schedule_pk', s.schedule_pk,
    'schedule_key', s.schedule_key,
    'event_type', s.event_type,
    'due_at', s.due_at,
    'entity_type', s.entity_type,
    'entity_id', s.entity_id,
    'payload', s.payload,
    'status', s.status,
    'emitted_at', s.emitted_at
  )
  from ops.scheduled_signals s
  where s.emitted_event_pk = p_event_pk;
$$;

revoke execute on function ops.schedule_signal(text,text,timestamptz,text,text,jsonb,text,text,text,text,text,integer) from public, anon, authenticated;
revoke execute on function ops.cancel_schedule(text,text,text) from public, anon, authenticated;
revoke execute on function ops.schedule_followup_due(text,timestamptz,text,text,jsonb,text) from public, anon, authenticated;
revoke execute on function ops.schedule_invoice_due(text,timestamptz,text,jsonb,text) from public, anon, authenticated;
revoke execute on function ops.schedule_notification(text,timestamptz,text,text,jsonb,text) from public, anon, authenticated;
revoke execute on function ops.sync_retry_schedules(timestamptz,integer) from public, anon, authenticated;
revoke execute on function ops.run_due_schedules(timestamptz,integer,text) from public, anon, authenticated;
revoke execute on function ops.scheduler_tick(timestamptz,integer,text) from public, anon, authenticated;
revoke execute on function ops.get_scheduled_event_context(uuid) from public, anon, authenticated;

revoke all on ops.scheduled_signals, ops.scheduler_runs from anon, authenticated;
grant select, insert, update, delete on ops.scheduled_signals, ops.scheduler_runs to service_role;
grant execute on function ops.schedule_signal(text,text,timestamptz,text,text,jsonb,text,text,text,text,text,integer) to service_role;
grant execute on function ops.cancel_schedule(text,text,text) to service_role;
grant execute on function ops.schedule_followup_due(text,timestamptz,text,text,jsonb,text) to service_role;
grant execute on function ops.schedule_invoice_due(text,timestamptz,text,jsonb,text) to service_role;
grant execute on function ops.schedule_notification(text,timestamptz,text,text,jsonb,text) to service_role;
grant execute on function ops.sync_retry_schedules(timestamptz,integer) to service_role;
grant execute on function ops.run_due_schedules(timestamptz,integer,text) to service_role;
grant execute on function ops.scheduler_tick(timestamptz,integer,text) to service_role;
grant execute on function ops.get_scheduled_event_context(uuid) to service_role;

commit;