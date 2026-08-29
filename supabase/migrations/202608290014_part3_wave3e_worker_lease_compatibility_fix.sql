create or replace function ops.prepare_domain_command(
  p_event_pk uuid,
  p_worker_key text,
  p_lease_token uuid,
  p_payload jsonb,
  p_target_entity_type text default null,
  p_target_entity_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_event ops.events;
  v_contract ops.domain_worker_contracts;
  v_run ops.worker_runs;
  v_cmd ops.domain_commands;
  v_key text;
  v_duplicate boolean := false;
  v_validation jsonb;
begin
  select * into v_event from ops.events where event_pk=p_event_pk;
  if not found then raise exception 'unknown event_pk: %', p_event_pk; end if;

  select * into v_contract from ops.domain_worker_contracts where worker_key=p_worker_key and active=true;
  if not found then raise exception 'worker % has no active domain contract', p_worker_key; end if;

  if not (v_event.event_type=any(v_contract.allowed_event_types)) then
    raise exception 'event_type % is not allowed for worker %', v_event.event_type, p_worker_key;
  end if;

  select * into v_run
    from ops.worker_runs
   where event_pk=p_event_pk
     and worker_key=p_worker_key
     and lease_token=p_lease_token
     and status='CLAIMED'
     and lease_until>now()
   order by started_at desc
   limit 1;
  if not found then raise exception 'valid active worker lease required'; end if;

  v_key := v_event.idempotency_key || '|command|' || v_contract.command_type;

  select * into v_cmd from ops.domain_commands where command_key=v_key;
  if found then
    v_duplicate := true;
  else
    insert into ops.domain_commands(
      command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,target_entity_id,
      source_raw_input_id,payload,validation_status,apply_status
    ) values (
      v_key,p_event_pk,v_run.worker_run_pk,p_worker_key,v_contract.command_type,
      coalesce(p_target_entity_type,v_contract.target_entity_type),p_target_entity_id,
      v_event.raw_input_id,coalesce(p_payload,'{}'::jsonb),'PENDING','PROPOSED'
    ) returning * into v_cmd;
  end if;

  v_validation := ops.validate_domain_command(v_cmd.command_pk);

  return v_validation || jsonb_build_object(
    'event_pk',v_cmd.event_pk,
    'worker_key',v_cmd.worker_key,
    'command_type',v_cmd.command_type,
    'duplicate_command',v_duplicate,
    'source_raw_input_id',v_cmd.source_raw_input_id
  );
end;
$$;

revoke execute on function ops.prepare_domain_command(uuid,text,uuid,jsonb,text,text) from public,anon,authenticated;
grant execute on function ops.prepare_domain_command(uuid,text,uuid,jsonb,text,text) to service_role;
