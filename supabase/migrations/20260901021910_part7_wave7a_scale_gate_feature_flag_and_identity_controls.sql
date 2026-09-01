create table if not exists ops.scale_gate_catalog (
  gate_key text primary key,
  gate_name text not null,
  question text not null,
  required_evidence text not null,
  if_fail text not null,
  authority text not null,
  active boolean not null default true,
  source_ref text not null default 'MEYOU_CONNECT_PORTAL_SCALE_CONTROL_MATRIX_V1',
  created_at timestamptz not null default now()
);

insert into ops.scale_gate_catalog(gate_key,gate_name,question,required_evidence,if_fail,authority) values
('SG-01','Demand','Is there real repeatable client demand in target area?','Verified Client/Job demand, not speculative lead','Do not launch acquisition as active province','Founder'),
('SG-02','Supply','Can MeYou Connect source candidates for the demand?','Qualified/relocation-ready/local supply signal','Keep area research-only','Founder/Candidate Ops'),
('SG-03','Unit Economics','Does pricing/collection support local operating cost?','Real deal/collection/direct cost evidence','No scale spend; renegotiate/learn','Founder/Finance'),
('SG-04','Collection','Is client payment behavior validated enough?','Collected revenue/payment history or acceptable risk decision','Limit exposure/no advance spend','Founder/Finance'),
('SG-05','Relocation Support','Are dorm/transport/medical/document pathways adequate if needed?','Verified providers/service-area coverage','Launch local-only or defer relocation promise','Operations'),
('SG-06','Owner/Capacity','Who owns local operation and support backlog?','Named owner + capacity/backlog thresholds','No new portal/province onboarding','Founder'),
('SG-07','Data Quality','Can records/evidence/follow-up remain within standards?','DQ/backlog/file/retention process acceptable','Fix process before scale','Data Audit'),
('SG-08','Compliance','Any local/legal/client-specific requirement requiring review?','Relevant contract/compliance review','Hold affected scope','Founder/Legal support'),
('SG-09','Exit Plan','Can the province be paused without losing data/obligations?','Service obligations + fallback/closure plan','Do not expand until controlled rollback exists','Founder/Architect')
on conflict(gate_key) do update set gate_name=excluded.gate_name,question=excluded.question,required_evidence=excluded.required_evidence,if_fail=excluded.if_fail,authority=excluded.authority,active=true;

create table if not exists ops.province_scale_state (
  province_code text primary key references geo.provinces(province_code) on delete restrict,
  lifecycle_state text not null default 'RESEARCH' check (lifecycle_state in ('RESEARCH','DEMAND_VALIDATION','PILOT','ACTIVE','PAUSED','CLOSED')),
  founder_approved boolean not null default false,
  approved_by text,
  approved_at timestamptz,
  status_reason text,
  last_transition_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint province_founder_approval_ck check ((founder_approved and approved_by is not null and approved_at is not null) or not founder_approved)
);

create table if not exists ops.province_scale_gate_results (
  province_code text not null references geo.provinces(province_code) on delete restrict,
  gate_key text not null references ops.scale_gate_catalog(gate_key) on delete restrict,
  readiness_status text not null default 'NOT_READY' check (readiness_status in ('NOT_READY','READY')),
  evidence_ref text,
  evaluated_by text,
  evaluated_at timestamptz,
  notes text,
  updated_at timestamptz not null default now(),
  primary key(province_code,gate_key),
  constraint scale_gate_ready_evidence_ck check ((readiness_status='READY' and evidence_ref is not null and evaluated_by is not null and evaluated_at is not null) or readiness_status='NOT_READY')
);
create index if not exists province_scale_gate_status_idx on ops.province_scale_gate_results(province_code,readiness_status);

create table if not exists ops.portal_feature_flags (
  feature_flag_pk uuid primary key default gen_random_uuid(),
  feature_key text not null,
  rollout_wave text not null check (rollout_wave in ('P0','P1A','P1B','P2','P3','P4','P5')),
  environment text not null default 'TEST' check (environment in ('TEST','PROD')),
  org_id uuid references authz.organizations(org_id) on delete restrict,
  service_area_id uuid references geo.service_areas(service_area_id) on delete restrict,
  enabled boolean not null default false,
  enabled_by text,
  enabled_at timestamptz,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint portal_flag_enable_evidence_ck check ((enabled and enabled_by is not null and enabled_at is not null) or not enabled),
  constraint portal_flag_no_secret_keys_ck check (not (config ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create unique index if not exists portal_feature_flags_scope_uq on ops.portal_feature_flags(feature_key,environment,coalesce(org_id,'00000000-0000-0000-0000-000000000000'::uuid),coalesce(service_area_id,'00000000-0000-0000-0000-000000000000'::uuid));
create index if not exists portal_feature_flags_org_idx on ops.portal_feature_flags(org_id,enabled) where org_id is not null;
create index if not exists portal_feature_flags_area_idx on ops.portal_feature_flags(service_area_id,enabled) where service_area_id is not null;

insert into ops.portal_feature_flags(feature_key,rollout_wave,environment,enabled) values
('partner_referral_submit','P1A','TEST',false),('partner_commission_view','P3','TEST',false),('client_demand_submit','P1B','TEST',false),('client_candidate_status','P1B','TEST',false),('client_invoice_view','P3','TEST',false),('candidate_profile_edit','P2','TEST',false),('candidate_consent','P2','TEST',false),('candidate_file_upload','P2','TEST',false),('candidate_followup','P2','TEST',false),('region_console','P4','TEST',false)
on conflict do nothing;

create table if not exists ops.portal_acceptance_catalog (
  test_id text primary key, actor text not null, scenario text not null, expected_behavior text not null,
  critical boolean not null default true,
  status text not null default 'NOT_RUN' check (status in ('NOT_RUN','PASS','FAIL','BLOCKED')),
  evidence_ref text,last_tested_at timestamptz,
  source_ref text not null default 'MEYOU_CONNECT_PORTAL_SCALE_CONTROL_MATRIX_V1',
  updated_at timestamptz not null default now()
);
insert into ops.portal_acceptance_catalog(test_id,actor,scenario,expected_behavior,critical) values
('PT-001','Client A member','Read Client B jobs/candidates/invoices','DENY',true),('PT-002','Partner A member','Read Partner B referrals/commission','DENY',true),('PT-003','Candidate A','Read/update Candidate B profile/consent/files','DENY',true),('PT-004','Client recruiter','Read full Candidate Master/other job history','DENY; only submission projection',true),('PT-005','Partner member','Set candidate consent or B2B rate','DENY',true),('PT-006','Client finance','Upload payment evidence','ALLOW event/upload; cannot mark COLLECTED',true),('PT-007','Removed org member','Use stale session after membership removal','DENY at DB membership check after revocation path',true),('PT-008','Multi-org user','Switch active org in client request without membership','DENY',true),('PT-009','Partner admin','Invite member to own org','ALLOW controlled membership command',true),('PT-010','Candidate portal','Change phone/contact low-risk field','ALLOW/PROPOSE per rule with audit',false),('PT-011','Candidate portal','Change verified placement STARTED to CLOSED directly','DENY direct; report outcome event only',true),('PT-012','Client user','View candidate for active submission after purpose ends','DENY/expire according to access lifecycle',true),('PT-013','Public anon','Read private job/client rate/evidence','DENY',true),('PT-014','Internal authorized support','Access case with audit trail','ALLOW within internal permission',true)
on conflict(test_id) do update set actor=excluded.actor,scenario=excluded.scenario,expected_behavior=excluded.expected_behavior,critical=excluded.critical;

create table if not exists ops.part7a_acceptance_catalog (
  test_id text primary key, scenario text not null, expected_behavior text not null,
  status text not null default 'NOT_RUN' check (status in ('NOT_RUN','PASS','FAIL','BLOCKED')),
  evidence_ref text,last_tested_at timestamptz,updated_at timestamptz not null default now()
);
insert into ops.part7a_acceptance_catalog(test_id,scenario,expected_behavior) values
('P7A-001','Province/service area is geography, not tenant boundary','Same business party can map across service areas without duplicate business ID'),
('P7A-002','Organization maps to an existing Client/Partner business party','Invalid or wrong-type business party is rejected'),
('P7A-003','Active organization membership is database truth','Only ACTIVE, in-window, non-removed membership passes'),
('P7A-004','Removed member with stale JWT subject','Membership predicate immediately returns DENY'),
('P7A-005','Multi-org user requests unowned organization','Membership predicate returns DENY for org not in membership table'),
('P7A-006','Candidate portal identity link','Only one verified active user link per Candidate; cross-candidate predicate denied'),
('P7A-007','Portal feature flags fail safe','All seeded external features remain disabled by default'),
('P7A-008','Province ACTIVE transition gate','ACTIVE blocked unless all SG-01..09 READY, Founder-approved, and activation master gate enabled')
on conflict(test_id) do update set scenario=excluded.scenario,expected_behavior=excluded.expected_behavior;

create or replace function authz.is_active_org_member(requested_org_id uuid)
returns boolean language sql stable security definer set search_path=''
as $function$
  select coalesce(exists(select 1 from authz.organization_members m join authz.organizations o on o.org_id=m.org_id where m.org_id=requested_org_id and m.auth_user_id=auth.uid() and o.status='ACTIVE' and m.membership_status='ACTIVE' and (m.active_from is null or m.active_from<=now()) and (m.expires_at is null or m.expires_at>now()) and m.removed_at is null),false)
$function$;
create or replace function authz.has_portal_role(requested_org_id uuid,requested_role text)
returns boolean language sql stable security definer set search_path=''
as $function$
  select coalesce(exists(select 1 from authz.organization_members m join authz.organizations o on o.org_id=m.org_id where m.org_id=requested_org_id and m.auth_user_id=auth.uid() and m.portal_role=requested_role and o.status='ACTIVE' and m.membership_status='ACTIVE' and (m.active_from is null or m.active_from<=now()) and (m.expires_at is null or m.expires_at>now()) and m.removed_at is null),false)
$function$;
create or replace function authz.is_verified_candidate_user(requested_candidate_id text)
returns boolean language sql stable security definer set search_path=''
as $function$
  select coalesce(exists(select 1 from authz.candidate_user_links l where l.auth_user_id=auth.uid() and l.candidate_id=requested_candidate_id and l.verification_status='VERIFIED' and l.disabled_at is null),false)
$function$;
create or replace function authz.current_candidate_id()
returns text language sql stable security definer set search_path=''
as $function$
  select l.candidate_id from authz.candidate_user_links l where l.auth_user_id=auth.uid() and l.verification_status='VERIFIED' and l.disabled_at is null limit 1
$function$;

create or replace function ops.province_scale_readiness(p_province_code text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_total integer;v_ready integer;v_pilot_ready integer;v_approved boolean;v_state text;v_master boolean;
begin
  select count(*) into v_total from ops.scale_gate_catalog where active;
  select count(*) into v_ready from ops.province_scale_gate_results r join ops.scale_gate_catalog c using(gate_key) where r.province_code=p_province_code and c.active and r.readiness_status='READY';
  select count(*) into v_pilot_ready from ops.province_scale_gate_results r where r.province_code=p_province_code and r.gate_key in ('SG-01','SG-02','SG-05','SG-06') and r.readiness_status='READY';
  select s.founder_approved,s.lifecycle_state into v_approved,v_state from ops.province_scale_state s where s.province_code=p_province_code;
  select coalesce((setting_value #>> '{}')::boolean,false) into v_master from config.system_settings where setting_key='province_scale_activation_enabled';
  return jsonb_build_object('province_code',p_province_code,'lifecycle_state',coalesce(v_state,'RESEARCH'),'gate_total',v_total,'gate_ready',v_ready,'pilot_prerequisite_ready',(v_pilot_ready=4),'all_scale_gates_ready',(v_total>0 and v_ready=v_total),'founder_approved',coalesce(v_approved,false),'activation_master_enabled',coalesce(v_master,false),'active_transition_ready',(v_total>0 and v_ready=v_total and coalesce(v_approved,false) and coalesce(v_master,false)));
end
$function$;

create or replace function ops.set_province_lifecycle(p_province_code text,p_new_state text,p_actor text,p_reason text default null)
returns jsonb language plpgsql security definer set search_path=''
as $function$
declare v_current text;v_ready jsonb;
begin
  if p_new_state not in ('RESEARCH','DEMAND_VALIDATION','PILOT','ACTIVE','PAUSED','CLOSED') then raise exception 'INVALID_PROVINCE_LIFECYCLE_STATE'; end if;
  insert into ops.province_scale_state(province_code,lifecycle_state,status_reason) values(p_province_code,'RESEARCH','Initialized by lifecycle control') on conflict(province_code) do nothing;
  select lifecycle_state into v_current from ops.province_scale_state where province_code=p_province_code for update;
  if p_new_state='PILOT' then v_ready:=ops.province_scale_readiness(p_province_code); if not coalesce((v_ready->>'pilot_prerequisite_ready')::boolean,false) then raise exception 'PILOT_SCALE_GATES_NOT_READY'; end if; end if;
  if p_new_state='ACTIVE' then v_ready:=ops.province_scale_readiness(p_province_code); if not coalesce((v_ready->>'active_transition_ready')::boolean,false) then raise exception 'ACTIVE_SCALE_GATES_NOT_READY'; end if; end if;
  update ops.province_scale_state set lifecycle_state=p_new_state,status_reason=p_reason,last_transition_at=now(),updated_at=now() where province_code=p_province_code;
  return jsonb_build_object('province_code',p_province_code,'from_state',v_current,'to_state',p_new_state,'actor',p_actor,'changed_at',now());
end
$function$;

revoke all on function authz.is_active_org_member(uuid) from public,anon; revoke all on function authz.has_portal_role(uuid,text) from public,anon; revoke all on function authz.is_verified_candidate_user(text) from public,anon; revoke all on function authz.current_candidate_id() from public,anon; revoke all on function ops.province_scale_readiness(text) from public,anon,authenticated; revoke all on function ops.set_province_lifecycle(text,text,text,text) from public,anon,authenticated;
grant execute on function authz.is_active_org_member(uuid) to authenticated,service_role; grant execute on function authz.has_portal_role(uuid,text) to authenticated,service_role; grant execute on function authz.is_verified_candidate_user(text) to authenticated,service_role; grant execute on function authz.current_candidate_id() to authenticated,service_role; grant execute on function ops.province_scale_readiness(text) to service_role; grant execute on function ops.set_province_lifecycle(text,text,text,text) to service_role;

alter table ops.scale_gate_catalog enable row level security; alter table ops.province_scale_state enable row level security; alter table ops.province_scale_gate_results enable row level security; alter table ops.portal_feature_flags enable row level security; alter table ops.portal_acceptance_catalog enable row level security; alter table ops.part7a_acceptance_catalog enable row level security;
revoke all on ops.scale_gate_catalog,ops.province_scale_state,ops.province_scale_gate_results,ops.portal_feature_flags,ops.portal_acceptance_catalog,ops.part7a_acceptance_catalog from public,anon,authenticated;
grant select,insert,update,delete on ops.scale_gate_catalog,ops.province_scale_state,ops.province_scale_gate_results,ops.portal_feature_flags,ops.portal_acceptance_catalog,ops.part7a_acceptance_catalog to service_role;