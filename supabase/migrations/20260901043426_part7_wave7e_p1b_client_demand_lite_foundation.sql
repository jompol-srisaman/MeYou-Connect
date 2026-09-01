insert into ops.worker_registry(worker_key,domain,enabled,default_lease_seconds,default_batch_size,max_retries,description)
values('portal_client_demand_review_worker','Client/Job',true,60,20,3,'Routes P1B Client Demand Lite submissions into an internal review queue while Google Sheets/Drive remains operational source of truth.')
on conflict(worker_key) do update set domain=excluded.domain,enabled=true,description=excluded.description,updated_at=now();

insert into ops.routing_rules(event_type,domain,route_key,material,evidence_expected,approval_policy,active)
values('portal.client.job_demand.submitted','Client/Job','portal_client_demand_review_worker',true,false,'NONE',true)
on conflict(event_type) do update set domain=excluded.domain,route_key=excluded.route_key,material=excluded.material,evidence_expected=excluded.evidence_expected,approval_policy=excluded.approval_policy,active=true,updated_at=now();

insert into ops.domain_worker_contracts(worker_key,domain,allowed_event_types,command_type,target_entity_type,requires_raw_input,requires_file_intake,requires_approval,active,contract_version)
values('portal_client_demand_review_worker','Client/Job',array['portal.client.job_demand.submitted'],'client_demand.review_queue','ClientDemandReview',true,false,false,true,'P7E-V1')
on conflict(worker_key) do update set domain=excluded.domain,allowed_event_types=excluded.allowed_event_types,command_type=excluded.command_type,target_entity_type=excluded.target_entity_type,requires_raw_input=true,requires_file_intake=false,requires_approval=false,active=true,contract_version=excluded.contract_version,updated_at=now();

insert into ops.portal_action_catalog(action_key,portal_kind,action_class,event_type,feature_key,target_scope,material,direct_master_write_allowed,requires_step_up,policy_note,active)
values('client.job_demand.submit','CLIENT','REQUIRES_REVIEW','portal.client.job_demand.submitted','client_demand_submit','CLIENT_JOB_DEMAND_REVIEW',true,false,false,'P1B Client Demand Lite accepts own-organization demand as Raw/Event and internal review only while GOOGLE_SHEETS_DRIVE remains operational source; no direct Job Master write.',true)
on conflict(action_key) do update set portal_kind=excluded.portal_kind,action_class=excluded.action_class,event_type=excluded.event_type,feature_key=excluded.feature_key,target_scope=excluded.target_scope,material=true,direct_master_write_allowed=false,requires_step_up=false,policy_note=excluded.policy_note,active=true,updated_at=now();

create table ops.client_demand_review_queue(
  review_pk uuid primary key default gen_random_uuid(),
  request_id uuid not null unique references ops.portal_action_requests(request_id) on delete restrict,
  org_id uuid not null references authz.organizations(org_id) on delete restrict,
  client_id text not null references core.clients(client_id) on delete restrict,
  submitted_by uuid not null references auth.users(id) on delete restrict,
  raw_input_id text not null references ops.raw_inputs(raw_input_id) on delete restrict,
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  trace_id text not null,
  demand_payload jsonb not null,
  review_status text not null default 'PENDING_REVIEW' check(review_status in ('PENDING_REVIEW','SOURCE_SYNCED','REJECTED','CANCELLED')),
  source_record_ref text,
  reviewed_by text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index client_demand_review_org_status_idx on ops.client_demand_review_queue(org_id,review_status,created_at desc);
create index client_demand_review_client_status_idx on ops.client_demand_review_queue(client_id,review_status,created_at desc);
create index client_demand_review_actor_idx on ops.client_demand_review_queue(submitted_by,created_at desc);
create index client_demand_review_raw_idx on ops.client_demand_review_queue(raw_input_id);
create index client_demand_review_event_idx on ops.client_demand_review_queue(event_pk);
alter table ops.client_demand_review_queue enable row level security;
create policy client_demand_review_external_deny on ops.client_demand_review_queue as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.client_demand_review_queue from public,anon,authenticated;
grant all on ops.client_demand_review_queue to service_role;

create or replace function api.portal_client_submit_job_demand(
  p_request_id uuid,
  p_org_id uuid,
  p_workplace_name text,
  p_province text,
  p_area text,
  p_position_name text,
  p_headcount integer,
  p_compensation_text text default null,
  p_shift text default null,
  p_desired_start_date date default null,
  p_requirements text default null,
  p_documents text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_existing ops.portal_action_requests;
  v_client_id text;
  v_alloc jsonb;
  v_raw_id text;
  v_trace text;
  v_ingest jsonb;
  v_event_pk uuid;
  v_payload jsonb;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  perform authz.require_portal_feature_enabled('client_demand_submit',p_org_id);
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not authz.is_active_org_member(p_org_id) then raise exception 'ACTIVE_ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_admin') or authz.has_portal_role(p_org_id,'client_recruiter')) then raise exception 'CLIENT_RECRUITMENT_ROLE_REQUIRED'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;

  select * into v_existing from ops.portal_action_requests where request_id=p_request_id;
  if found then
    if v_existing.auth_user_id<>v_uid or v_existing.action_key<>'client.job_demand.submit' or v_existing.org_id is distinct from p_org_id then raise exception 'REQUEST_ID_REUSE_CONFLICT'; end if;
    return jsonb_build_object('request_id',v_existing.request_id,'request_status',v_existing.request_status,'raw_input_id',v_existing.raw_input_id,'event_pk',v_existing.event_pk,'duplicate_request',true,'master_job_changed',false);
  end if;

  select o.business_party_id into v_client_id from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORG_REQUIRED'; end if;
  if nullif(btrim(coalesce(p_workplace_name,'')),'') is null or length(p_workplace_name)>300 then raise exception 'VALID_WORKPLACE_NAME_REQUIRED'; end if;
  if nullif(btrim(coalesce(p_position_name,'')),'') is null or length(p_position_name)>300 then raise exception 'VALID_POSITION_NAME_REQUIRED'; end if;
  if p_headcount is null or p_headcount<1 or p_headcount>10000 then raise exception 'VALID_HEADCOUNT_REQUIRED'; end if;
  if p_province is not null and length(p_province)>100 then raise exception 'PROVINCE_TOO_LONG'; end if;
  if p_area is not null and length(p_area)>300 then raise exception 'AREA_TOO_LONG'; end if;
  if p_compensation_text is not null and length(p_compensation_text)>1000 then raise exception 'COMPENSATION_TEXT_TOO_LONG'; end if;
  if p_shift is not null and length(p_shift)>1000 then raise exception 'SHIFT_TOO_LONG'; end if;
  if p_requirements is not null and length(p_requirements)>5000 then raise exception 'REQUIREMENTS_TOO_LONG'; end if;
  if p_documents is not null and length(p_documents)>5000 then raise exception 'DOCUMENTS_TOO_LONG'; end if;
  if p_notes is not null and length(p_notes)>5000 then raise exception 'NOTES_TOO_LONG'; end if;

  v_payload:=jsonb_build_object(
    'workplace_name',btrim(p_workplace_name),
    'province',nullif(btrim(coalesce(p_province,'')),''),
    'area',nullif(btrim(coalesce(p_area,'')),''),
    'position_name',btrim(p_position_name),
    'headcount',p_headcount,
    'compensation_text',nullif(btrim(coalesce(p_compensation_text,'')),''),
    'shift',nullif(btrim(coalesce(p_shift,'')),''),
    'desired_start_date',p_desired_start_date,
    'requirements',nullif(btrim(coalesce(p_requirements,'')),''),
    'documents',nullif(btrim(coalesce(p_documents,'')),''),
    'notes',nullif(btrim(coalesce(p_notes,'')),'')
  );

  v_alloc:=config.allocate_business_id('Raw Input','portal_client:'||v_uid::text,jsonb_build_object('portal_action','client.job_demand.submit','request_id',p_request_id,'org_id',p_org_id,'client_id',v_client_id));
  v_raw_id:=v_alloc->>'allocated_id';
  v_trace:='portal-client-demand:'||p_request_id::text;
  v_ingest:=ops.ingest_material_event(
    v_raw_id,'P7E-V1','MYC_PORTAL','PORTAL',
    'portal-client-job-demand-'||p_request_id::text,
    'portal|client|job_demand|'||v_uid::text||'|'||p_request_id::text,
    v_trace,'portal.client.job_demand.submitted',now(),'CLIENT','JSON',
    'portal://client/job-demand/'||p_request_id::text,
    v_uid::text,p_org_id::text,null,p_request_id::text,
    'Client submitted a Job Demand for internal review before operational source update',
    'Client',v_client_id,false,null,false,null,
    jsonb_build_object('portal_action_key','client.job_demand.submit','actor_auth_user_id',v_uid,'org_id',p_org_id,'client_id',v_client_id,'request_id',p_request_id,'demand',v_payload,'operational_source','GOOGLE_SHEETS_DRIVE'),
    null,null
  );
  v_event_pk:=(v_ingest->>'event_pk')::uuid;

  insert into ops.portal_action_requests(request_id,action_key,auth_user_id,org_id,target_entity_type,target_entity_id,raw_input_id,event_pk,trace_id,request_status)
  values(p_request_id,'client.job_demand.submit',v_uid,p_org_id,'ClientDemandReview',v_client_id,v_raw_id,v_event_pk,v_trace,'REVIEW_REQUIRED');

  return jsonb_build_object('request_id',p_request_id,'request_status','REVIEW_REQUIRED','raw_input_id',v_raw_id,'event_pk',v_event_pk,'client_id',v_client_id,'duplicate_request',false,'master_job_changed',false,'operational_source','GOOGLE_SHEETS_DRIVE');
end $$;
revoke all on function api.portal_client_submit_job_demand(uuid,uuid,text,text,text,text,integer,text,text,date,text,text,text) from public,anon;
grant execute on function api.portal_client_submit_job_demand(uuid,uuid,text,text,text,text,integer,text,text,date,text,text,text) to authenticated,service_role;

create or replace function api.portal_client_demand_requests(p_org_id uuid)
returns table(
  request_id uuid,
  request_status text,
  workplace_name text,
  province text,
  area text,
  position_name text,
  headcount integer,
  desired_start_date date,
  review_status text,
  source_record_ref text,
  submitted_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_client_id text;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  perform authz.require_portal_feature_enabled('client_demand_submit',p_org_id);
  if not authz.is_active_org_member(p_org_id) then raise exception 'ACTIVE_ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_admin') or authz.has_portal_role(p_org_id,'client_recruiter')) then raise exception 'CLIENT_RECRUITMENT_ROLE_REQUIRED'; end if;
  select o.business_party_id into v_client_id from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORG_REQUIRED'; end if;
  return query
  select r.request_id,r.request_status,
         ri.metadata #>> '{demand,workplace_name}',
         ri.metadata #>> '{demand,province}',
         ri.metadata #>> '{demand,area}',
         ri.metadata #>> '{demand,position_name}',
         nullif(ri.metadata #>> '{demand,headcount}','')::integer,
         nullif(ri.metadata #>> '{demand,desired_start_date}','')::date,
         q.review_status,q.source_record_ref,r.created_at,r.updated_at
  from ops.portal_action_requests r
  join ops.raw_inputs ri on ri.raw_input_id=r.raw_input_id
  left join ops.client_demand_review_queue q on q.request_id=r.request_id
  where r.org_id=p_org_id and r.action_key='client.job_demand.submit' and r.target_entity_id=v_client_id
  order by r.created_at desc,r.request_id;
end $$;
revoke all on function api.portal_client_demand_requests(uuid) from public,anon;
grant execute on function api.portal_client_demand_requests(uuid) to authenticated,service_role;

create or replace function api.portal_client_candidate_submissions(p_org_id uuid)
returns table(placement_id text, job_id text, candidate_id text, candidate_nickname text, education text, primary_experience text, relocation_ready boolean, ready_date date, documents_ready boolean, medical_ready boolean, placement_status text, submitted_at timestamptz, appointment_at timestamptz, applied_at timestamptz, start_date date, updated_at timestamptz)
language plpgsql
stable
security definer
set search_path=''
as $$
declare v_client_id text;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  perform authz.require_portal_feature_enabled('client_candidate_status',p_org_id);
  if not authz.is_active_org_member(p_org_id) then raise exception 'ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_admin') or authz.has_portal_role(p_org_id,'client_recruiter')) then raise exception 'CLIENT_RECRUITMENT_ROLE_REQUIRED'; end if;
  select o.business_party_id into v_client_id from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORGANIZATION_REQUIRED'; end if;
  return query
  select p.placement_id,p.job_id,p.candidate_id,c.nickname,c.education,c.primary_experience,
         c.relocation_ready,c.ready_date,c.documents_ready,c.medical_ready,p.status,
         p.submitted_at,p.appointment_at,p.applied_at,p.start_date,p.updated_at
  from core.placements p
  join core.jobs j on j.job_id=p.job_id and j.client_id=v_client_id
  join core.candidates c on c.candidate_id=p.candidate_id
  where authz.is_active_client_candidate_purpose(p_org_id,p.placement_id,p.candidate_id)
  order by p.updated_at desc,p.placement_id;
end $$;
revoke all on function api.portal_client_candidate_submissions(uuid) from public,anon;
grant execute on function api.portal_client_candidate_submissions(uuid) to authenticated,service_role;

create table ops.part7e_acceptance_catalog(
  test_id text primary key,
  scenario text not null,
  expected_behavior text not null,
  status text not null default 'NOT_RUN' check(status in ('NOT_RUN','PASS','FAIL')),
  evidence_ref text,
  last_tested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into ops.part7e_acceptance_catalog(test_id,scenario,expected_behavior) values
('P7E-001','P1B feature disabled blocks Client Demand ingress','DENY'),
('P7E-002','Org-scoped P1B feature enables own Client recruiter/admin only','PASS'),
('P7E-003','Cross-client organization demand submission is denied','DENY'),
('P7E-004','Job Demand creates Raw Input + Event + Portal request but no Job Master effect','PASS'),
('P7E-005','Demand review worker creates internal review queue effect only','PASS'),
('P7E-006','Duplicate request ID is idempotent','PASS'),
('P7E-007','Client demand request projection is own-org scoped','PASS'),
('P7E-008','Client candidate submission projection requires client_candidate_status feature flag','DENY')
on conflict(test_id) do nothing;
alter table ops.part7e_acceptance_catalog enable row level security;
create policy part7e_acceptance_external_deny on ops.part7e_acceptance_catalog as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.part7e_acceptance_catalog from public,anon,authenticated;
grant all on ops.part7e_acceptance_catalog to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
('part7_pilot_selected','"P1B_CLIENT_DEMAND_LITE"'::jsonb,'Architect-selected Founder-authorized continuation based on current operational bottleneck evidence: recurring Client demand/status workload exists while Candidate rows and Partner leads remain zero. Selection does not enable Production Portal.','Part7E + Google Data Hub 1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc',now()),
('part7e_p1b_foundation_ready','true'::jsonb,'P1B Client Demand Lite TEST foundation installed; external Portal remains disabled.','Part7E',now()),
('part7e_foundation_closed','false'::jsonb,'Part 7E acceptance/closeout not yet complete.','Part7E',now())
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;