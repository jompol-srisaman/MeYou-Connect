create table if not exists analytics.appointment_outcome_fact (
  appointment_fact_pk uuid primary key default gen_random_uuid(),
  fact_key text not null unique,
  placement_id text not null references core.placements(placement_id) on delete restrict,
  appointment_at timestamptz not null,
  outcome text not null check (outcome in ('SHOW','NO_SHOW','CANCELLED','RESCHEDULED','UNKNOWN','NEEDS_REVIEW')),
  observed_at timestamptz not null,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  source_followup_id text references core.followups(followup_id) on delete restrict,
  source_kind text not null check (source_kind in ('EVENT','FOLLOWUP','MANUAL_VERIFIED','MIGRATION_VERIFIED')),
  verified boolean not null default false,
  actor_service text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint appointment_outcome_provenance_ck check (evidence_id is not null or raw_input_id is not null or source_followup_id is not null),
  constraint appointment_outcome_verified_ck check ((not verified) or evidence_id is not null or source_kind='MANUAL_VERIFIED'),
  constraint appointment_outcome_no_secret_keys_ck check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists appointment_outcome_placement_time_idx on analytics.appointment_outcome_fact(placement_id,appointment_at,observed_at desc);
create index if not exists appointment_outcome_evidence_idx on analytics.appointment_outcome_fact(evidence_id);
create index if not exists appointment_outcome_raw_idx on analytics.appointment_outcome_fact(raw_input_id);
create index if not exists appointment_outcome_followup_idx on analytics.appointment_outcome_fact(source_followup_id);

create table if not exists analytics.partner_attribution_fact (
  attribution_fact_pk uuid primary key default gen_random_uuid(),
  fact_key text not null unique,
  candidate_id text not null references core.candidates(candidate_id) on delete restrict,
  partner_id text not null references core.partners(partner_id) on delete restrict,
  attributed_at timestamptz not null,
  attribution_status text not null check (attribution_status in ('APPROVED','REJECTED','NEEDS_REVIEW')),
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  source_kind text not null check (source_kind in ('EVENT','RAW_INPUT','MANUAL_VERIFIED','MIGRATION_VERIFIED')),
  approved_by text,
  approved_at timestamptz,
  actor_service text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint partner_attribution_provenance_ck check (evidence_id is not null or raw_input_id is not null),
  constraint partner_attribution_approved_ck check (attribution_status<>'APPROVED' or ((evidence_id is not null or raw_input_id is not null) and approved_by is not null and approved_at is not null)),
  constraint partner_attribution_no_secret_keys_ck check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists partner_attribution_candidate_time_idx on analytics.partner_attribution_fact(candidate_id,attributed_at desc);
create index if not exists partner_attribution_partner_time_idx on analytics.partner_attribution_fact(partner_id,attributed_at desc);
create index if not exists partner_attribution_evidence_idx on analytics.partner_attribution_fact(evidence_id);
create index if not exists partner_attribution_raw_idx on analytics.partner_attribution_fact(raw_input_id);

create or replace function analytics.record_stage_transition(
  p_entity_type text,
  p_entity_id text,
  p_from_stage text,
  p_to_stage text,
  p_occurred_at timestamptz,
  p_source_event_pk uuid default null,
  p_raw_input_id text default null,
  p_evidence_id text default null,
  p_actor_service text default 'SYSTEM',
  p_source_kind text default 'EVENT',
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_pk uuid;
begin
  if p_entity_type is null or p_entity_id is null or p_to_stage is null or p_occurred_at is null then raise exception 'STAGE_TRANSITION_REQUIRED_FIELDS'; end if;
  if p_source_event_pk is null and p_raw_input_id is null and p_evidence_id is null then raise exception 'STAGE_TRANSITION_PROVENANCE_REQUIRED'; end if;
  select transition_pk into v_pk
  from analytics.stage_transition_fact
  where entity_type=p_entity_type and entity_id=p_entity_id and coalesce(from_stage,'')=coalesce(p_from_stage,'') and to_stage=p_to_stage
    and occurred_at=p_occurred_at and source_event_pk is not distinct from p_source_event_pk
    and raw_input_id is not distinct from p_raw_input_id and evidence_id is not distinct from p_evidence_id
  order by created_at limit 1;
  if v_pk is not null then return v_pk; end if;
  insert into analytics.stage_transition_fact(entity_type,entity_id,from_stage,to_stage,occurred_at,source_event_pk,raw_input_id,evidence_id,actor_service,valid_transition,source_kind,metadata)
  values(p_entity_type,p_entity_id,p_from_stage,p_to_stage,p_occurred_at,p_source_event_pk,p_raw_input_id,p_evidence_id,p_actor_service,true,p_source_kind,coalesce(p_metadata,'{}'::jsonb))
  returning transition_pk into v_pk;
  return v_pk;
end
$function$;

create or replace function analytics.record_appointment_outcome(
  p_placement_id text,
  p_appointment_at timestamptz,
  p_outcome text,
  p_observed_at timestamptz,
  p_evidence_id text default null,
  p_raw_input_id text default null,
  p_source_followup_id text default null,
  p_source_kind text default 'EVENT',
  p_verified boolean default false,
  p_actor_service text default 'SYSTEM',
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_key text; v_pk uuid;
begin
  v_key:=encode(digest(concat_ws('|','appointment',p_placement_id,p_appointment_at::text,upper(coalesce(p_outcome,'')),coalesce(p_evidence_id,''),coalesce(p_raw_input_id,''),coalesce(p_source_followup_id,''),p_observed_at::text),'sha256'),'hex');
  select appointment_fact_pk into v_pk from analytics.appointment_outcome_fact where fact_key=v_key;
  if v_pk is not null then return v_pk; end if;
  insert into analytics.appointment_outcome_fact(fact_key,placement_id,appointment_at,outcome,observed_at,evidence_id,raw_input_id,source_followup_id,source_kind,verified,actor_service,metadata)
  values(v_key,p_placement_id,p_appointment_at,upper(p_outcome),p_observed_at,p_evidence_id,p_raw_input_id,p_source_followup_id,p_source_kind,p_verified,p_actor_service,coalesce(p_metadata,'{}'::jsonb))
  returning appointment_fact_pk into v_pk;
  return v_pk;
end
$function$;

create or replace function analytics.record_partner_attribution(
  p_candidate_id text,
  p_partner_id text,
  p_attributed_at timestamptz,
  p_status text,
  p_evidence_id text default null,
  p_raw_input_id text default null,
  p_source_kind text default 'EVENT',
  p_approved_by text default null,
  p_approved_at timestamptz default null,
  p_actor_service text default 'SYSTEM',
  p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_key text; v_pk uuid;
begin
  v_key:=encode(digest(concat_ws('|','partner_attribution',p_candidate_id,p_partner_id,p_attributed_at::text,upper(coalesce(p_status,'')),coalesce(p_evidence_id,''),coalesce(p_raw_input_id,'')),'sha256'),'hex');
  select attribution_fact_pk into v_pk from analytics.partner_attribution_fact where fact_key=v_key;
  if v_pk is not null then return v_pk; end if;
  insert into analytics.partner_attribution_fact(fact_key,candidate_id,partner_id,attributed_at,attribution_status,evidence_id,raw_input_id,source_kind,approved_by,approved_at,actor_service,metadata)
  values(v_key,p_candidate_id,p_partner_id,p_attributed_at,upper(p_status),p_evidence_id,p_raw_input_id,p_source_kind,p_approved_by,p_approved_at,p_actor_service,coalesce(p_metadata,'{}'::jsonb))
  returning attribution_fact_pk into v_pk;
  return v_pk;
end
$function$;

create or replace function analytics.normalize_followup_milestone(p_followup_id text,p_actor_service text default 'FOLLOWUP_NORMALIZER') returns uuid
language plpgsql security definer set search_path=''
as $function$
declare f core.followups%rowtype; v_outcome text; v_pk uuid;
begin
  select * into f from core.followups where followup_id=p_followup_id;
  if not found then raise exception 'FOLLOWUP_NOT_FOUND'; end if;
  if upper(coalesce(f.milestone,'')) not in ('D7','D30','D90','D120') then raise exception 'UNSUPPORTED_RETENTION_MILESTONE'; end if;
  v_outcome:=case upper(trim(coalesce(f.result,'')))
    when 'ACTIVE' then 'ACTIVE' when 'PASS' then 'PASS' when 'LEFT' then 'LEFT' when 'DROPOUT' then 'DROPOUT'
    when 'UNKNOWN' then 'UNKNOWN' when 'NOT_REACHED' then 'NOT_REACHED' when 'CONTACT_FAILED' then 'CONTACT_FAILED'
    when 'NEEDS_REVIEW' then 'NEEDS_REVIEW' else 'NEEDS_REVIEW' end;
  select milestone_fact_pk into v_pk from analytics.placement_milestone_fact
  where placement_id=f.placement_id and milestone=upper(f.milestone) and source_followup_id=f.followup_id
  order by created_at desc limit 1;
  if v_pk is not null then return v_pk; end if;
  insert into analytics.placement_milestone_fact(placement_id,milestone,outcome,observed_at,source_followup_id,actor_service)
  values(f.placement_id,upper(f.milestone),v_outcome,coalesce(f.followed_up_at,f.created_at),f.followup_id,p_actor_service)
  returning milestone_fact_pk into v_pk;
  return v_pk;
end
$function$;

alter table analytics.appointment_outcome_fact enable row level security;
alter table analytics.partner_attribution_fact enable row level security;
revoke all on analytics.appointment_outcome_fact,analytics.partner_attribution_fact from public,anon,authenticated;
grant select,insert,update,delete on analytics.appointment_outcome_fact,analytics.partner_attribution_fact to service_role;
revoke all on function analytics.record_stage_transition(text,text,text,text,timestamptz,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function analytics.record_appointment_outcome(text,timestamptz,text,timestamptz,text,text,text,text,boolean,text,jsonb) from public,anon,authenticated;
revoke all on function analytics.record_partner_attribution(text,text,timestamptz,text,text,text,text,text,timestamptz,text,jsonb) from public,anon,authenticated;
revoke all on function analytics.normalize_followup_milestone(text,text) from public,anon,authenticated;
grant execute on function analytics.record_stage_transition(text,text,text,text,timestamptz,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function analytics.record_appointment_outcome(text,timestamptz,text,timestamptz,text,text,text,text,boolean,text,jsonb) to service_role;
grant execute on function analytics.record_partner_attribution(text,text,timestamptz,text,text,text,text,text,timestamptz,text,jsonb) to service_role;
grant execute on function analytics.normalize_followup_milestone(text,text) to service_role;