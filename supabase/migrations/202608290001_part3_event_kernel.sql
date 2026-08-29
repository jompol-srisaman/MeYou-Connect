begin;

create extension if not exists pgcrypto;
create schema if not exists ops;

do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where n.nspname = 'ops' and t.typname = 'event_processing_state'
  ) then
    create type ops.event_processing_state as enum (
      'RECEIVED','RAW_STORED','PARSED','VALIDATED','ROUTED','APPLIED','COMPLETED',
      'NEEDS_REVIEW','DQ_HOLD','APPROVAL_REQUIRED','RETRY_WAIT','DEAD_LETTER',
      'REJECTED','CANCELLED'
    );
  end if;
end $$;

create table if not exists ops.raw_inputs (
  raw_input_id text primary key,
  received_at timestamptz not null default now(),
  channel text,
  sender_type text,
  sender_ref text,
  content_type text,
  original_ref text,
  raw_summary text,
  classification text,
  entity_type text,
  entity_id text,
  ai_parsed boolean not null default false,
  ai_confidence numeric(5,2),
  processing_status text,
  sensitive boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists ops.events (
  event_pk uuid primary key default gen_random_uuid(),
  schema_version text not null,
  source_system text not null,
  event_id text not null,
  idempotency_key text not null,
  trace_id text not null,
  correlation_id text,
  causation_event_id text,
  event_type text not null,
  occurred_at timestamptz not null,
  received_at timestamptz not null default now(),
  processing_state ops.event_processing_state not null default 'RECEIVED',
  processing_attempt integer not null default 0 check (processing_attempt >= 0),
  next_retry_at timestamptz,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  entity_type text,
  entity_id text,
  last_error_class text,
  last_error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_system, event_id),
  unique (idempotency_key)
);

create index if not exists events_processing_state_idx on ops.events(processing_state, received_at);
create index if not exists events_trace_idx on ops.events(trace_id);

create table if not exists ops.event_effects (
  effect_id uuid primary key default gen_random_uuid(),
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  effect_type text not null,
  effect_key text not null unique,
  entity_type text,
  entity_id text,
  effect_ref text,
  applied_at timestamptz not null default now()
);

create table if not exists ops.approvals (
  approval_id uuid primary key default gen_random_uuid(),
  event_pk uuid references ops.events(event_pk) on delete restrict,
  action_type text not null,
  entity_type text,
  entity_id text,
  requested_by text,
  status text not null default 'PENDING' check (status in ('PENDING','APPROVED','REJECTED','CANCELLED')),
  approved_by text,
  approved_at timestamptz,
  context jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists ops.dead_letters (
  dead_letter_id uuid primary key default gen_random_uuid(),
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  error_class text not null,
  error_message text,
  failed_at timestamptz not null default now(),
  replay_status text not null default 'PENDING' check (replay_status in ('PENDING','APPROVED','REPLAYED','CANCELLED')),
  reviewed_by text,
  reviewed_at timestamptz,
  unique(event_pk)
);

create table if not exists ops.data_quality_issues (
  dq_issue_id text primary key,
  entity_type text,
  entity_id text,
  field_name text,
  issue_type text,
  current_value text,
  incoming_value text,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  severity text,
  status text not null default 'OPEN',
  resolution text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function ops.register_event(
  p_schema_version text,
  p_source_system text,
  p_event_id text,
  p_idempotency_key text,
  p_trace_id text,
  p_event_type text,
  p_occurred_at timestamptz,
  p_raw_input_id text default null,
  p_correlation_id text default null,
  p_causation_event_id text default null
)
returns ops.events
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_event ops.events;
begin
  select * into v_event from ops.events where source_system = p_source_system and event_id = p_event_id;
  if found then return v_event; end if;

  select * into v_event from ops.events where idempotency_key = p_idempotency_key;
  if found then return v_event; end if;

  insert into ops.events (
    schema_version, source_system, event_id, idempotency_key, trace_id,
    correlation_id, causation_event_id, event_type, occurred_at, raw_input_id, processing_state
  ) values (
    p_schema_version, p_source_system, p_event_id, p_idempotency_key, p_trace_id,
    p_correlation_id, p_causation_event_id, p_event_type, p_occurred_at, p_raw_input_id,
    case when p_raw_input_id is null then 'RECEIVED'::ops.event_processing_state else 'RAW_STORED'::ops.event_processing_state end
  ) returning * into v_event;

  return v_event;
exception
  when unique_violation then
    select * into v_event from ops.events
    where (source_system = p_source_system and event_id = p_event_id) or idempotency_key = p_idempotency_key
    order by created_at limit 1;
    if found then return v_event; end if;
    raise;
end;
$$;

create or replace function ops.register_effect(
  p_event_pk uuid,
  p_effect_type text,
  p_effect_key text,
  p_entity_type text default null,
  p_entity_id text default null,
  p_effect_ref text default null
)
returns ops.event_effects
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_effect ops.event_effects;
begin
  insert into ops.event_effects (event_pk, effect_type, effect_key, entity_type, entity_id, effect_ref)
  values (p_event_pk, p_effect_type, p_effect_key, p_entity_type, p_entity_id, p_effect_ref)
  on conflict (effect_key) do nothing
  returning * into v_effect;

  if found then return v_effect; end if;

  select * into v_effect from ops.event_effects where effect_key = p_effect_key;
  return v_effect;
end;
$$;

commit;
