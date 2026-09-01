create or replace function ops.apply_portal_candidate_contact_command(
  p_command_pk uuid,
  p_lease_token uuid,
  p_actor text default 'portal_candidate_contact_worker'
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
  v_patch jsonb;
  v_raw_patch jsonb;
  v_bad_keys text[];
  v_audit ops.domain_command_apply_audit;
  v_result jsonb;
  v_finish jsonb;
  v_effect_ref text;
  v_effect_key text;
begin
  if p_actor is null or btrim(p_actor)='' then raise exception 'ACTOR_REQUIRED'; end if;

  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk for update;
  if not found then raise exception 'UNKNOWN_COMMAND_PK'; end if;
  if v_cmd.command_type<>'candidate_contact.update_proposal' or v_cmd.worker_key<>'portal_candidate_contact_worker' then
    raise exception 'PORTAL_CANDIDATE_CONTACT_COMMAND_REQUIRED';
  end if;

  if v_cmd.apply_status='APPLIED' then
    return jsonb_build_object(
      'command_pk',v_cmd.command_pk,
      'apply_status','APPLIED',
      'duplicate_apply',true,
      'master_effect_ref',v_cmd.master_effect_ref
    );
  end if;
  if v_cmd.validation_status<>'VALID' or v_cmd.apply_status not in ('READY','BLOCKED') then
    raise exception 'COMMAND_NOT_READY';
  end if;

  select * into v_run
  from ops.worker_runs
  where worker_run_pk=v_cmd.worker_run_pk
    and event_pk=v_cmd.event_pk
    and worker_key='portal_candidate_contact_worker'
    and lease_token=p_lease_token
    and status='CLAIMED'
    and lease_until>now();
  if not found then raise exception 'VALID_ACTIVE_PORTAL_WORKER_LEASE_REQUIRED'; end if;

  select * into v_req
  from ops.portal_action_requests
  where event_pk=v_cmd.event_pk
    and action_key='candidate.contact.propose'
  for update;
  if not found then raise exception 'PORTAL_ACTION_REQUEST_REQUIRED'; end if;
  if v_req.raw_input_id is distinct from v_cmd.source_raw_input_id
     or v_req.candidate_id is distinct from v_cmd.target_entity_id then
    raise exception 'PORTAL_COMMAND_PROVENANCE_MISMATCH';
  end if;

  select * into v_raw from ops.raw_inputs where raw_input_id=v_req.raw_input_id;
  if not found then raise exception 'RAW_INPUT_REQUIRED'; end if;

  v_patch:=coalesce(v_cmd.payload->'fields','{}'::jsonb);
  v_raw_patch:=coalesce(v_raw.metadata->'portal_payload','{}'::jsonb);
  if jsonb_typeof(v_patch)<>'object' or v_patch='{}'::jsonb then raise exception 'CONTACT_PATCH_REQUIRED'; end if;
  if v_patch is distinct from v_raw_patch then raise exception 'PORTAL_COMMAND_PAYLOAD_PROVENANCE_MISMATCH'; end if;
  select array_agg(k) into v_bad_keys from jsonb_object_keys(v_patch) k where k not in ('phone','line_id','email');
  if v_bad_keys is not null then raise exception 'CONTACT_FIELD_NOT_ALLOWED:%',array_to_string(v_bad_keys,','); end if;

  if (v_raw.metadata->>'actor_auth_user_id')::uuid is distinct from v_req.auth_user_id
     or v_raw.metadata->>'candidate_id' is distinct from v_req.candidate_id
     or (v_raw.metadata->>'request_id')::uuid is distinct from v_req.request_id then
    raise exception 'PORTAL_RAW_IDENTITY_PROVENANCE_MISMATCH';
  end if;

  if not exists(
    select 1 from authz.candidate_user_links l
    where l.auth_user_id=v_req.auth_user_id
      and l.candidate_id=v_req.candidate_id
      and l.verification_status='VERIFIED'
      and l.disabled_at is null
  ) then
    v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','VERIFIED_CANDIDATE_LINK_REQUIRED');
    insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id,result,error_class,error_message,finished_at)
    values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'BLOCKED',p_actor,'CandidateContact',v_req.candidate_id,v_result,'AUTHZ_REVOKED','Candidate link not active at apply time',now())
    on conflict(command_pk) do update set status='BLOCKED',actor=excluded.actor,result=excluded.result,error_class=excluded.error_class,error_message=excluded.error_message,finished_at=excluded.finished_at,updated_at=now();
    update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
    update ops.portal_action_requests set request_status='BLOCKED',updated_at=now() where request_pk=v_req.request_pk;
    return v_result;
  end if;

  if not config.setting_is_true('business_master_apply_enabled') then
    v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','GATE_DISABLED','gate_key','business_master_apply_enabled');
    insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id,result,error_class,error_message,finished_at)
    values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'BLOCKED',p_actor,'CandidateContact',v_req.candidate_id,v_result,'GATE_DISABLED','Business master apply gate is disabled',now())
    on conflict(command_pk) do update set status='BLOCKED',actor=excluded.actor,result=excluded.result,error_class=excluded.error_class,error_message=excluded.error_message,finished_at=excluded.finished_at,updated_at=now();
    update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
    update ops.portal_action_requests set request_status='BLOCKED',updated_at=now() where request_pk=v_req.request_pk;
    return v_result;
  end if;

  insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id)
  values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'APPLYING',p_actor,'CandidateContact',v_req.candidate_id)
  on conflict(command_pk) do update set status='APPLYING',actor=excluded.actor,error_class=null,error_message=null,started_at=now(),finished_at=null,updated_at=now()
  returning * into v_audit;

  insert into private.candidate_contacts(candidate_id,phone,line_id,email,source_raw_input_id)
  values(
    v_req.candidate_id,
    case when v_patch ? 'phone' then nullif(v_patch->>'phone','') else null end,
    case when v_patch ? 'line_id' then nullif(v_patch->>'line_id','') else null end,
    case when v_patch ? 'email' then nullif(v_patch->>'email','') else null end,
    v_req.raw_input_id
  )
  on conflict(candidate_id) do update set
    phone=case when v_patch ? 'phone' then nullif(v_patch->>'phone','') else private.candidate_contacts.phone end,
    line_id=case when v_patch ? 'line_id' then nullif(v_patch->>'line_id','') else private.candidate_contacts.line_id end,
    email=case when v_patch ? 'email' then nullif(v_patch->>'email','') else private.candidate_contacts.email end,
    source_raw_input_id=excluded.source_raw_input_id,
    updated_at=now();

  v_effect_ref:='private.candidate_contacts:'||v_req.candidate_id;
  v_effect_key:='portal_candidate_contact|'||v_cmd.command_key;
  v_finish:=ops.finish_event_success(
    v_run.worker_run_pk,p_lease_token,
    'portal_candidate_contact',v_effect_key,
    'CandidateContact',v_req.candidate_id,v_effect_ref,
    jsonb_build_object('portal_request_id',v_req.request_id,'raw_input_id',v_req.raw_input_id,'candidate_id',v_req.candidate_id),now()
  );

  v_result:=jsonb_build_object(
    'command_pk',p_command_pk,
    'apply_status','APPLIED',
    'duplicate_apply',false,
    'candidate_id',v_req.candidate_id,
    'master_effect_ref',v_effect_ref,
    'event_pk',v_cmd.event_pk,
    'raw_input_id',v_req.raw_input_id
  );
  update ops.domain_commands
    set apply_status='APPLIED',target_entity_type='CandidateContact',target_entity_id=v_req.candidate_id,master_effect_ref=v_effect_ref,applied_at=now(),updated_at=now()
    where command_pk=p_command_pk;
  update ops.domain_command_apply_audit
    set status='APPLIED',target_entity_type='CandidateContact',target_entity_id=v_req.candidate_id,effect_ref=v_effect_ref,result=v_result,error_class=null,error_message=null,finished_at=now(),updated_at=now()
    where command_pk=p_command_pk;
  update ops.portal_action_requests
    set request_status='APPLIED',effect_ref=v_effect_ref,updated_at=now()
    where request_pk=v_req.request_pk;
  return v_result || jsonb_build_object('worker_finish',v_finish);
end $$;

revoke all on function ops.apply_portal_candidate_contact_command(uuid,uuid,text) from public,anon,authenticated;
grant execute on function ops.apply_portal_candidate_contact_command(uuid,uuid,text) to service_role;