create or replace function ops.evaluate_ingress_request(
  p_endpoint_key text,
  p_request_id text,
  p_provider_event_id text,
  p_idempotency_key text,
  p_request_timestamp timestamptz,
  p_payload_bytes integer,
  p_content_type text,
  p_signature_present boolean,
  p_signature_verified boolean,
  p_replay_key_hash text,
  p_client_key_hash text,
  p_sensitive boolean default false,
  p_metadata jsonb default '{}'::jsonb,
  p_now timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_policy ops.ingress_endpoint_policies%rowtype;
  v_existing ops.ingress_request_log%rowtype;
  v_decision text := 'ALLOW';
  v_reason text := 'ACCEPTED';
  v_content_type text;
  v_window_start timestamptz;
  v_rate_count integer := 0;
  v_rows integer := 0;
  v_log_pk uuid;
  v_prod_gate boolean;
  v_external_gate boolean;
  v_test_gate boolean;
  v_metadata jsonb := coalesce(p_metadata,'{}'::jsonb);
begin
  if p_endpoint_key is null or btrim(p_endpoint_key)='' then
    return jsonb_build_object('decision','DENY','reason_code','ENDPOINT_REQUIRED');
  end if;

  select * into v_policy from ops.ingress_endpoint_policies where endpoint_key=p_endpoint_key;
  if not found then
    return jsonb_build_object('decision','DENY','reason_code','UNKNOWN_ENDPOINT','endpoint_key',p_endpoint_key);
  end if;

  if p_request_id is null or btrim(p_request_id)='' then
    return jsonb_build_object('decision','DENY','reason_code','REQUEST_ID_REQUIRED','endpoint_key',p_endpoint_key);
  end if;

  select * into v_existing
  from ops.ingress_request_log
  where endpoint_key=p_endpoint_key and request_id=p_request_id;
  if found then
    return jsonb_build_object(
      'decision',v_existing.decision,
      'reason_code',v_existing.reason_code,
      'request_log_pk',v_existing.ingress_request_pk,
      'existing_request',true,
      'event_pk',v_existing.event_pk,
      'raw_input_id',v_existing.raw_input_id
    );
  end if;

  if jsonb_typeof(v_metadata) <> 'object' then
    v_metadata := '{}'::jsonb;
    v_decision := 'DENY'; v_reason := 'INVALID_METADATA';
  elsif v_metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','authorization','signature'] then
    v_metadata := '{}'::jsonb;
    v_decision := 'DENY'; v_reason := 'SECRET_MATERIAL_NOT_ALLOWED';
  end if;

  if v_decision='ALLOW' and not v_policy.enabled then
    v_decision := 'DENY'; v_reason := 'ENDPOINT_DISABLED';
  end if;

  if v_policy.environment='TEST' then
    select coalesce((select setting_value='true'::jsonb from config.system_settings where setting_key='security_test_ingress_enabled'),false) into v_test_gate;
    if v_decision='ALLOW' and not v_test_gate then v_decision:='DENY'; v_reason:='TEST_INGRESS_DISABLED'; end if;
  else
    select coalesce((select setting_value='true'::jsonb from config.system_settings where setting_key='security_production_gate_enabled'),false) into v_prod_gate;
    select coalesce((select setting_value='true'::jsonb from config.system_settings where setting_key='external_channel_webhooks_enabled'),false) into v_external_gate;
    if v_decision='ALLOW' and (not v_prod_gate or not v_external_gate) then v_decision:='DENY'; v_reason:='PROD_INGRESS_DISABLED'; end if;
  end if;

  if v_decision='ALLOW' and (p_payload_bytes is null or p_payload_bytes < 0) then
    v_decision:='DENY'; v_reason:='INVALID_PAYLOAD_SIZE';
  elsif v_decision='ALLOW' and p_payload_bytes > v_policy.max_payload_bytes then
    v_decision:='DENY'; v_reason:='PAYLOAD_TOO_LARGE';
  end if;

  v_content_type := lower(split_part(coalesce(p_content_type,''),';',1));
  if v_decision='ALLOW' and not exists (
    select 1 from unnest(v_policy.allowed_content_types) a where lower(a)=v_content_type
  ) then
    v_decision:='DENY'; v_reason:='CONTENT_TYPE_NOT_ALLOWED';
  end if;

  if v_decision='ALLOW' and v_policy.signature_required and not coalesce(p_signature_present,false) then
    v_decision:='DENY'; v_reason:='SIGNATURE_REQUIRED';
  elsif v_decision='ALLOW' and v_policy.signature_required and not coalesce(p_signature_verified,false) then
    v_decision:='DENY'; v_reason:='SIGNATURE_INVALID';
  end if;

  if v_decision='ALLOW' and v_policy.timestamp_required and p_request_timestamp is null then
    v_decision:='DENY'; v_reason:='TIMESTAMP_REQUIRED';
  elsif v_decision='ALLOW' and v_policy.timestamp_required and p_request_timestamp < p_now - make_interval(secs=>v_policy.replay_window_seconds) then
    v_decision:='DENY'; v_reason:='REQUEST_STALE';
  elsif v_decision='ALLOW' and v_policy.timestamp_required and p_request_timestamp > p_now + make_interval(secs=>v_policy.max_future_skew_seconds) then
    v_decision:='DENY'; v_reason:='REQUEST_FROM_FUTURE';
  end if;

  if v_decision='ALLOW' and coalesce(p_sensitive,false) and not v_policy.sensitive_allowed then
    v_decision:='QUARANTINE'; v_reason:='SENSITIVE_NOT_ALLOWED';
  end if;

  if v_decision='ALLOW' and v_policy.replay_protection_required and (p_replay_key_hash is null or btrim(p_replay_key_hash)='') then
    v_decision:='DENY'; v_reason:='REPLAY_KEY_REQUIRED';
  end if;

  if v_decision='ALLOW' and (p_client_key_hash is null or btrim(p_client_key_hash)='') then
    v_decision:='DENY'; v_reason:='CLIENT_KEY_REQUIRED';
  end if;

  if v_decision='ALLOW' then
    v_window_start := to_timestamp(floor(extract(epoch from p_now) / v_policy.rate_limit_window_seconds) * v_policy.rate_limit_window_seconds);
    insert into ops.ingress_rate_windows(endpoint_key,client_key_hash,window_started_at,window_seconds,request_count,expires_at)
    values(v_policy.endpoint_key,p_client_key_hash,v_window_start,v_policy.rate_limit_window_seconds,1,v_window_start + make_interval(secs=>v_policy.rate_limit_window_seconds*2))
    on conflict(endpoint_key,client_key_hash,window_started_at) do update
      set request_count=ops.ingress_rate_windows.request_count+1
    returning request_count into v_rate_count;
    if v_rate_count > v_policy.rate_limit_requests then
      v_decision:='DENY'; v_reason:='RATE_LIMITED';
    end if;
  end if;

  if v_decision='ALLOW' and v_policy.replay_protection_required then
    delete from ops.ingress_replay_keys
    where endpoint_key=v_policy.endpoint_key and replay_key_hash=p_replay_key_hash and expires_at <= p_now;

    insert into ops.ingress_replay_keys(endpoint_key,replay_key_hash,request_id,first_seen_at,expires_at)
    values(v_policy.endpoint_key,p_replay_key_hash,p_request_id,p_now,p_now + make_interval(secs=>v_policy.replay_window_seconds))
    on conflict do nothing;
    get diagnostics v_rows = row_count;
    if v_rows=0 then
      v_decision:='DENY'; v_reason:='REPLAY_DETECTED';
    end if;
  end if;

  insert into ops.ingress_request_log(
    endpoint_key,environment,request_id,source_system,provider_event_id,idempotency_key,request_timestamp,received_at,
    payload_bytes,content_type,signature_present,signature_verified,replay_key_hash,client_key_hash,decision,reason_code,metadata)
  values(
    v_policy.endpoint_key,v_policy.environment,p_request_id,v_policy.source_system,p_provider_event_id,p_idempotency_key,p_request_timestamp,p_now,
    coalesce(p_payload_bytes,0),v_content_type,coalesce(p_signature_present,false),coalesce(p_signature_verified,false),p_replay_key_hash,p_client_key_hash,v_decision,v_reason,v_metadata)
  returning ingress_request_pk into v_log_pk;

  return jsonb_build_object(
    'decision',v_decision,
    'reason_code',v_reason,
    'request_log_pk',v_log_pk,
    'existing_request',false,
    'environment',v_policy.environment,
    'endpoint_key',v_policy.endpoint_key,
    'rate_count',v_rate_count
  );
end;
$$;

create or replace function ops.cleanup_ingress_security_state(p_now timestamptz default now())
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_replay int; v_rate int; begin
  delete from ops.ingress_replay_keys where expires_at <= p_now;
  get diagnostics v_replay=row_count;
  delete from ops.ingress_rate_windows where expires_at <= p_now;
  get diagnostics v_rate=row_count;
  return jsonb_build_object('replay_keys_deleted',v_replay,'rate_windows_deleted',v_rate);
end; $$;

revoke all on function ops.evaluate_ingress_request(text,text,text,text,timestamptz,integer,text,boolean,boolean,text,text,boolean,jsonb,timestamptz) from public,anon,authenticated;
revoke all on function ops.cleanup_ingress_security_state(timestamptz) from public,anon,authenticated;
grant execute on function ops.evaluate_ingress_request(text,text,text,text,timestamptz,integer,text,boolean,boolean,text,text,boolean,jsonb,timestamptz) to service_role;
grant execute on function ops.cleanup_ingress_security_state(timestamptz) to service_role;