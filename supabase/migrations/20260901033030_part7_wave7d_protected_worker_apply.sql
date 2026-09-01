create or replace function ops.apply_portal_org_member_invite_command(
  p_command_pk uuid,
  p_lease_token uuid,
  p_actor text default 'portal_org_membership_worker'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_cmd ops.domain_commands;
  v_run ops.worker_runs;
  v_req ops.portal_action_requests;
  v_raw ops.raw_inputs;
  v_invited uuid;
  v_result jsonb;
  v_finish jsonb;
  v_effect_ref text;
begin
  if p_actor is null or btrim(p_actor)='' then raise exception 'ACTOR_REQUIRED'; end if;
  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk for update;
  if not found then raise exception 'UNKNOWN_COMMAND_PK'; end if;
  if v_cmd.command_type<>'organization_member.invite' or v_cmd.worker_key<>'portal_org_membership_worker' then raise exception 'PORTAL_ORG_INVITE_COMMAND_REQUIRED'; end if;
  if v_cmd.apply_status='APPLIED' then return jsonb_build_object('command_pk',v_cmd.command_pk,'apply_status','APPLIED','duplicate_apply',true,'master_effect_ref',v_cmd.master_effect_ref); end if;
  if v_cmd.validation_status<>'VALID' or v_cmd.apply_status not in ('READY','BLOCKED') then raise exception 'COMMAND_NOT_READY'; end if;
  select * into v_run from ops.worker_runs where worker_run_pk=v_cmd.worker_run_pk and event_pk=v_cmd.event_pk and worker_key='portal_org_membership_worker' and lease_token=p_lease_token and status='CLAIMED' and lease_until>now();
  if not found then raise exception 'VALID_ACTIVE_PORTAL_WORKER_LEASE_REQUIRED'; end if;
  select * into v_req from ops.portal_action_requests where event_pk=v_cmd.event_pk and action_key='partner.member.invite' for update;
  if not found then raise exception 'PORTAL_ACTION_REQUEST_REQUIRED'; end if;
  select * into v_raw from ops.raw_inputs where raw_input_id=v_req.raw_input_id;
  if not found then raise exception 'RAW_INPUT_REQUIRED'; end if;
  if v_req.raw_input_id is distinct from v_cmd.source_raw_input_id or v_req.org_id is null or v_req.target_entity_id is null then raise exception 'PORTAL_COMMAND_PROVENANCE_MISMATCH'; end if;
  v_invited:=v_req.target_entity_id::uuid;
  if (v_raw.metadata->>'actor_auth_user_id')::uuid is distinct from v_req.auth_user_id
     or (v_raw.metadata->>'org_id')::uuid is distinct from v_req.org_id
     or (v_raw.metadata->>'invited_auth_user_id')::uuid is distinct from v_invited
     or v_raw.metadata->>'portal_role'<>'partner_member'
     or v_raw.metadata->>'aal'<>'aal2'
     or (v_raw.metadata->>'request_id')::uuid is distinct from v_req.request_id then raise exception 'PORTAL_RAW_IDENTITY_PROVENANCE_MISMATCH'; end if;
  if not exists(
    select 1 from authz.organization_members m join authz.organizations o on o.org_id=m.org_id
    where m.org_id=v_req.org_id and m.auth_user_id=v_req.auth_user_id and m.portal_role='partner_admin'
      and m.membership_status='ACTIVE' and m.removed_at is null and (m.active_from is null or m.active_from<=now()) and (m.expires_at is null or m.expires_at>now())
      and o.org_type='PARTNER' and o.status='ACTIVE'
  ) then
    v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','PARTNER_ADMIN_MEMBERSHIP_NOT_ACTIVE');
    insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id,result,error_class,error_message,finished_at)
    values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'BLOCKED',p_actor,'OrganizationMember',v_invited::text,v_result,'AUTHZ_REVOKED','Partner Admin membership not active at apply time',now())
    on conflict(command_pk) do update set status='BLOCKED',actor=excluded.actor,result=excluded.result,error_class=excluded.error_class,error_message=excluded.error_message,finished_at=excluded.finished_at,updated_at=now();
    update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
    update ops.portal_action_requests set request_status='BLOCKED',updated_at=now() where request_pk=v_req.request_pk;
    return v_result;
  end if;
  if not exists(select 1 from auth.users where id=v_invited) then raise exception 'INVITED_AUTH_USER_NOT_FOUND_AT_APPLY'; end if;
  if exists(select 1 from authz.organization_members where org_id=v_req.org_id and auth_user_id=v_invited) then raise exception 'ORGANIZATION_MEMBER_ALREADY_EXISTS_AT_APPLY'; end if;

  insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id)
  values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'APPLYING',p_actor,'OrganizationMember',v_invited::text)
  on conflict(command_pk) do update set status='APPLYING',actor=excluded.actor,error_class=null,error_message=null,started_at=now(),finished_at=null,updated_at=now();

  insert into authz.organization_members(org_id,auth_user_id,portal_role,membership_status,invited_at,created_by)
  values(v_req.org_id,v_invited,'partner_member','INVITED',now(),'portal_partner:'||v_req.auth_user_id::text);
  v_effect_ref:='authz.organization_members:'||v_req.org_id::text||':'||v_invited::text;
  v_finish:=ops.finish_event_success(v_run.worker_run_pk,p_lease_token,'portal_org_member_invite','portal_org_member_invite|'||v_cmd.command_key,'OrganizationMember',v_invited::text,v_effect_ref,jsonb_build_object('portal_request_id',v_req.request_id,'org_id',v_req.org_id,'invited_auth_user_id',v_invited,'membership_status','INVITED'),now());
  v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','APPLIED','duplicate_apply',false,'org_id',v_req.org_id,'invited_auth_user_id',v_invited,'membership_status','INVITED','master_effect_ref',v_effect_ref);
  update ops.domain_commands set apply_status='APPLIED',target_entity_type='OrganizationMember',target_entity_id=v_invited::text,master_effect_ref=v_effect_ref,applied_at=now(),updated_at=now() where command_pk=p_command_pk;
  update ops.domain_command_apply_audit set status='APPLIED',target_entity_type='OrganizationMember',target_entity_id=v_invited::text,effect_ref=v_effect_ref,result=v_result,error_class=null,error_message=null,finished_at=now(),updated_at=now() where command_pk=p_command_pk;
  update ops.portal_action_requests set request_status='APPLIED',effect_ref=v_effect_ref,updated_at=now() where request_pk=v_req.request_pk;
  return v_result || jsonb_build_object('worker_finish',v_finish);
end $$;
revoke all on function ops.apply_portal_org_member_invite_command(uuid,uuid,text) from public,anon,authenticated;
grant execute on function ops.apply_portal_org_member_invite_command(uuid,uuid,text) to service_role;

create or replace function ops.apply_portal_support_access_command(
  p_command_pk uuid,
  p_lease_token uuid,
  p_actor text default 'portal_support_audit_worker'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_cmd ops.domain_commands;
  v_run ops.worker_runs;
  v_req ops.portal_action_requests;
  v_raw ops.raw_inputs;
  v_target_request uuid;
  v_reason text;
  v_access_pk uuid;
  v_security_pk uuid;
  v_result jsonb;
  v_finish jsonb;
  v_effect_ref text;
begin
  if p_actor is null or btrim(p_actor)='' then raise exception 'ACTOR_REQUIRED'; end if;
  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk for update;
  if not found then raise exception 'UNKNOWN_COMMAND_PK'; end if;
  if v_cmd.command_type<>'portal_support_access.record' or v_cmd.worker_key<>'portal_support_audit_worker' then raise exception 'PORTAL_SUPPORT_COMMAND_REQUIRED'; end if;
  if v_cmd.apply_status='APPLIED' then return jsonb_build_object('command_pk',v_cmd.command_pk,'apply_status','APPLIED','duplicate_apply',true,'master_effect_ref',v_cmd.master_effect_ref); end if;
  if v_cmd.validation_status<>'VALID' or v_cmd.apply_status not in ('READY','BLOCKED') then raise exception 'COMMAND_NOT_READY'; end if;
  select * into v_run from ops.worker_runs where worker_run_pk=v_cmd.worker_run_pk and event_pk=v_cmd.event_pk and worker_key='portal_support_audit_worker' and lease_token=p_lease_token and status='CLAIMED' and lease_until>now();
  if not found then raise exception 'VALID_ACTIVE_PORTAL_WORKER_LEASE_REQUIRED'; end if;
  select * into v_req from ops.portal_action_requests where event_pk=v_cmd.event_pk and action_key='internal.support.case_access' for update;
  if not found then raise exception 'PORTAL_ACTION_REQUEST_REQUIRED'; end if;
  select * into v_raw from ops.raw_inputs where raw_input_id=v_req.raw_input_id;
  if not found then raise exception 'RAW_INPUT_REQUIRED'; end if;
  v_target_request:=v_req.target_entity_id::uuid;
  v_reason:=v_raw.metadata->>'reason';
  if v_req.raw_input_id is distinct from v_cmd.source_raw_input_id
     or (v_raw.metadata->>'actor_auth_user_id')::uuid is distinct from v_req.auth_user_id
     or (v_raw.metadata->>'target_portal_request_id')::uuid is distinct from v_target_request
     or (v_raw.metadata->>'request_id')::uuid is distinct from v_req.request_id
     or v_raw.metadata->>'aal'<>'aal2' then raise exception 'PORTAL_SUPPORT_PROVENANCE_MISMATCH'; end if;
  if not authz.user_has_capability(v_req.auth_user_id,'portal_support_access') then
    v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','PORTAL_SUPPORT_CAPABILITY_REVOKED');
    insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id,result,error_class,error_message,finished_at)
    values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'BLOCKED',p_actor,'PortalSupportAccess',v_target_request::text,v_result,'AUTHZ_REVOKED','Support capability not active at apply time',now())
    on conflict(command_pk) do update set status='BLOCKED',actor=excluded.actor,result=excluded.result,error_class=excluded.error_class,error_message=excluded.error_message,finished_at=excluded.finished_at,updated_at=now();
    update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
    update ops.portal_action_requests set request_status='BLOCKED',updated_at=now() where request_pk=v_req.request_pk;
    return v_result;
  end if;
  if not exists(select 1 from ops.portal_action_requests where request_id=v_target_request) then raise exception 'TARGET_PORTAL_REQUEST_NOT_FOUND_AT_APPLY'; end if;

  insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id)
  values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'APPLYING',p_actor,'PortalSupportAccess',v_target_request::text)
  on conflict(command_pk) do update set status='APPLYING',actor=excluded.actor,error_class=null,error_message=null,started_at=now(),finished_at=null,updated_at=now();

  insert into ops.portal_support_access_audit(request_id,auth_user_id,target_portal_request_id,raw_input_id,event_pk,trace_id,reason,aal,access_status,granted_at,valid_until)
  values(v_req.request_id,v_req.auth_user_id,v_target_request,v_req.raw_input_id,v_req.event_pk,v_req.trace_id,v_reason,'aal2','GRANTED',now(),now()+interval '15 minutes')
  returning support_access_pk into v_access_pk;
  v_security_pk:=ops.record_security_event('TEST','SEV3','PORTAL_SUPPORT_ACCESS_GRANTED','AAL2 internal support access granted to a single Portal action request','auth_user:'||v_req.auth_user_id::text,'portal_support_audit_worker','PortalActionRequest',v_target_request::text,v_req.trace_id,v_req.event_pk::text,'GRANTED','ops.portal_support_access_audit:'||v_access_pk::text,jsonb_build_object('support_access_pk',v_access_pk,'portal_request_id',v_req.request_id,'target_portal_request_id',v_target_request,'valid_minutes',15),'CLOSED');
  v_effect_ref:='ops.portal_support_access_audit:'||v_access_pk::text;
  v_finish:=ops.finish_event_success(v_run.worker_run_pk,p_lease_token,'portal_support_access','portal_support_access|'||v_cmd.command_key,'PortalSupportAccess',v_target_request::text,v_effect_ref,jsonb_build_object('portal_request_id',v_req.request_id,'support_access_pk',v_access_pk,'security_event_pk',v_security_pk,'target_portal_request_id',v_target_request),now());
  v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','APPLIED','duplicate_apply',false,'support_access_pk',v_access_pk,'security_event_pk',v_security_pk,'target_portal_request_id',v_target_request,'master_effect_ref',v_effect_ref);
  update ops.domain_commands set apply_status='APPLIED',target_entity_type='PortalSupportAccess',target_entity_id=v_target_request::text,master_effect_ref=v_effect_ref,applied_at=now(),updated_at=now() where command_pk=p_command_pk;
  update ops.domain_command_apply_audit set status='APPLIED',target_entity_type='PortalSupportAccess',target_entity_id=v_target_request::text,effect_ref=v_effect_ref,result=v_result,error_class=null,error_message=null,finished_at=now(),updated_at=now() where command_pk=p_command_pk;
  update ops.portal_action_requests set request_status='APPLIED',effect_ref=v_effect_ref,updated_at=now() where request_pk=v_req.request_pk;
  return v_result || jsonb_build_object('worker_finish',v_finish);
end $$;
revoke all on function ops.apply_portal_support_access_command(uuid,uuid,text) from public,anon,authenticated;
grant execute on function ops.apply_portal_support_access_command(uuid,uuid,text) to service_role;