begin;

alter table ops.raw_inputs add column if not exists source_system text;
alter table ops.raw_inputs add column if not exists source_account_ref text;
alter table ops.raw_inputs add column if not exists thread_id text;
alter table ops.raw_inputs add column if not exists message_id text;
alter table ops.raw_inputs add column if not exists entity_type_hint text;
alter table ops.raw_inputs add column if not exists entity_id_if_known text;
alter table ops.raw_inputs add column if not exists natural_language_summary text;
alter table ops.raw_inputs add column if not exists consent_signal text;
alter table ops.raw_inputs add column if not exists metadata jsonb not null default '{}'::jsonb;

create unique index if not exists raw_inputs_source_ref_uq
  on ops.raw_inputs(source_system, coalesce(source_account_ref, ''), original_ref)
  where source_system is not null and original_ref is not null;

create table if not exists ops.routing_rules (
  event_type text primary key,
  domain text not null,
  route_key text not null,
  material boolean not null default true,
  evidence_expected boolean not null default false,
  approval_policy text not null default 'NONE',
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.routing_rules(event_type, domain, route_key, material, evidence_expected, approval_policy)
values
  ('candidate.lead.received','Candidate','candidate_intake',true,false,'NONE'),
  ('candidate.profile.updated','Candidate','candidate_worker',true,false,'NONE'),
  ('candidate.consent.received','Consent','consent_worker',true,true,'REVIEW_IF_AMBIGUOUS'),
  ('partner.referral.received','Partner','attribution_worker',true,true,'NONE'),
  ('client.demand.received','Client/Job','client_job_worker',true,true,'NONE'),
  ('job.detail.confirmed','Job','job_worker',true,true,'NONE'),
  ('placement.created','Placement','placement_worker',true,false,'NONE'),
  ('placement.milestone.reached','Placement','placement_finance_followup_router',true,true,'REVIEW_IF_CONFLICT'),
  ('followup.due','Follow-up','followup_notification',false,false,'NONE'),
  ('followup.response.received','Follow-up','followup_worker',true,false,'REVIEW_FOR_EXCEPTION'),
  ('finance.invoice.issued','Finance','ar_worker',true,true,'HUMAN_APPROVAL_IF_ISSUE_ACTION'),
  ('finance.payment_evidence.received','Finance','finance_reconciliation',true,true,'NONE'),
  ('finance.collection.confirmed','Finance','finance_accounting',true,true,'REVIEW_IF_NO_DETERMINISTIC_MATCH'),
  ('commission.eligible','Commission','commission_worker',true,true,'NONE'),
  ('commission.payment.requested','Commission','approval_payment_prep',true,true,'FOUNDER_APPROVAL'),
  ('file.uploaded','Evidence','file_evidence_worker',true,true,'NONE'),
  ('evidence.registered','Evidence','domain_router',true,true,'NONE'),
  ('data.conflict.detected','Data Quality','dq_review',true,true,'HUMAN_REVIEW'),
  ('notification.requested','Notification','notification_worker',false,false,'NONE'),
  ('automation.retry_due','System','retry_router',false,false,'NONE')
on conflict (event_type) do update set
  domain = excluded.domain,
  route_key = excluded.route_key,
  material = excluded.material,
  evidence_expected = excluded.evidence_expected,
  approval_policy = excluded.approval_policy,
  active = true,
  updated_at = now();

create table if not exists ops.file_intake (
  file_intake_pk uuid primary key default gen_random_uuid(),
  raw_input_id text not null references ops.raw_inputs(raw_input_id) on delete restrict,
  source_system text not null,
  source_account_ref text,
  provider_file_ref text not null,
  original_filename text,
  content_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'),
  mirror_status text not null default 'SOURCE_ONLY'
    check (mirror_status in ('SOURCE_ONLY','MIRRORED','SOURCE_NOT_MIRRORED','FAILED')),
  sensitive boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists file_intake_source_ref_uq
  on ops.file_intake(source_system, coalesce(source_account_ref, ''), provider_file_ref);
create index if not exists file_intake_raw_input_id_idx on ops.file_intake(raw_input_id);

create table if not exists ops.replay_requests (
  replay_request_pk uuid primary key default gen_random_uuid(),
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  requested_by text not null,
  reason text not null,
  status text not null default 'PENDING'
    check (status in ('PENDING','APPROVED','REPLAYED','REJECTED','CANCELLED')),
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists replay_requests_one_pending_uq
  on ops.replay_requests(event_pk)
  where status = 'PENDING';
create index if not exists replay_requests_status_idx on ops.replay_requests(status, created_at);

create or replace function ops.get_event_route(p_event_type text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select jsonb_build_object(
    'event_type', r.event_type,
    'domain', r.domain,
    'route_key', r.route_key,
    'material', r.material,
    'evidence_expected', r.evidence_expected,
    'approval_policy', r.approval_policy,
    'active', r.active
  )
  from ops.routing_rules r
  where r.event_type = p_event_type and r.active = true;
$$;

create or replace function ops.ingest_material_event(
  p_raw_input_id text,
  p_schema_version text,
  p_source_system text,
  p_channel text,
  p_event_id text,
  p_idempotency_key text,
  p_trace_id text,
  p_event_type text,
  p_occurred_at timestamptz,
  p_sender_type text,
  p_content_type text,
  p_original_ref text,
  p_sender_ref text default null,
  p_source_account_ref text default null,
  p_thread_id text default null,
  p_message_id text default null,
  p_raw_summary text default null,
  p_entity_type_hint text default null,
  p_entity_id_if_known text default null,
  p_ai_parsed boolean default false,
  p_ai_confidence numeric default null,
  p_sensitive boolean default false,
  p_consent_signal text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_correlation_id text default null,
  p_causation_event_id text default null
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_route ops.routing_rules;
  v_event ops.events;
  v_existing_raw ops.raw_inputs;
  v_duplicate_event boolean := false;
begin
  if p_raw_input_id is null or btrim(p_raw_input_id) = '' then
    raise exception 'raw_input_id is required for material ingestion';
  end if;
  if p_source_system is null or btrim(p_source_system) = '' then
    raise exception 'source_system is required';
  end if;
  if p_event_id is null or btrim(p_event_id) = '' then
    raise exception 'event_id is required';
  end if;
  if p_idempotency_key is null or btrim(p_idempotency_key) = '' then
    raise exception 'idempotency_key is required';
  end if;
  if p_trace_id is null or btrim(p_trace_id) = '' then
    raise exception 'trace_id is required';
  end if;
  if p_original_ref is null or btrim(p_original_ref) = '' then
    raise exception 'original_ref is required for provenance';
  end if;

  select * into v_route
  from ops.routing_rules
  where event_type = p_event_type and active = true;

  if not found then
    raise exception 'unsupported or inactive event_type: %', p_event_type;
  end if;

  if v_route.material is false then
    raise exception 'event_type % is non-material; use a non-material event path', p_event_type;
  end if;

  select * into v_existing_raw
  from ops.raw_inputs
  where source_system = p_source_system
    and coalesce(source_account_ref, '') = coalesce(p_source_account_ref, '')
    and original_ref = p_original_ref
  limit 1;

  if found and v_existing_raw.raw_input_id <> p_raw_input_id then
    raise exception 'source provenance already bound to raw_input_id %', v_existing_raw.raw_input_id;
  end if;

  insert into ops.raw_inputs (
    raw_input_id, received_at, source_system, channel, source_account_ref,
    thread_id, message_id, sender_type, sender_ref, content_type, original_ref,
    raw_summary, natural_language_summary, classification, entity_type_hint,
    entity_id_if_known, ai_parsed, ai_confidence, processing_status, sensitive,
    consent_signal, metadata
  ) values (
    p_raw_input_id, now(), p_source_system, p_channel, p_source_account_ref,
    p_thread_id, p_message_id, p_sender_type, p_sender_ref, p_content_type, p_original_ref,
    p_raw_summary, p_raw_summary, p_event_type, p_entity_type_hint,
    p_entity_id_if_known, p_ai_parsed, p_ai_confidence, 'RAW_STORED', p_sensitive,
    p_consent_signal, coalesce(p_metadata, '{}'::jsonb)
  )
  on conflict (raw_input_id) do nothing;

  select exists(
    select 1 from ops.events
    where (source_system = p_source_system and event_id = p_event_id)
       or idempotency_key = p_idempotency_key
  ) into v_duplicate_event;

  v_event := ops.register_event(
    p_schema_version,
    p_source_system,
    p_event_id,
    p_idempotency_key,
    p_trace_id,
    p_event_type,
    p_occurred_at,
    p_raw_input_id,
    p_correlation_id,
    p_causation_event_id
  );

  return jsonb_build_object(
    'raw_input_id', p_raw_input_id,
    'event_pk', v_event.event_pk,
    'event_id', v_event.event_id,
    'processing_state', v_event.processing_state,
    'duplicate_event', v_duplicate_event,
    'route_key', v_route.route_key,
    'domain', v_route.domain,
    'evidence_expected', v_route.evidence_expected,
    'approval_policy', v_route.approval_policy
  );
end;
$$;

create or replace function ops.register_file_intake(
  p_raw_input_id text,
  p_source_system text,
  p_provider_file_ref text,
  p_source_account_ref text default null,
  p_original_filename text default null,
  p_content_type text default null,
  p_size_bytes bigint default null,
  p_checksum_sha256 text default null,
  p_mirror_status text default 'SOURCE_ONLY',
  p_sensitive boolean default false,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_file ops.file_intake;
  v_duplicate boolean := false;
begin
  if not exists (select 1 from ops.raw_inputs where raw_input_id = p_raw_input_id) then
    raise exception 'unknown raw_input_id: %', p_raw_input_id;
  end if;

  select * into v_file
  from ops.file_intake
  where source_system = p_source_system
    and coalesce(source_account_ref, '') = coalesce(p_source_account_ref, '')
    and provider_file_ref = p_provider_file_ref
  limit 1;

  if found then
    v_duplicate := true;
  else
    insert into ops.file_intake(
      raw_input_id, source_system, source_account_ref, provider_file_ref,
      original_filename, content_type, size_bytes, checksum_sha256,
      mirror_status, sensitive, metadata
    ) values (
      p_raw_input_id, p_source_system, p_source_account_ref, p_provider_file_ref,
      p_original_filename, p_content_type, p_size_bytes, p_checksum_sha256,
      p_mirror_status, p_sensitive, coalesce(p_metadata, '{}'::jsonb)
    ) returning * into v_file;
  end if;

  return jsonb_build_object(
    'file_intake_pk', v_file.file_intake_pk,
    'raw_input_id', v_file.raw_input_id,
    'duplicate_file', v_duplicate,
    'mirror_status', v_file.mirror_status
  );
end;
$$;

create or replace function ops.request_manual_replay(
  p_event_pk uuid,
  p_requested_by text,
  p_reason text
)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_event ops.events;
  v_request ops.replay_requests;
  v_duplicate boolean := false;
begin
  select * into v_event from ops.events where event_pk = p_event_pk;
  if not found then
    raise exception 'unknown event_pk: %', p_event_pk;
  end if;

  if v_event.processing_state not in ('DEAD_LETTER','NEEDS_REVIEW','RETRY_WAIT') then
    raise exception 'event state % is not eligible for manual replay request', v_event.processing_state;
  end if;

  select * into v_request
  from ops.replay_requests
  where event_pk = p_event_pk and status = 'PENDING'
  limit 1;

  if found then
    v_duplicate := true;
  else
    insert into ops.replay_requests(event_pk, requested_by, reason)
    values (p_event_pk, p_requested_by, p_reason)
    returning * into v_request;
  end if;

  return jsonb_build_object(
    'replay_request_pk', v_request.replay_request_pk,
    'event_pk', v_request.event_pk,
    'status', v_request.status,
    'duplicate_request', v_duplicate
  );
end;
$$;

revoke execute on all functions in schema ops from public, anon, authenticated;
revoke all on all tables in schema ops from anon, authenticated;
grant usage on schema ops to service_role;
grant select, insert, update, delete on all tables in schema ops to service_role;
grant execute on all functions in schema ops to service_role;

commit;
