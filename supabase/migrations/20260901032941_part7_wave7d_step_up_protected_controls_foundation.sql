create or replace function authz.require_step_up_aal2()
returns void
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if coalesce(auth.jwt()->>'aal','aal1') <> 'aal2' then raise exception 'STEP_UP_AAL2_REQUIRED'; end if;
end $$;
revoke all on function authz.require_step_up_aal2() from public,anon,authenticated;
grant execute on function authz.require_step_up_aal2() to service_role;

create or replace function authz.user_has_capability(p_auth_user_id uuid,p_capability_key text)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(exists(
    select 1
    from authz.user_profiles up
    join authz.user_roles ur on ur.auth_user_id=up.auth_user_id
    join authz.role_capabilities rc on rc.role_key=ur.role_key
    join authz.role_catalog r on r.role_key=ur.role_key
    where up.auth_user_id=p_auth_user_id
      and up.status='ACTIVE'
      and ur.active=true
      and (ur.expires_at is null or ur.expires_at>now())
      and r.active=true
      and rc.capability_key=p_capability_key
  ),false)
$$;
revoke all on function authz.user_has_capability(uuid,text) from public,anon,authenticated;
grant execute on function authz.user_has_capability(uuid,text) to service_role;

insert into authz.role_capabilities(role_key,capability_key) values
('founder','portal_support_access'),
('secretary','portal_support_access')
on conflict do nothing;

create table ops.portal_support_access_audit (
  support_access_pk uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  auth_user_id uuid not null references auth.users(id) on delete restrict,
  target_portal_request_id uuid not null,
  raw_input_id text not null references ops.raw_inputs(raw_input_id) on delete restrict,
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  trace_id text not null,
  reason text not null,
  aal text not null check(aal='aal2'),
  access_status text not null default 'GRANTED' check(access_status in ('GRANTED','REVOKED','EXPIRED')),
  granted_at timestamptz not null default now(),
  valid_until timestamptz not null,
  created_at timestamptz not null default now(),
  check(valid_until>granted_at)
);
create index portal_support_access_auth_idx on ops.portal_support_access_audit(auth_user_id,valid_until desc);
create index portal_support_access_target_idx on ops.portal_support_access_audit(target_portal_request_id,valid_until desc);
create index portal_support_access_event_idx on ops.portal_support_access_audit(event_pk);
create index portal_support_access_raw_idx on ops.portal_support_access_audit(raw_input_id);
alter table ops.portal_support_access_audit enable row level security;
create policy portal_support_access_external_deny on ops.portal_support_access_audit as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.portal_support_access_audit from public,anon,authenticated;
grant all on ops.portal_support_access_audit to service_role;

insert into ops.domain_worker_contracts(worker_key,domain,allowed_event_types,command_type,target_entity_type,requires_raw_input,requires_file_intake,requires_approval,active,contract_version) values
('portal_org_membership_worker','Authorization',array['portal.organization.member_invite.requested'],'organization_member.invite','OrganizationMember',true,false,false,true,'P7D-V1'),
('portal_support_audit_worker','Security',array['portal.internal.support_access.recorded'],'portal_support_access.record','PortalSupportAccess',true,false,false,true,'P7D-V1')
on conflict(worker_key) do update set domain=excluded.domain,allowed_event_types=excluded.allowed_event_types,command_type=excluded.command_type,target_entity_type=excluded.target_entity_type,requires_raw_input=excluded.requires_raw_input,requires_file_intake=excluded.requires_file_intake,requires_approval=excluded.requires_approval,active=true,contract_version=excluded.contract_version,updated_at=now();

create or replace function api.portal_client_submit_payment_evidence(
  p_request_id uuid,
  p_org_id uuid,
  p_ar_id text,
  p_provider_file_ref text,
  p_original_filename text default null,
  p_content_type text default null,
  p_size_bytes bigint default null,
  p_checksum_sha256 text default null
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
  v_file_intake jsonb;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  perform authz.require_portal_feature_enabled('client_payment_evidence_upload',p_org_id);
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  if not authz.is_active_org_member(p_org_id) then raise exception 'ACTIVE_ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_finance') or authz.has_portal_role(p_org_id,'client_admin')) then raise exception 'CLIENT_FINANCE_ROLE_REQUIRED'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into v_existing from ops.portal_action_requests where request_id=p_request_id;
  if found then
    if v_existing.auth_user_id<>v_uid or v_existing.action_key<>'client.payment_evidence.submit' or v_existing.org_id is distinct from p_org_id then raise exception 'REQUEST_ID_REUSE_CONFLICT'; end if;
    return jsonb_build_object('request_id',v_existing.request_id,'request_status',v_existing.request_status,'raw_input_id',v_existing.raw_input_id,'event_pk',v_existing.event_pk,'duplicate_request',true);
  end if;
  select o.business_party_id into v_client_id from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORG_REQUIRED'; end if;
  if not exists(select 1 from finance.accounts_receivable ar where ar.ar_id=p_ar_id and ar.client_id=v_client_id) then raise exception 'AR_NOT_OWNED_BY_CLIENT_ORG'; end if;
  if nullif(btrim(coalesce(p_provider_file_ref,'')),'') is null then raise exception 'PROVIDER_FILE_REF_REQUIRED'; end if;
  if length(p_provider_file_ref)>1024 then raise exception 'PROVIDER_FILE_REF_TOO_LONG'; end if;
  if p_size_bytes is not null and p_size_bytes<0 then raise exception 'INVALID_FILE_SIZE'; end if;
  if p_checksum_sha256 is not null and p_checksum_sha256 !~ '^[0-9A-Fa-f]{64}$' then raise exception 'INVALID_SHA256'; end if;

  v_alloc:=config.allocate_business_id('Raw Input','portal_client:'||v_uid::text,jsonb_build_object('portal_action','client.payment_evidence.submit','request_id',p_request_id,'org_id',p_org_id,'ar_id',p_ar_id));
  v_raw_id:=v_alloc->>'allocated_id';
  v_trace:='portal:'||p_request_id::text;
  v_ingest:=ops.ingest_material_event(
    v_raw_id,'P7D-V1','MYC_PORTAL','PORTAL',
    'portal-client-payment-evidence-'||p_request_id::text,
    'portal|client|payment_evidence|'||v_uid::text||'|'||p_request_id::text,
    v_trace,'finance.payment_evidence.received',now(),'CLIENT','FILE',
    'portal://client/payment-evidence/'||p_request_id::text,
    v_uid::text,null,null,p_request_id::text,'Client submitted payment evidence for finance reconciliation','AccountsReceivable',p_ar_id,true,null,true,null,
    jsonb_build_object('portal_action_key','client.payment_evidence.submit','actor_auth_user_id',v_uid,'org_id',p_org_id,'client_id',v_client_id,'ar_id',p_ar_id,'request_id',p_request_id),null,null);
  v_event_pk:=(v_ingest->>'event_pk')::uuid;
  v_file_intake:=ops.register_file_intake(
    v_raw_id,'MYC_PORTAL',p_provider_file_ref,p_org_id::text,p_original_filename,p_content_type,p_size_bytes,p_checksum_sha256,
    'SOURCE_ONLY',true,
    jsonb_build_object('portal_action_key','client.payment_evidence.submit','org_id',p_org_id,'client_id',v_client_id,'ar_id',p_ar_id,'actor_auth_user_id',v_uid,'request_id',p_request_id,'storage_profile','evidence-private'));
  insert into ops.portal_action_requests(request_id,action_key,auth_user_id,org_id,target_entity_type,target_entity_id,raw_input_id,event_pk,trace_id,request_status)
  values(p_request_id,'client.payment_evidence.submit',v_uid,p_org_id,'AccountsReceivable',p_ar_id,v_raw_id,v_event_pk,v_trace,'REVIEW_REQUIRED');
  return jsonb_build_object('request_id',p_request_id,'request_status','REVIEW_REQUIRED','raw_input_id',v_raw_id,'event_pk',v_event_pk,'file_intake_pk',v_file_intake->>'file_intake_pk','duplicate_request',false,'finance_state_changed',false);
end $$;
revoke all on function api.portal_client_submit_payment_evidence(uuid,uuid,text,text,text,text,bigint,text) from public,anon;
grant execute on function api.portal_client_submit_payment_evidence(uuid,uuid,text,text,text,text,bigint,text) to authenticated,service_role;

create or replace function api.portal_partner_invite_member(
  p_request_id uuid,
  p_org_id uuid,
  p_invited_auth_user_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_existing ops.portal_action_requests;
  v_partner_id text;
  v_alloc jsonb;
  v_raw_id text;
  v_trace text;
  v_ingest jsonb;
  v_event_pk uuid;
begin
  perform authz.require_external_portal_enabled('PARTNER');
  perform authz.require_portal_feature_enabled('partner_member_manage',p_org_id);
  perform authz.require_step_up_aal2();
  if not authz.has_portal_role(p_org_id,'partner_admin') then raise exception 'PARTNER_ADMIN_REQUIRED'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select * into v_existing from ops.portal_action_requests where request_id=p_request_id;
  if found then
    if v_existing.auth_user_id<>v_uid or v_existing.action_key<>'partner.member.invite' or v_existing.org_id is distinct from p_org_id then raise exception 'REQUEST_ID_REUSE_CONFLICT'; end if;
    return jsonb_build_object('request_id',v_existing.request_id,'request_status',v_existing.request_status,'raw_input_id',v_existing.raw_input_id,'event_pk',v_existing.event_pk,'duplicate_request',true);
  end if;
  select o.business_party_id into v_partner_id from authz.organizations o where o.org_id=p_org_id and o.org_type='PARTNER' and o.status='ACTIVE';
  if v_partner_id is null then raise exception 'ACTIVE_PARTNER_ORG_REQUIRED'; end if;
  if p_invited_auth_user_id is null or not exists(select 1 from auth.users where id=p_invited_auth_user_id) then raise exception 'INVITED_AUTH_USER_NOT_FOUND'; end if;
  if p_invited_auth_user_id=v_uid then raise exception 'SELF_INVITE_NOT_ALLOWED'; end if;
  if exists(select 1 from authz.organization_members where org_id=p_org_id and auth_user_id=p_invited_auth_user_id) then raise exception 'ORGANIZATION_MEMBER_ALREADY_EXISTS'; end if;

  v_alloc:=config.allocate_business_id('Raw Input','portal_partner:'||v_uid::text,jsonb_build_object('portal_action','partner.member.invite','request_id',p_request_id,'org_id',p_org_id));
  v_raw_id:=v_alloc->>'allocated_id';
  v_trace:='portal:'||p_request_id::text;
  v_ingest:=ops.ingest_material_event(
    v_raw_id,'P7D-V1','MYC_PORTAL','PORTAL',
    'portal-partner-member-invite-'||p_request_id::text,
    'portal|partner|member_invite|'||v_uid::text||'|'||p_request_id::text,
    v_trace,'portal.organization.member_invite.requested',now(),'PARTNER','JSON',
    'portal://partner/member-invite/'||p_request_id::text,
    v_uid::text,null,null,p_request_id::text,'Partner Admin requested invitation of a member to own organization','Organization',p_org_id::text,false,null,true,null,
    jsonb_build_object('portal_action_key','partner.member.invite','actor_auth_user_id',v_uid,'org_id',p_org_id,'partner_id',v_partner_id,'invited_auth_user_id',p_invited_auth_user_id,'portal_role','partner_member','request_id',p_request_id,'aal','aal2'),null,null);
  v_event_pk:=(v_ingest->>'event_pk')::uuid;
  insert into ops.portal_action_requests(request_id,action_key,auth_user_id,org_id,target_entity_type,target_entity_id,raw_input_id,event_pk,trace_id,request_status)
  values(p_request_id,'partner.member.invite',v_uid,p_org_id,'OrganizationMember',p_invited_auth_user_id::text,v_raw_id,v_event_pk,v_trace,'ACCEPTED');
  return jsonb_build_object('request_id',p_request_id,'request_status','ACCEPTED','raw_input_id',v_raw_id,'event_pk',v_event_pk,'invited_auth_user_id',p_invited_auth_user_id,'portal_role','partner_member','duplicate_request',false,'membership_status','PENDING_WORKER');
end $$;
revoke all on function api.portal_partner_invite_member(uuid,uuid,uuid) from public,anon;
grant execute on function api.portal_partner_invite_member(uuid,uuid,uuid) to authenticated,service_role;

create or replace function api.request_portal_support_access(
  p_request_id uuid,
  p_target_portal_request_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_uid uuid:=auth.uid();
  v_existing ops.portal_action_requests;
  v_target ops.portal_action_requests;
  v_alloc jsonb;
  v_raw_id text;
  v_trace text;
  v_ingest jsonb;
  v_event_pk uuid;
begin
  perform authz.require_capability('portal_support_access');
  perform authz.require_step_up_aal2();
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if p_target_portal_request_id is null then raise exception 'TARGET_PORTAL_REQUEST_REQUIRED'; end if;
  if nullif(btrim(coalesce(p_reason,'')),'') is null or length(p_reason)>1000 then raise exception 'VALID_SUPPORT_REASON_REQUIRED'; end if;
  select * into v_existing from ops.portal_action_requests where request_id=p_request_id;
  if found then
    if v_existing.auth_user_id<>v_uid or v_existing.action_key<>'internal.support.case_access' then raise exception 'REQUEST_ID_REUSE_CONFLICT'; end if;
    return jsonb_build_object('request_id',v_existing.request_id,'request_status',v_existing.request_status,'raw_input_id',v_existing.raw_input_id,'event_pk',v_existing.event_pk,'duplicate_request',true);
  end if;
  select * into v_target from ops.portal_action_requests where request_id=p_target_portal_request_id;
  if not found then raise exception 'TARGET_PORTAL_REQUEST_NOT_FOUND'; end if;

  v_alloc:=config.allocate_business_id('Raw Input','portal_support:'||v_uid::text,jsonb_build_object('portal_action','internal.support.case_access','request_id',p_request_id,'target_request_id',p_target_portal_request_id));
  v_raw_id:=v_alloc->>'allocated_id';
  v_trace:='portal-support:'||p_request_id::text;
  v_ingest:=ops.ingest_material_event(
    v_raw_id,'P7D-V1','MYC_INTERNAL','INTERNAL',
    'portal-support-access-'||p_request_id::text,
    'portal|internal|support_access|'||v_uid::text||'|'||p_request_id::text,
    v_trace,'portal.internal.support_access.recorded',now(),'INTERNAL','JSON',
    'internal://portal/support-access/'||p_request_id::text,
    v_uid::text,null,null,p_request_id::text,'Authorized internal support requested scoped access to a Portal action','PortalActionRequest',p_target_portal_request_id::text,false,null,true,null,
    jsonb_build_object('portal_action_key','internal.support.case_access','actor_auth_user_id',v_uid,'target_portal_request_id',p_target_portal_request_id,'reason',p_reason,'request_id',p_request_id,'aal','aal2'),null,null);
  v_event_pk:=(v_ingest->>'event_pk')::uuid;
  insert into ops.portal_action_requests(request_id,action_key,auth_user_id,target_entity_type,target_entity_id,raw_input_id,event_pk,trace_id,request_status)
  values(p_request_id,'internal.support.case_access',v_uid,'PortalActionRequest',p_target_portal_request_id::text,v_raw_id,v_event_pk,v_trace,'ACCEPTED');
  return jsonb_build_object('request_id',p_request_id,'request_status','ACCEPTED','raw_input_id',v_raw_id,'event_pk',v_event_pk,'target_portal_request_id',p_target_portal_request_id,'duplicate_request',false,'access_granted',false);
end $$;
revoke all on function api.request_portal_support_access(uuid,uuid,text) from public,anon;
grant execute on function api.request_portal_support_access(uuid,uuid,text) to authenticated,service_role;

create or replace function api.portal_support_action_request(p_target_portal_request_id uuid)
returns table(
  request_id uuid,
  action_key text,
  request_status text,
  org_id uuid,
  candidate_id text,
  target_entity_type text,
  target_entity_id text,
  created_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('portal_support_access');
  perform authz.require_step_up_aal2();
  if not exists(
    select 1 from ops.portal_support_access_audit a
    where a.auth_user_id=auth.uid()
      and a.target_portal_request_id=p_target_portal_request_id
      and a.access_status='GRANTED'
      and a.valid_until>now()
  ) then raise exception 'ACTIVE_SUPPORT_ACCESS_GRANT_REQUIRED'; end if;
  return query
    select r.request_id,r.action_key,r.request_status,r.org_id,r.candidate_id,r.target_entity_type,r.target_entity_id,r.created_at,r.updated_at
    from ops.portal_action_requests r where r.request_id=p_target_portal_request_id;
end $$;
revoke all on function api.portal_support_action_request(uuid) from public,anon;
grant execute on function api.portal_support_action_request(uuid) to authenticated,service_role;

create table ops.part7d_acceptance_catalog (
  test_id text primary key,
  scenario text not null,
  expected_behavior text not null,
  status text not null default 'NOT_RUN' check(status in ('NOT_RUN','PASS','FAIL')),
  evidence_ref text,
  last_tested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into ops.part7d_acceptance_catalog(test_id,scenario,expected_behavior) values
('P7D-001','AAL1 is denied for protected Partner membership command','DENY'),
('P7D-002','AAL2 Partner Admin may request own-org partner_member invitation','PASS'),
('P7D-003','Partner Admin cannot invite into another organization','DENY'),
('P7D-004','Membership worker creates INVITED membership only and revalidates caller membership','PASS'),
('P7D-005','Client Finance submits own AR payment evidence as Raw/File Intake/Event without changing collected truth','PASS'),
('P7D-006','Client Finance cannot submit evidence for another Client AR or directly mark COLLECTED','DENY'),
('P7D-007','AAL2 internal support capability creates audited scoped grant before support read','PASS'),
('P7D-008','AAL1 or unauthorized internal identity cannot obtain support access','DENY')
on conflict(test_id) do nothing;
alter table ops.part7d_acceptance_catalog enable row level security;
create policy part7d_acceptance_external_deny on ops.part7d_acceptance_catalog as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.part7d_acceptance_catalog from public,anon,authenticated;
grant all on ops.part7d_acceptance_catalog to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
('part7d_step_up_foundation_ready','true'::jsonb,'Part 7D S7 step-up and protected Portal control APIs installed in TEST.','Part7D',now()),
('part7d_foundation_closed','false'::jsonb,'Part 7D closeout not yet complete.','Part7D',now())
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;