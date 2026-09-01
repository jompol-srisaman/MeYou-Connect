create or replace function ops.set_province_lifecycle(p_province_code text,p_new_state text,p_actor text,p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare v_current text;v_ready jsonb;v_allowed boolean:=false;
begin
  if p_new_state not in ('RESEARCH','DEMAND_VALIDATION','PILOT','ACTIVE','PAUSED','CLOSED') then raise exception 'INVALID_PROVINCE_LIFECYCLE_STATE'; end if;
  insert into ops.province_scale_state(province_code,lifecycle_state,status_reason) values(p_province_code,'RESEARCH','Initialized by lifecycle control') on conflict(province_code) do nothing;
  select lifecycle_state into v_current from ops.province_scale_state where province_code=p_province_code for update;

  if p_new_state=v_current then return jsonb_build_object('province_code',p_province_code,'from_state',v_current,'to_state',p_new_state,'changed',false); end if;

  v_allowed :=
    (v_current='RESEARCH' and p_new_state in ('DEMAND_VALIDATION','CLOSED')) or
    (v_current='DEMAND_VALIDATION' and p_new_state in ('RESEARCH','PILOT','PAUSED','CLOSED')) or
    (v_current='PILOT' and p_new_state in ('DEMAND_VALIDATION','ACTIVE','PAUSED','CLOSED')) or
    (v_current='ACTIVE' and p_new_state in ('PAUSED','CLOSED')) or
    (v_current='PAUSED' and p_new_state in ('RESEARCH','PILOT','ACTIVE','CLOSED'));
  if not v_allowed then raise exception 'INVALID_PROVINCE_LIFECYCLE_TRANSITION:%->%',v_current,p_new_state; end if;

  if p_new_state='PILOT' then
    v_ready:=ops.province_scale_readiness(p_province_code);
    if not coalesce((v_ready->>'pilot_prerequisite_ready')::boolean,false) then raise exception 'PILOT_SCALE_GATES_NOT_READY'; end if;
  end if;
  if p_new_state='ACTIVE' then
    v_ready:=ops.province_scale_readiness(p_province_code);
    if not coalesce((v_ready->>'active_transition_ready')::boolean,false) then raise exception 'ACTIVE_SCALE_GATES_NOT_READY'; end if;
  end if;
  update ops.province_scale_state set lifecycle_state=p_new_state,status_reason=p_reason,last_transition_at=now(),updated_at=now() where province_code=p_province_code;
  return jsonb_build_object('province_code',p_province_code,'from_state',v_current,'to_state',p_new_state,'changed',true,'actor',p_actor,'changed_at',now());
end
$function$;
revoke all on function ops.set_province_lifecycle(text,text,text,text) from public,anon,authenticated;
grant execute on function ops.set_province_lifecycle(text,text,text,text) to service_role;