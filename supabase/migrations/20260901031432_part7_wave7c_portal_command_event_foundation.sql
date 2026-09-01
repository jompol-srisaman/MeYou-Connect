create table ops.portal_action_catalog (
  action_key text primary key,
  portal_kind text not null check (portal_kind in ('CANDIDATE','PARTNER','CLIENT','INTERNAL')),
  action_class text not null check (action_class in ('READ','PROPOSE','COMMAND','EVENT','REQUIRES_REVIEW','DENY')),
  event_type text,
  feature_key text,
  target_scope text not null,
  material boolean not null default true,
  direct_master_write_allowed boolean not null default false,
  requires_step_up boolean not null default false,
  policy_note text not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((action_class='DENY' and event_type is null) or action_class<>'DENY')
);

insert into ops.portal_action_catalog(action_key,portal_kind,action_class,event_type,feature_key,target_scope,material,direct_master_write_allowed,requires_step_up,policy_note) values
('candidate.contact.propose','CANDIDATE','PROPOSE','portal.candidate.contact_change.requested','candidate_profile_edit','PRIVATE_CANDIDATE_CONTACT',true,false,false,'Candidate may propose only own low-risk contact fields; effect must pass verified link, worker validation and write gate.'),
('candidate.placement_outcome.report','CANDIDATE','EVENT','portal.candidate.placement_outcome.reported','candidate_followup','PLACEMENT_SIGNAL',true,false,false,'Candidate report is source signal only and never directly changes verified Placement lifecycle truth.'),
('partner.candidate_consent.set','PARTNER','DENY',null,null,'CONSENT',true,false,false,'Partner cannot consent on behalf of Candidate.'),
('partner.b2b_rate.set','PARTNER','DENY',null,null,'B2B_PRICING',true,false,false,'Partner cannot set Founder-controlled B2B pricing.'),
('candidate.placement_state.direct_set','CANDIDATE','DENY',null,null,'PLACEMENT',true,false,false,'Candidate cannot directly mutate verified Placement lifecycle state.'),
('client.payment_evidence.submit','CLIENT','COMMAND','finance.payment_evidence.received','client_payment_evidence_upload','FINANCE_EVIDENCE',true,false,false,'Client finance may submit payment evidence through controlled file/event flow only; never mark COLLECTED.'),
('partner.member.invite','PARTNER','COMMAND','portal.organization.member_invite.requested','partner_member_manage','ORGANIZATION_MEMBERSHIP',true,false,true,'Partner Admin may invite only to own organization through step-up protected controlled command.'),
('internal.support.case_access','INTERNAL','COMMAND','portal.internal.support_access.recorded',null,'SUPPORT_AUDIT',true,false,true,'Authorized internal support access must be capability scoped and auditable.')
on conflict(action_key) do update set portal_kind=excluded.portal_kind,action_class=excluded.action_class,event_type=excluded.event_type,feature_key=excluded.feature_key,target_scope=excluded.target_scope,material=excluded.material,direct_master_write_allowed=excluded.direct_master_write_allowed,requires_step_up=excluded.requires_step_up,policy_note=excluded.policy_note,active=true,updated_at=now();

create table ops.portal_action_requests (
  request_pk uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  action_key text not null references ops.portal_action_catalog(action_key) on delete restrict,
  auth_user_id uuid not null,
  org_id uuid references authz.organizations(org_id) on delete restrict,
  candidate_id text references core.candidates(candidate_id) on delete restrict,
  target_entity_type text,
  target_entity_id text,
  raw_input_id text not null references ops.raw_inputs(raw_input_id) on delete restrict,
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  trace_id text not null,
  request_status text not null default 'ACCEPTED' check (request_status in ('ACCEPTED','ROUTED','VALIDATED','BLOCKED','APPLIED','REVIEW_REQUIRED','FAILED')),
  effect_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index portal_action_requests_auth_idx on ops.portal_action_requests(auth_user_id,created_at desc);
create index portal_action_requests_org_idx on ops.portal_action_requests(org_id,created_at desc) where org_id is not null;
create index portal_action_requests_candidate_idx on ops.portal_action_requests(candidate_id,created_at desc) where candidate_id is not null;
create index portal_action_requests_event_idx on ops.portal_action_requests(event_pk);
create index portal_action_requests_raw_idx on ops.portal_action_requests(raw_input_id);

alter table ops.portal_action_catalog enable row level security;
alter table ops.portal_action_requests enable row level security;
create policy portal_action_catalog_external_deny on ops.portal_action_catalog as restrictive for all to anon,authenticated using(false) with check(false);
create policy portal_action_requests_external_deny on ops.portal_action_requests as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.portal_action_catalog from public,anon,authenticated;
revoke all on ops.portal_action_requests from public,anon,authenticated;
grant all on ops.portal_action_catalog to service_role;
grant all on ops.portal_action_requests to service_role;

insert into ops.portal_feature_flags(feature_key,rollout_wave,environment,enabled,config)
values
('client_payment_evidence_upload','P3','TEST',false,'{}'::jsonb),
('partner_member_manage','P1A','TEST',false,'{}'::jsonb)
on conflict do nothing;

insert into ops.routing_rules(event_type,domain,route_key,material,evidence_expected,approval_policy,active) values
('portal.candidate.contact_change.requested','Candidate','portal_candidate_contact_worker',true,false,'NONE',true),
('portal.candidate.placement_outcome.reported','Placement','portal_candidate_outcome_review',true,false,'HUMAN_REVIEW',true),
('portal.organization.member_invite.requested','Authorization','portal_org_membership_worker',true,false,'STEP_UP_REQUIRED',true),
('portal.internal.support_access.recorded','Security','portal_support_audit_worker',true,true,'STEP_UP_REQUIRED',true)
on conflict(event_type) do update set domain=excluded.domain,route_key=excluded.route_key,material=excluded.material,evidence_expected=excluded.evidence_expected,approval_policy=excluded.approval_policy,active=true,updated_at=now();

insert into ops.worker_registry(worker_key,domain,enabled,default_lease_seconds,default_batch_size,max_retries,description) values
('portal_candidate_contact_worker','Candidate',true,60,20,3,'Applies verified low-risk Candidate contact proposals from Portal through Part 3 event/command flow.'),
('portal_candidate_outcome_review','Placement',true,60,20,3,'Routes Candidate-reported placement outcomes for internal validation; no direct lifecycle mutation.'),
('portal_org_membership_worker','Authorization',true,60,20,3,'Processes step-up protected organization membership commands.'),
('portal_support_audit_worker','Security',true,60,20,3,'Records audited internal support access events.')
on conflict(worker_key) do update set domain=excluded.domain,enabled=excluded.enabled,description=excluded.description,updated_at=now();

insert into ops.domain_worker_contracts(worker_key,domain,allowed_event_types,command_type,target_entity_type,requires_raw_input,requires_file_intake,requires_approval,active,contract_version) values
('portal_candidate_contact_worker','Candidate',array['portal.candidate.contact_change.requested'],'candidate_contact.update_proposal','CandidateContact',true,false,false,true,'P7C-V1')
on conflict(worker_key) do update set domain=excluded.domain,allowed_event_types=excluded.allowed_event_types,command_type=excluded.command_type,target_entity_type=excluded.target_entity_type,requires_raw_input=excluded.requires_raw_input,requires_file_intake=excluded.requires_file_intake,requires_approval=excluded.requires_approval,active=true,contract_version=excluded.contract_version,updated_at=now();

insert into ops.master_apply_contracts(command_type,target_scope,gate_key,handler_key,allow_create,allow_update,active,notes) values
('candidate_contact.update_proposal','PRIVACY','business_master_apply_enabled','PORTAL_CANDIDATE_CONTACT',true,true,true,'Part 7C dedicated controlled handler; only phone/line_id/email and verified active Candidate-user link are allowed.')
on conflict(command_type) do update set target_scope=excluded.target_scope,gate_key=excluded.gate_key,handler_key=excluded.handler_key,allow_create=excluded.allow_create,allow_update=excluded.allow_update,active=true,notes=excluded.notes,updated_at=now();

create or replace function authz.require_portal_feature_enabled(p_feature_key text,p_org_id uuid default null)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_feature_key is null or btrim(p_feature_key)='' then raise exception 'PORTAL_FEATURE_KEY_REQUIRED'; end if;
  if not exists(
    select 1 from ops.portal_feature_flags f
    where f.feature_key=p_feature_key and f.environment='TEST' and f.enabled=true
      and (f.org_id is null or (p_org_id is not null and f.org_id=p_org_id))
  ) then raise exception 'PORTAL_FEATURE_DISABLED:%',p_feature_key; end if;
end $$;
revoke all on function authz.require_portal_feature_enabled(text,uuid) from public,anon,authenticated;
grant execute on function authz.require_portal_feature_enabled(text,uuid) to service_role;

create or replace function api.portal_candidate_propose_contact_update(p_request_id uuid,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_candidate_id text;
  v_existing ops.portal_action_requests;
  v_alloc jsonb;
  v_raw_id text;
  v_trace text;
  v_ingest jsonb;
  v_event_pk uuid;
  v_bad_keys text[];
  v_actor text;
begin
  perform authz.require_external_portal_enabled('CANDIDATE');
  perform authz.require_portal_feature_enabled('candidate_profile_edit',null);
  if v_uid is null then raise exception 'AUTHENTICATED_USER_REQUIRED'; end if;
  v_candidate_id:=authz.current_candidate_id();
  if v_candidate_id is null then raise exception 'VERIFIED_CANDIDATE_LINK_REQUIRED'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into v_existing from ops.portal_action_requests where request_id=p_request_id;
  if found then
    if v_existing.auth_user_id<>v_uid or v_existing.action_key<>'candidate.contact.propose' then raise exception 'REQUEST_ID_REUSE_CONFLICT'; end if;
    return jsonb_build_object('request_id',v_existing.request_id,'request_status',v_existing.request_status,'raw_input_id',v_existing.raw_input_id,'event_pk',v_existing.event_pk,'duplicate_request',true);
  end if;
  if p_patch is null or jsonb_typeof(p_patch)<>'object' or p_patch='{}'::jsonb then raise exception 'CONTACT_PATCH_REQUIRED'; end if;
  select array_agg(k) into v_bad_keys from jsonb_object_keys(p_patch) k where k not in ('phone','line_id','email');
  if v_bad_keys is not null then raise exception 'CONTACT_FIELD_NOT_ALLOWED:%',array_to_string(v_bad_keys,','); end if;
  if p_patch ? 'phone' and length(coalesce(p_patch->>'phone',''))>32 then raise exception 'PHONE_TOO_LONG'; end if;
  if p_patch ? 'line_id' and length(coalesce(p_patch->>'line_id',''))>128 then raise exception 'LINE_ID_TOO_LONG'; end if;
  if p_patch ? 'email' and length(coalesce(p_patch->>'email',''))>254 then raise exception 'EMAIL_TOO_LONG'; end if;
  v_actor:='portal_candidate:'||v_uid::text;
  v_alloc:=config.allocate_business_id('Raw Input',v_actor,jsonb_build_object('portal_action','candidate.contact.propose','request_id',p_request_id));
  v_raw_id:=v_alloc->>'allocated_id';
  v_trace:='portal:'||p_request_id::text;
  v_ingest:=ops.ingest_material_event(
    v_raw_id,'P7C-V1','MYC_PORTAL','PORTAL',
    'portal-candidate-contact-'||p_request_id::text,
    'portal|candidate|contact|'||v_uid::text||'|'||p_request_id::text,
    v_trace,'portal.candidate.contact_change.requested',now(),'CANDIDATE','JSON',
    'portal://candidate/contact/'||p_request_id::text,
    v_uid::text,null,null,p_request_id::text,'Candidate proposed low-risk contact update','Candidate',v_candidate_id,false,null,true,null,
    jsonb_build_object('portal_action_key','candidate.contact.propose','portal_payload',p_patch,'actor_auth_user_id',v_uid,'candidate_id',v_candidate_id,'request_id',p_request_id),null,null);
  v_event_pk:=(v_ingest->>'event_pk')::uuid;
  insert into ops.portal_action_requests(request_id,action_key,auth_user_id,candidate_id,target_entity_type,target_entity_id,raw_input_id,event_pk,trace_id,request_status)
  values(p_request_id,'candidate.contact.propose',v_uid,v_candidate_id,'CandidateContact',v_candidate_id,v_raw_id,v_event_pk,v_trace,'ACCEPTED');
  return jsonb_build_object('request_id',p_request_id,'request_status','ACCEPTED','raw_input_id',v_raw_id,'event_pk',v_event_pk,'duplicate_request',false,'candidate_id',v_candidate_id);
end $$;

create or replace function api.portal_candidate_report_placement_outcome(p_request_id uuid,p_placement_id text,p_reported_outcome text,p_notes text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_uid uuid:=auth.uid();
  v_candidate_id text;
  v_existing ops.portal_action_requests;
  v_alloc jsonb;
  v_raw_id text;
  v_trace text;
  v_ingest jsonb;
  v_event_pk uuid;
  v_actor text;
begin
  perform authz.require_external_portal_enabled('CANDIDATE');
  perform authz.require_portal_feature_enabled('candidate_followup',null);
  if v_uid is null then raise exception 'AUTHENTICATED_USER_REQUIRED'; end if;
  v_candidate_id:=authz.current_candidate_id();
  if v_candidate_id is null then raise exception 'VERIFIED_CANDIDATE_LINK_REQUIRED'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into v_existing from ops.portal_action_requests where request_id=p_request_id;
  if found then
    if v_existing.auth_user_id<>v_uid or v_existing.action_key<>'candidate.placement_outcome.report' then raise exception 'REQUEST_ID_REUSE_CONFLICT'; end if;
    return jsonb_build_object('request_id',v_existing.request_id,'request_status',v_existing.request_status,'raw_input_id',v_existing.raw_input_id,'event_pk',v_existing.event_pk,'duplicate_request',true);
  end if;
  if p_placement_id is null or not exists(select 1 from core.placements p where p.placement_id=p_placement_id and p.candidate_id=v_candidate_id) then raise exception 'PLACEMENT_NOT_OWNED_BY_CANDIDATE'; end if;
  if upper(coalesce(p_reported_outcome,'')) not in ('STARTED','DROPOUT','CLOSED','ISSUE','OTHER') then raise exception 'INVALID_REPORTED_OUTCOME'; end if;
  if length(coalesce(p_notes,''))>2000 then raise exception 'NOTES_TOO_LONG'; end if;
  v_actor:='portal_candidate:'||v_uid::text;
  v_alloc:=config.allocate_business_id('Raw Input',v_actor,jsonb_build_object('portal_action','candidate.placement_outcome.report','request_id',p_request_id));
  v_raw_id:=v_alloc->>'allocated_id';
  v_trace:='portal:'||p_request_id::text;
  v_ingest:=ops.ingest_material_event(
    v_raw_id,'P7C-V1','MYC_PORTAL','PORTAL',
    'portal-candidate-outcome-'||p_request_id::text,
    'portal|candidate|placement_outcome|'||v_uid::text||'|'||p_request_id::text,
    v_trace,'portal.candidate.placement_outcome.reported',now(),'CANDIDATE','JSON',
    'portal://candidate/placement-outcome/'||p_request_id::text,
    v_uid::text,null,null,p_request_id::text,'Candidate reported placement outcome signal','Placement',p_placement_id,false,null,true,null,
    jsonb_build_object('portal_action_key','candidate.placement_outcome.report','actor_auth_user_id',v_uid,'candidate_id',v_candidate_id,'placement_id',p_placement_id,'reported_outcome',upper(p_reported_outcome),'notes',p_notes,'request_id',p_request_id),null,null);
  v_event_pk:=(v_ingest->>'event_pk')::uuid;
  insert into ops.portal_action_requests(request_id,action_key,auth_user_id,candidate_id,target_entity_type,target_entity_id,raw_input_id,event_pk,trace_id,request_status)
  values(p_request_id,'candidate.placement_outcome.report',v_uid,v_candidate_id,'Placement',p_placement_id,v_raw_id,v_event_pk,v_trace,'REVIEW_REQUIRED');
  return jsonb_build_object('request_id',p_request_id,'request_status','REVIEW_REQUIRED','raw_input_id',v_raw_id,'event_pk',v_event_pk,'duplicate_request',false,'official_placement_state_changed',false);
end $$;

revoke all on function api.portal_candidate_propose_contact_update(uuid,jsonb) from public,anon;
revoke all on function api.portal_candidate_report_placement_outcome(uuid,text,text,text) from public,anon;
grant execute on function api.portal_candidate_propose_contact_update(uuid,jsonb) to authenticated,service_role;
grant execute on function api.portal_candidate_report_placement_outcome(uuid,text,text,text) to authenticated,service_role;

create table ops.part7c_acceptance_catalog (
  test_id text primary key,
  scenario text not null,
  expected_behavior text not null,
  status text not null default 'NOT_RUN' check(status in ('NOT_RUN','PASS','FAIL')),
  evidence_ref text,
  last_tested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into ops.part7c_acceptance_catalog(test_id,scenario,expected_behavior) values
('P7C-001','Candidate contact proposal uses verified self link and creates Raw/Event/Action chain','PASS'),
('P7C-002','Candidate cannot select or update another Candidate','DENY'),
('P7C-003','Candidate contact proposal rejects non-whitelisted PII/master fields','DENY'),
('P7C-004','Partner cannot set Candidate consent or B2B rate through direct/internal paths','DENY'),
('P7C-005','Candidate placement outcome is report event only; official Placement state unchanged','PASS'),
('P7C-006','Repeated request_id is idempotent and does not create duplicate event/action','PASS'),
('P7C-007','Disabled/revoked Candidate link blocks Portal command ingress','DENY'),
('P7C-008','Portal action preserves auth user, Candidate, Raw Input, Event and trace references','PASS')
on conflict(test_id) do nothing;
alter table ops.part7c_acceptance_catalog enable row level security;
create policy part7c_acceptance_external_deny on ops.part7c_acceptance_catalog as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.part7c_acceptance_catalog from public,anon,authenticated;
grant all on ops.part7c_acceptance_catalog to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
('part7c_command_event_foundation_ready','true'::jsonb,'Part 7C Portal Command/Event ingress foundation installed in TEST; external Portal remains disabled.','Part7C',now()),
('part7c_foundation_closed','false'::jsonb,'Part 7C closeout not yet complete.','Part7C',now())
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;