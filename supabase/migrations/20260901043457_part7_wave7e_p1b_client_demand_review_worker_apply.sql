create or replace function ops.apply_portal_client_demand_review_command(
  p_command_pk uuid,
  p_lease_token uuid,
  p_actor text default 'portal_client_demand_review_worker'
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
  v_client_id text;
  v_review_pk uuid;
  v_effect_ref text;
  v_result jsonb;
  v_finish jsonb;
begin
  if p_actor is null or btrim(p_actor)='' then raise exception 'ACTOR_REQUIRED'; end if;
  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk for update;
  if not found then raise exception 'UNKNOWN_COMMAND_PK'; end if;
  if v_cmd.command_type<>'client_demand.review_queue' or v_cmd.worker_key<>'portal_client_demand_review_worker' then raise exception 'CLIENT_DEMAND_REVIEW_COMMAND_REQUIRED'; end if;
  if v_cmd.apply_status='APPLIED' then return jsonb_build_object('command_pk',v_cmd.command_pk,'apply_status','APPLIED','duplicate_apply',true,'master_effect_ref',v_cmd.master_effect_ref,'job_master_changed',false); end if;
  if v_cmd.validation_status<>'VALID' or v_cmd.apply_status not in ('READY','BLOCKED') then raise exception 'COMMAND_NOT_READY'; end if;

  select * into v_run from ops.worker_runs
   where worker_run_pk=v_cmd.worker_run_pk and event_pk=v_cmd.event_pk and worker_key='portal_client_demand_review_worker'
     and lease_token=p_lease_token and status='CLAIMED' and lease_until>now();
  if not found then raise exception 'VALID_ACTIVE_CLIENT_DEMAND_WORKER_LEASE_REQUIRED'; end if;

  select * into v_req from ops.portal_action_requests
   where event_pk=v_cmd.event_pk and action_key='client.job_demand.submit' for update;
  if not found then raise exception 'PORTAL_ACTION_REQUEST_REQUIRED'; end if;
  select * into v_raw from ops.raw_inputs where raw_input_id=v_req.raw_input_id;
  if not found then raise exception 'RAW_INPUT_REQUIRED'; end if;
  if v_req.raw_input_id is distinct from v_cmd.source_raw_input_id or v_req.org_id is null then raise exception 'CLIENT_DEMAND_PROVENANCE_MISMATCH'; end if;

  select o.business_party_id into v_client_id
  from authz.organizations o
  where o.org_id=v_req.org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORG_REQUIRED_AT_APPLY'; end if;
  if v_req.target_entity_id is distinct from v_client_id then raise exception 'CLIENT_DEMAND_TARGET_MISMATCH'; end if;
  if (v_raw.metadata->>'actor_auth_user_id')::uuid is distinct from v_req.auth_user_id
     or (v_raw.metadata->>'org_id')::uuid is distinct from v_req.org_id
     or v_raw.metadata->>'client_id' is distinct from v_client_id
     or (v_raw.metadata->>'request_id')::uuid is distinct from v_req.request_id
     or v_raw.metadata->>'portal_action_key'<>'client.job_demand.submit'
     or v_raw.metadata->>'operational_source'<>'GOOGLE_SHEETS_DRIVE'
     or jsonb_typeof(v_raw.metadata->'demand')<>'object' then
    raise exception 'CLIENT_DEMAND_RAW_PROVENANCE_MISMATCH';
  end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then
    raise exception 'P1B_REVIEW_WORKER_REQUIRES_GOOGLE_SHEETS_DRIVE_SOURCE';
  end if;

  insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id)
  values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'APPLYING',p_actor,'ClientDemandReview',v_req.request_id::text)
  on conflict(command_pk) do update set status='APPLYING',actor=excluded.actor,error_class=null,error_message=null,started_at=now(),finished_at=null,updated_at=now();

  insert into ops.client_demand_review_queue(request_id,org_id,client_id,submitted_by,raw_input_id,event_pk,trace_id,demand_payload,review_status)
  values(v_req.request_id,v_req.org_id,v_client_id,v_req.auth_user_id,v_req.raw_input_id,v_req.event_pk,v_req.trace_id,v_raw.metadata->'demand','PENDING_REVIEW')
  on conflict(request_id) do update set updated_at=now()
  returning review_pk into v_review_pk;

  v_effect_ref:='ops.client_demand_review_queue:'||v_review_pk::text;
  v_finish:=ops.finish_event_success(
    v_run.worker_run_pk,p_lease_token,
    'portal_client_demand_review','portal_client_demand_review|'||v_cmd.command_key,
    'ClientDemandReview',v_req.request_id::text,v_effect_ref,
    jsonb_build_object('portal_request_id',v_req.request_id,'org_id',v_req.org_id,'client_id',v_client_id,'review_pk',v_review_pk,'review_status','PENDING_REVIEW','operational_source','GOOGLE_SHEETS_DRIVE','job_master_changed',false),now()
  );

  v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','APPLIED','duplicate_apply',false,'review_pk',v_review_pk,'review_status','PENDING_REVIEW','master_effect_ref',v_effect_ref,'job_master_changed',false,'operational_source','GOOGLE_SHEETS_DRIVE');
  update ops.domain_commands set apply_status='APPLIED',target_entity_type='ClientDemandReview',target_entity_id=v_req.request_id::text,master_effect_ref=v_effect_ref,applied_at=now(),updated_at=now() where command_pk=p_command_pk;
  update ops.domain_command_apply_audit set status='APPLIED',target_entity_type='ClientDemandReview',target_entity_id=v_req.request_id::text,effect_ref=v_effect_ref,result=v_result,error_class=null,error_message=null,finished_at=now(),updated_at=now() where command_pk=p_command_pk;
  update ops.portal_action_requests set request_status='REVIEW_REQUIRED',effect_ref=v_effect_ref,updated_at=now() where request_pk=v_req.request_pk;
  return v_result || jsonb_build_object('worker_finish',v_finish);
end $$;
revoke all on function ops.apply_portal_client_demand_review_command(uuid,uuid,text) from public,anon,authenticated;
grant execute on function ops.apply_portal_client_demand_review_command(uuid,uuid,text) to service_role;