create or replace function ops.secure_ingest_material_event(
  p_endpoint_key text,
  p_request_id text,
  p_request_timestamp timestamptz,
  p_payload_bytes integer,
  p_transport_content_type text,
  p_signature_present boolean,
  p_signature_verified boolean,
  p_replay_key_hash text,
  p_client_key_hash text,
  p_event_envelope jsonb,
  p_security_metadata jsonb default '{}'::jsonb,
  p_now timestamptz default now()
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_guard jsonb;
  v_ingest jsonb;
  v_policy ops.ingress_endpoint_policies%rowtype;
  v_log_pk uuid;
  v_event_meta jsonb := coalesce(p_event_envelope->'metadata','{}'::jsonb);
  v_sensitive boolean := coalesce((p_event_envelope->>'sensitive')::boolean,false);
begin
  if p_event_envelope is null or jsonb_typeof(p_event_envelope) <> 'object' then
    return jsonb_build_object('decision','DENY','reason_code','EVENT_ENVELOPE_REQUIRED');
  end if;

  select * into v_policy from ops.ingress_endpoint_policies where endpoint_key=p_endpoint_key;
  if not found then
    return jsonb_build_object('decision','DENY','reason_code','UNKNOWN_ENDPOINT','endpoint_key',p_endpoint_key);
  end if;

  v_guard := ops.evaluate_ingress_request(
    p_endpoint_key,
    p_request_id,
    p_event_envelope->>'event_id',
    p_event_envelope->>'idempotency_key',
    p_request_timestamp,
    p_payload_bytes,
    p_transport_content_type,
    p_signature_present,
    p_signature_verified,
    p_replay_key_hash,
    p_client_key_hash,
    v_sensitive,
    p_security_metadata,
    p_now
  );

  if coalesce(v_guard->>'decision','DENY') <> 'ALLOW' then
    return v_guard;
  end if;

  v_log_pk := (v_guard->>'request_log_pk')::uuid;

  if coalesce(p_event_envelope->>'source_system','') <> v_policy.source_system
     or coalesce(p_event_envelope->>'channel','') <> v_policy.channel then
    update ops.ingress_request_log
    set decision='DENY', reason_code='SOURCE_POLICY_MISMATCH'
    where ingress_request_pk=v_log_pk;
    return v_guard || jsonb_build_object('decision','DENY','reason_code','SOURCE_POLICY_MISMATCH');
  end if;

  if v_event_meta ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','authorization','signature'] then
    update ops.ingress_request_log
    set decision='DENY', reason_code='EVENT_METADATA_SECRET_MATERIAL'
    where ingress_request_pk=v_log_pk;
    return v_guard || jsonb_build_object('decision','DENY','reason_code','EVENT_METADATA_SECRET_MATERIAL');
  end if;

  if p_event_envelope->>'raw_input_id' is null
     or p_event_envelope->>'event_id' is null
     or p_event_envelope->>'idempotency_key' is null
     or p_event_envelope->>'trace_id' is null
     or p_event_envelope->>'event_type' is null
     or p_event_envelope->>'original_ref' is null then
    update ops.ingress_request_log
    set decision='DENY', reason_code='EVENT_REQUIRED_FIELD_MISSING'
    where ingress_request_pk=v_log_pk;
    return v_guard || jsonb_build_object('decision','DENY','reason_code','EVENT_REQUIRED_FIELD_MISSING');
  end if;

  v_ingest := ops.ingest_material_event(
    p_event_envelope->>'raw_input_id',
    coalesce(p_event_envelope->>'schema_version','1.0'),
    p_event_envelope->>'source_system',
    p_event_envelope->>'channel',
    p_event_envelope->>'event_id',
    p_event_envelope->>'idempotency_key',
    p_event_envelope->>'trace_id',
    p_event_envelope->>'event_type',
    coalesce((p_event_envelope->>'occurred_at')::timestamptz,p_now),
    coalesce(p_event_envelope->>'sender_type','EXTERNAL'),
    coalesce(p_event_envelope->>'content_type',p_transport_content_type),
    p_event_envelope->>'original_ref',
    p_event_envelope->>'sender_ref',
    p_event_envelope->>'source_account_ref',
    p_event_envelope->>'thread_id',
    p_event_envelope->>'message_id',
    p_event_envelope->>'raw_summary',
    p_event_envelope->>'entity_type_hint',
    p_event_envelope->>'entity_id_if_known',
    coalesce((p_event_envelope->>'ai_parsed')::boolean,false),
    (p_event_envelope->>'ai_confidence')::numeric,
    v_sensitive,
    p_event_envelope->>'consent_signal',
    v_event_meta,
    p_event_envelope->>'correlation_id',
    p_event_envelope->>'causation_event_id'
  );

  update ops.ingress_request_log
  set raw_input_id=v_ingest->>'raw_input_id',
      event_pk=(v_ingest->>'event_pk')::uuid
  where ingress_request_pk=v_log_pk;

  return v_guard || jsonb_build_object(
    'ingested',true,
    'raw_input_id',v_ingest->>'raw_input_id',
    'event_pk',v_ingest->>'event_pk',
    'event_id',v_ingest->>'event_id',
    'processing_state',v_ingest->>'processing_state',
    'duplicate_event',coalesce((v_ingest->>'duplicate_event')::boolean,false),
    'route_key',v_ingest->>'route_key'
  );
end;
$$;

revoke all on function ops.secure_ingest_material_event(text,text,timestamptz,integer,text,boolean,boolean,text,text,jsonb,jsonb,timestamptz) from public,anon,authenticated;
grant execute on function ops.secure_ingest_material_event(text,text,timestamptz,integer,text,boolean,boolean,text,text,jsonb,jsonb,timestamptz) to service_role;