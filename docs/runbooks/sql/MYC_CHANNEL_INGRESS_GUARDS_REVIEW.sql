-- Additive review candidate for LINE event identity hardening.
-- Apply only inside the isolated, network-disabled restore bootstrap after review.
-- Existing rows are never backfilled, updated or deleted. A legacy map row with
-- a fully verifiable raw/event lineage can be compared read-only; incomplete or
-- unprovable legacy rows fail closed for manual review.

ALTER TABLE ops.channel_event_raw_map
  ADD COLUMN IF NOT EXISTS event_fingerprint text;

CREATE OR REPLACE FUNCTION ops.line_capture_canonical_json(p_value jsonb)
RETURNS jsonb
LANGUAGE plpgsql
IMMUTABLE
SET search_path TO ''
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  CASE pg_catalog.jsonb_typeof(p_value)
    WHEN 'object' THEN
      SELECT coalesce(pg_catalog.jsonb_object_agg(e.key, e.clean_value ORDER BY e.key),
        '{}'::jsonb
      )
      INTO v_result
      FROM (
        SELECT source.key, ops.line_capture_canonical_json(source.value) AS clean_value
        FROM pg_catalog.jsonb_each(p_value) AS source(key, value)
      ) AS e
      WHERE pg_catalog.lower(e.key) NOT IN (
        'replytoken', 'quotetoken', 'accesstoken', 'refreshtoken', 'authorization', 'isredelivery', 'is_redelivery'
      )
        AND NOT (pg_catalog.lower(e.key) = 'deliverycontext' AND e.clean_value = '{}'::jsonb);
      RETURN v_result;
    WHEN 'array' THEN
      SELECT coalesce(
        pg_catalog.jsonb_agg(ops.line_capture_canonical_json(a.value) ORDER BY a.ordinality),
        '[]'::jsonb
      )
      INTO v_result
      FROM pg_catalog.jsonb_array_elements(p_value) WITH ORDINALITY AS a(value, ordinality);
      RETURN v_result;
    ELSE
      RETURN p_value;
  END CASE;
END;
$function$;

CREATE OR REPLACE FUNCTION ops.line_capture_canonical_envelope(p_envelope jsonb)
RETURNS jsonb
LANGUAGE sql
IMMUTABLE
SET search_path TO ''
AS $function$
  SELECT ops.line_capture_canonical_json(
    pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
      'schema_version', p_envelope->'schema_version',
      'source_system', p_envelope->'source_system',
      'channel', p_envelope->'channel',
      'event_id', p_envelope->'event_id',
      'event_type', p_envelope->'event_type',
      'sender_type', p_envelope->'sender_type',
      'content_type', p_envelope->'content_type',
      'original_ref', p_envelope->'original_ref',
      'sender_ref', p_envelope->'sender_ref',
      'source_account_ref', p_envelope->'source_account_ref',
      'thread_id', p_envelope->'thread_id',
      'message_id', p_envelope->'message_id',
      'raw_summary', p_envelope->'raw_summary',
      'ai_parsed', p_envelope->'ai_parsed',
      'sensitive', p_envelope->'sensitive',
      'metadata', pg_catalog.jsonb_build_object(
        'provider', p_envelope#>'{metadata,provider}',
        'account_key', p_envelope#>'{metadata,account_key}',
        'line_event_type', p_envelope#>'{metadata,line_event_type}',
        'source_type', p_envelope#>'{metadata,source_type}',
        'provider_payload', p_envelope#>'{metadata,provider_payload}'
      )
    ))
  );
$function$;

REVOKE ALL ON FUNCTION ops.line_capture_canonical_json(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION ops.line_capture_canonical_json(jsonb) FROM anon, authenticated;
REVOKE ALL ON FUNCTION ops.line_capture_canonical_envelope(jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION ops.line_capture_canonical_envelope(jsonb) FROM anon, authenticated;
DO $grant_capture_owner$
DECLARE
  v_owner name;
BEGIN
  SELECT r.rolname INTO v_owner
  FROM pg_catalog.pg_proc AS p
  JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
  JOIN pg_catalog.pg_roles AS r ON r.oid = p.proowner
  WHERE n.nspname = 'public'
    AND p.proname = 'line_capture_ingest'
    AND pg_catalog.pg_get_function_identity_arguments(p.oid) =
      'p_endpoint_key text, p_request_id text, p_request_timestamp timestamp with time zone, p_payload_bytes integer, p_replay_key_hash text, p_client_key_hash text, p_event_envelope jsonb, p_security_metadata jsonb';
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'LINE_CAPTURE_OWNER_NOT_FOUND';
  END IF;
  EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION ops.line_capture_canonical_json(jsonb) TO %I', v_owner);
  EXECUTE pg_catalog.format('GRANT EXECUTE ON FUNCTION ops.line_capture_canonical_envelope(jsonb) TO %I', v_owner);
END;
$grant_capture_owner$;

CREATE OR REPLACE FUNCTION public.line_capture_ingest(
  p_endpoint_key text,
  p_request_id text,
  p_request_timestamp timestamp with time zone,
  p_payload_bytes integer,
  p_replay_key_hash text,
  p_client_key_hash text,
  p_event_envelope jsonb,
  p_security_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_result jsonb;
  v_complete jsonb;
  v_envelope jsonb := coalesce(p_event_envelope, '{}'::jsonb);
  v_source_account_ref text;
  v_event_id text;
  v_provider_event_id text;
  v_raw_id text;
  v_raw ops.raw_inputs%rowtype;
  v_event ops.events%rowtype;
  v_legacy_envelope jsonb;
  v_payload jsonb;
  v_payload_provider_id text;
  v_account_key text;
  v_existing_fingerprint text;
  v_fingerprint text;
  v_media_recovery_required boolean := false;
  v_alloc jsonb;
BEGIN
  IF p_endpoint_key NOT IN ('line_official_webhook_test', 'line_group_bot_webhook_test') THEN
    RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_ENDPOINT_NOT_ALLOWED');
  END IF;

  v_source_account_ref := v_envelope->>'source_account_ref';
  v_event_id := v_envelope->>'event_id';
  IF (p_endpoint_key = 'line_official_webhook_test' AND v_source_account_ref IS DISTINCT FROM 'LINE_OA:MEYOU_CONNECT_OFFICIAL')
     OR (p_endpoint_key = 'line_group_bot_webhook_test' AND v_source_account_ref IS DISTINCT FROM 'LINE_OA:MYC_DATA_BOT') THEN
    RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_ENDPOINT_ACCOUNT_MISMATCH');
  END IF;
  IF v_event_id IS NULL OR pg_catalog.btrim(v_event_id) = '' THEN
    RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_PROVIDER_EVENT_ID_REQUIRED');
  END IF;
  IF p_endpoint_key = 'line_official_webhook_test' AND v_event_id LIKE 'LINE:OFFICIAL:%' THEN
    v_provider_event_id := v_event_id;
    IF pg_catalog.btrim(pg_catalog.substr(v_event_id, pg_catalog.length('LINE:OFFICIAL:') + 1)) = '' THEN
      RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_PROVIDER_EVENT_ID_REQUIRED');
    END IF;
  ELSIF p_endpoint_key = 'line_group_bot_webhook_test' AND v_event_id LIKE 'LINE:DATA_BOT:%' THEN
    v_provider_event_id := v_event_id;
    IF pg_catalog.btrim(pg_catalog.substr(v_event_id, pg_catalog.length('LINE:DATA_BOT:') + 1)) = '' THEN
      RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_PROVIDER_EVENT_ID_REQUIRED');
    END IF;
  ELSE
    RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_EVENT_ID_SCOPE_MISMATCH');
  END IF;
  v_fingerprint := pg_catalog.encode(
    extensions.digest(
      pg_catalog.convert_to(ops.line_capture_canonical_envelope(v_envelope)::text, 'UTF8'),
      'sha256'
    ),
    'hex'
  );
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('LINE_RAW|' || v_source_account_ref || '|' || v_provider_event_id, 0)
  );

  SELECT m.raw_input_id, m.event_fingerprint
  INTO v_raw_id, v_existing_fingerprint
  FROM ops.channel_event_raw_map AS m
  WHERE m.source_system = 'LINE'
    AND m.source_account_ref = v_source_account_ref
    AND m.provider_event_id = v_provider_event_id;

  IF FOUND THEN
    IF v_existing_fingerprint IS NULL THEN
      SELECT * INTO v_raw
      FROM ops.raw_inputs AS r
      WHERE r.raw_input_id = v_raw_id
        AND r.source_system = 'LINE'
        AND r.source_account_ref = v_source_account_ref;
      IF NOT FOUND OR v_raw.channel IS NULL OR v_raw.sender_type IS NULL OR v_raw.content_type IS NULL
         OR v_raw.original_ref IS NULL OR v_raw.raw_summary IS NULL
         OR pg_catalog.jsonb_typeof(v_raw.metadata->'provider_payload') <> 'object'
         OR v_raw.metadata->>'provider' IS DISTINCT FROM 'LINE' THEN
        RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_EXISTING_FINGERPRINT_REQUIRES_REVIEW');
      END IF;
      v_account_key := CASE v_source_account_ref
        WHEN 'LINE_OA:MEYOU_CONNECT_OFFICIAL' THEN 'OFFICIAL'
        WHEN 'LINE_OA:MYC_DATA_BOT' THEN 'DATA_BOT'
      END;
      IF v_raw.metadata->>'account_key' IS DISTINCT FROM v_account_key THEN
        RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_EXISTING_FINGERPRINT_REQUIRES_REVIEW');
      END IF;
      SELECT * INTO v_event
      FROM ops.events AS e
      WHERE e.raw_input_id = v_raw_id
        AND e.source_system = 'LINE'
        AND e.event_id = v_event_id
        AND e.event_type = 'channel.raw.received';
      IF NOT FOUND THEN
        RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_EXISTING_FINGERPRINT_REQUIRES_REVIEW');
      END IF;
      v_payload := v_raw.metadata->'provider_payload';
      v_payload_provider_id := coalesce(v_payload->>'webhookEventId', v_payload#>>'{message,id}');
      IF v_payload_provider_id IS NULL OR pg_catalog.btrim(v_payload_provider_id) = ''
         OR v_event_id <> 'LINE:' || v_account_key || ':' || v_payload_provider_id
         OR coalesce(v_raw.metadata->>'line_event_type', 'unknown') <> coalesce(v_payload->>'type', 'unknown')
         OR coalesce(v_raw.metadata->>'source_type', 'unknown') <> coalesce(v_payload#>>'{source,type}', 'unknown') THEN
        RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_EXISTING_FINGERPRINT_REQUIRES_REVIEW');
      END IF;
      v_legacy_envelope := pg_catalog.jsonb_build_object(
        'schema_version', v_event.schema_version,
        'source_system', v_event.source_system,
        'channel', v_raw.channel,
        'event_id', v_event.event_id,
        'event_type', v_event.event_type,
        'sender_type', v_raw.sender_type,
        'content_type', v_raw.content_type,
        'original_ref', v_raw.original_ref,
        'sender_ref', v_raw.sender_ref,
        'source_account_ref', v_raw.source_account_ref,
        'thread_id', v_raw.thread_id,
        'message_id', v_raw.message_id,
        'raw_summary', v_raw.raw_summary,
        'ai_parsed', v_raw.ai_parsed,
        'sensitive', v_raw.sensitive,
        'metadata', pg_catalog.jsonb_build_object(
          'provider', v_raw.metadata->'provider',
          'account_key', v_raw.metadata->'account_key',
          'line_event_type', v_raw.metadata->'line_event_type',
          'source_type', v_raw.metadata->'source_type',
          'is_redelivery', v_raw.metadata->'is_redelivery',
          'provider_payload', v_payload
        )
      );
      v_existing_fingerprint := pg_catalog.encode(
        extensions.digest(
          pg_catalog.convert_to(ops.line_capture_canonical_envelope(v_legacy_envelope)::text, 'UTF8'),
          'sha256'
        ),
        'hex'
      );
    END IF;
    IF v_existing_fingerprint <> v_fingerprint THEN
      RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_EVENT_ID_PAYLOAD_CONFLICT');
    END IF;
    IF v_envelope->>'content_type' IN ('LINE_IMAGE', 'LINE_VIDEO', 'LINE_AUDIO', 'LINE_FILE')
       AND nullif(v_envelope->>'message_id', '') IS NOT NULL THEN
      SELECT NOT EXISTS (
        SELECT 1 FROM ops.file_intake AS f
        WHERE f.source_system = 'LINE'
          AND f.source_account_ref = v_source_account_ref
          AND f.provider_file_ref = v_envelope->>'message_id'
          AND f.mirror_status = 'MIRRORED'
          AND f.checksum_sha256 IS NOT NULL
      ) INTO v_media_recovery_required;
    END IF;
    RETURN jsonb_build_object(
      'decision', 'REPLAY_DETECTED',
      'reason_code', 'REPLAY_DETECTED',
      'raw_input_id', v_raw_id,
      'media_recovery_required', v_media_recovery_required
    );
  ELSE
    v_alloc := config.allocate_business_id(
      'Raw Input', 'LINE_CAPTURE',
      jsonb_build_object(
        'source_system', 'LINE',
        'source_account_ref', v_source_account_ref,
        'provider_event_id', v_provider_event_id
      )
    );
    v_raw_id := v_alloc->>'allocated_id';
  END IF;

  v_envelope := v_envelope || jsonb_build_object('raw_input_id', v_raw_id);
  v_result := ops.secure_ingest_material_event(
    p_endpoint_key,
    p_request_id,
    p_request_timestamp,
    p_payload_bytes,
    'application/json',
    true,
    true,
    p_replay_key_hash,
    p_client_key_hash,
    v_envelope,
    coalesce(p_security_metadata, '{}'::jsonb),
    now()
  );

  IF coalesce(v_result->>'decision', 'DENY') = 'ALLOW' AND v_result->>'raw_input_id' IS NOT NULL THEN
    IF v_existing_fingerprint IS NULL THEN
      INSERT INTO ops.channel_event_raw_map(source_system, source_account_ref, provider_event_id, raw_input_id, event_fingerprint)
      VALUES ('LINE', v_source_account_ref, v_provider_event_id, v_result->>'raw_input_id', v_fingerprint)
      ON CONFLICT (source_system, source_account_ref, provider_event_id) DO NOTHING;
      SELECT m.raw_input_id, m.event_fingerprint
      INTO v_raw_id, v_existing_fingerprint
      FROM ops.channel_event_raw_map AS m
      WHERE m.source_system = 'LINE'
        AND m.source_account_ref = v_source_account_ref
        AND m.provider_event_id = v_provider_event_id;
      IF v_existing_fingerprint IS DISTINCT FROM v_fingerprint THEN
        RETURN jsonb_build_object('decision', 'DENY', 'reason_code', 'LINE_EVENT_ID_PAYLOAD_CONFLICT');
      END IF;
    END IF;
  END IF;

  IF coalesce(v_result->>'decision', 'DENY') = 'ALLOW' AND v_result->>'event_pk' IS NOT NULL THEN
    v_complete := ops.complete_raw_capture_event((v_result->>'event_pk')::uuid);
    v_result := v_result || jsonb_build_object('capture_completion', v_complete);
  END IF;
  RETURN v_result || jsonb_build_object('raw_input_id', v_raw_id);
END;
$function$;

CREATE OR REPLACE FUNCTION public.line_capture_register_file(
  p_raw_input_id text,
  p_source_account_ref text,
  p_provider_file_ref text,
  p_original_filename text,
  p_content_type text,
  p_size_bytes bigint,
  p_checksum_sha256 text,
  p_mirror_status text,
  p_sensitive boolean,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_raw ops.raw_inputs%rowtype;
  v_existing ops.file_intake%rowtype;
  v_result jsonb;
  v_mirror_status text;
BEGIN
  IF p_source_account_ref NOT IN ('LINE_OA:MEYOU_CONNECT_OFFICIAL', 'LINE_OA:MYC_DATA_BOT') THEN
    RAISE EXCEPTION 'LINE source account not allowed';
  END IF;
  IF p_mirror_status NOT IN ('SOURCE_ONLY', 'MIRRORED', 'SOURCE_NOT_MIRRORED', 'FAILED') THEN
    RAISE EXCEPTION 'invalid mirror status';
  END IF;
  SELECT * INTO v_raw FROM ops.raw_inputs WHERE raw_input_id = p_raw_input_id;
  IF NOT FOUND OR v_raw.source_system <> 'LINE' OR v_raw.source_account_ref <> p_source_account_ref THEN
    RAISE EXCEPTION 'LINE raw input not found or account mismatch';
  END IF;

  SELECT * INTO v_existing
  FROM ops.file_intake
  WHERE source_system = 'LINE'
    AND coalesce(source_account_ref, '') = coalesce(p_source_account_ref, '')
    AND provider_file_ref = p_provider_file_ref
  ORDER BY created_at
  LIMIT 1;
  IF FOUND THEN
    IF v_existing.checksum_sha256 IS NOT NULL
       AND p_checksum_sha256 IS NOT NULL
       AND v_existing.checksum_sha256 <> p_checksum_sha256 THEN
      RAISE EXCEPTION 'LINE_ATTACHMENT_CHECKSUM_CONFLICT';
    END IF;
    v_mirror_status := CASE
      WHEN v_existing.mirror_status = 'MIRRORED' THEN 'MIRRORED'
      ELSE p_mirror_status
    END;
    UPDATE ops.file_intake
    SET original_filename = coalesce(p_original_filename, original_filename),
        content_type = coalesce(p_content_type, content_type),
        size_bytes = coalesce(p_size_bytes, size_bytes),
        checksum_sha256 = coalesce(v_existing.checksum_sha256, p_checksum_sha256),
        mirror_status = v_mirror_status,
        sensitive = coalesce(p_sensitive, sensitive),
        metadata = metadata || coalesce(p_metadata, '{}'::jsonb),
        updated_at = now()
    WHERE file_intake_pk = v_existing.file_intake_pk;
    v_result := jsonb_build_object(
      'file_intake_pk', v_existing.file_intake_pk,
      'duplicate_file', true,
      'mirror_status', v_mirror_status
    );
  ELSE
    v_result := ops.register_file_intake(
      p_raw_input_id, 'LINE', p_provider_file_ref, p_source_account_ref,
      p_original_filename, p_content_type, p_size_bytes, p_checksum_sha256,
      p_mirror_status, p_sensitive, coalesce(p_metadata, '{}'::jsonb)
    );
  END IF;
  UPDATE ops.raw_inputs
  SET metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object('attachment', coalesce(p_metadata, '{}'::jsonb)),
      updated_at = now()
  WHERE raw_input_id = p_raw_input_id;
  RETURN v_result;
END;
$function$;

-- CREATE OR REPLACE preserves existing function owners and ACLs. New helpers
-- are executable only by the line_capture_ingest owner so its SECURITY DEFINER
-- call works. The capture and registry RPC ACLs are intentionally untouched.
-- Do not replace endpoint grants here; verify and retain the current account policy.



-- Reuse candidate_intake's existing bounded retry/DLQ contract for LINE route failures.
-- The generic scheduler already calls run_line_candidate_ingestion_tick; no new job is added.
CREATE OR REPLACE FUNCTION ops.complete_raw_capture_event(p_event_pk uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_event ops.events%rowtype;
  v_route jsonb;
  v_failure jsonb;
  v_processing_state ops.event_processing_state;
  v_sqlstate text;
begin
  select * into v_event from ops.events where event_pk=p_event_pk for update;
  if not found then return jsonb_build_object('ok',false,'reason','EVENT_NOT_FOUND'); end if;
  if v_event.event_type<>'channel.raw.received' then return jsonb_build_object('ok',false,'reason','NOT_RAW_CAPTURE_EVENT'); end if;
  v_processing_state:=v_event.processing_state;
  IF v_event.processing_state NOT IN (
    'RECEIVED'::ops.event_processing_state,
    'RAW_STORED'::ops.event_processing_state,
    'PARSED'::ops.event_processing_state,
    'VALIDATED'::ops.event_processing_state,
    'ROUTED'::ops.event_processing_state
  ) AND NOT (
    v_event.processing_state='RETRY_WAIT'::ops.event_processing_state
    AND (v_event.next_retry_at IS NULL OR v_event.next_retry_at<=now())
  ) THEN
    RETURN jsonb_build_object('ok',true,'event_pk',p_event_pk,'processing_state',v_processing_state,'reason','STATE_NOT_ELIGIBLE');
  END IF;
  begin
    v_route:=ops.route_line_raw_event_v1(p_event_pk);
    if v_event.processing_state not in ('CANCELLED'::ops.event_processing_state,'DEAD_LETTER'::ops.event_processing_state) then
      update ops.events set processing_state='COMPLETED'::ops.event_processing_state,next_retry_at=null,last_error_class=null,last_error_message=null,updated_at=now() where event_pk=p_event_pk;
      v_processing_state:='COMPLETED'::ops.event_processing_state;
    end if;
    update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)-'line_ingestion_route_error'-'line_ingestion_route_error_at',updated_at=now() where raw_input_id=v_event.raw_input_id;
  exception when others then
    get stacked diagnostics v_sqlstate=returned_sqlstate;
    v_failure:=ops.apply_failure_transition(p_event_pk,'candidate_intake','TRANSIENT','LINE downstream route failed',now());
    v_processing_state:=(v_failure->>'processing_state')::ops.event_processing_state;
    v_route:=jsonb_build_object('routed',false,'reason','DOWNSTREAM_ROUTE_ERROR','error_code',v_sqlstate,'retry_state',v_processing_state);
    update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('line_ingestion_route_error','LINE downstream route failed','line_ingestion_route_error_at',now()),updated_at=now() where raw_input_id=v_event.raw_input_id;
  end;
  return jsonb_build_object('ok',true,'event_pk',p_event_pk,'processing_state',v_processing_state,'downstream_route',v_route);
end;
$function$;

CREATE OR REPLACE FUNCTION ops.run_line_candidate_ingestion_tick(p_now timestamp with time zone DEFAULT now(), p_limit integer DEFAULT 100, p_actor text DEFAULT 'db_scheduler'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  r record;
  v_route jsonb;
  v_parse jsonb;
  v_payload jsonb;
  v_cmd jsonb;
  v_finish jsonb;
  v_candidate jsonb;
  v_routed int:=0;
  v_candidate_events int:=0;
  v_commands int:=0;
  v_reconciled_commands int:=0;
  v_errors int:=0;
begin
  if p_limit<1 or p_limit>200 then raise exception 'limit must be between 1 and 200'; end if;
  perform ops.record_worker_heartbeat('candidate_intake','db_scheduler','test','HEALTHY','line-ingestion-v1.2',jsonb_build_object('actor',p_actor),p_now);

  for r in
    select e.event_pk,e.raw_input_id from ops.events e
    where e.event_type='channel.raw.received' and e.source_system='LINE'
      and not exists(select 1 from ops.event_effects ee where ee.effect_key='line_ingestion_classification|'||e.raw_input_id)
      and (
        e.processing_state in (
          'RECEIVED'::ops.event_processing_state,
          'RAW_STORED'::ops.event_processing_state,
          'PARSED'::ops.event_processing_state,
          'VALIDATED'::ops.event_processing_state,
          'ROUTED'::ops.event_processing_state
        )
        or (e.processing_state='RETRY_WAIT'::ops.event_processing_state and (e.next_retry_at is null or e.next_retry_at<=p_now))
      )
    order by e.received_at,e.created_at limit p_limit
    for update of e skip locked
  loop
    begin
      v_route:=ops.route_line_raw_event_v1(r.event_pk);
      update ops.events set processing_state='COMPLETED'::ops.event_processing_state,next_retry_at=null,last_error_class=null,last_error_message=null,updated_at=p_now where event_pk=r.event_pk and processing_state not in ('CANCELLED'::ops.event_processing_state,'DEAD_LETTER'::ops.event_processing_state);
      update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)-'line_ingestion_route_error'-'line_ingestion_route_error_at',updated_at=now() where raw_input_id=r.raw_input_id;
      v_routed:=v_routed+1;
      if v_route->>'classification'='CANDIDATE_LEAD' then v_candidate_events:=v_candidate_events+1; end if;
    exception when others then
      perform ops.apply_failure_transition(r.event_pk,'candidate_intake','TRANSIENT','LINE downstream route failed',p_now);
      update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('line_ingestion_route_error','LINE downstream route failed','line_ingestion_route_error_at',p_now),updated_at=now() where raw_input_id=r.raw_input_id;
      v_errors:=v_errors+1;
    end;
  end loop;

  for r in select * from ops.claim_events('candidate_intake','db_scheduler',p_limit,120,p_now)
  loop
    begin
      if r.event_id like 'DERIVED:CANDIDATE_RECONCILIATION:%' then
        v_payload:=ops.build_candidate_reconciliation_payload_v1(r.raw_input_id);
        v_cmd:=ops.prepare_domain_command(r.event_pk,'candidate_intake',r.lease_token,v_payload,'Candidate',null);
        v_finish:=ops.finish_event_success(
          r.worker_run_pk,r.lease_token,'candidate_reconciliation_proposal_prepared','candidate_reconciliation_proposal|'||r.raw_input_id,
          'CandidateLead',null,'ops.domain_commands:'||(v_cmd->>'command_pk'),
          jsonb_build_object('raw_input_id',r.raw_input_id,'command_pk',v_cmd->>'command_pk','validation_status',v_cmd->>'validation_status','master_apply_deferred_to','GOOGLE_SHEETS_DRIVE','reconciliation',true),p_now
        );
        update ops.raw_inputs
        set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
          'candidate_command_pk',v_cmd->>'command_pk',
          'candidate_command_validation',v_cmd->>'validation_status',
          'candidate_worker_completed_at',p_now,
          'candidate_reconciliation_command_ready',true
        ),updated_at=now()
        where raw_input_id=r.raw_input_id;
        v_commands:=v_commands+1;
        v_reconciled_commands:=v_reconciled_commands+1;
        continue;
      end if;

      v_parse:=ops.parse_line_candidate_raw_v1(r.raw_input_id);
      if v_parse->>'classification'<>'CANDIDATE_LEAD' then
        perform ops.finish_event_failure(r.worker_run_pk,r.lease_token,'VALIDATION','Derived candidate event no longer parses as candidate',jsonb_build_object('raw_input_id',r.raw_input_id),p_now);
        v_errors:=v_errors+1;
        continue;
      end if;
      v_candidate:=coalesce(v_parse->'candidate','{}'::jsonb)||jsonb_build_object('status','SCREENING');
      if nullif(v_parse->>'partner_id','') is not null then v_candidate:=v_candidate||jsonb_build_object('source_type','Sourcing Partner'); end if;
      v_payload:=jsonb_build_object(
        'candidate',v_candidate,
        'private_contact',jsonb_build_object('full_name',v_parse#>>'{candidate,full_name}','phone',v_parse#>>'{candidate,phone}','date_of_birth',v_parse#>>'{candidate,date_of_birth}'),
        'partner_id',v_parse->>'partner_id','job_id',v_parse->>'job_id','dedupe_rule','NAME_PHONE_DOB','dedupe_key',v_parse->>'dedupe_key',
        'ai_confidence',v_parse->'confidence','missing_fields',v_parse->'missing_fields','parser_version','line_candidate_v1','source_raw_input_id',r.raw_input_id,
        'operational_master_target','GOOGLE_SHEETS_DRIVE','auto_submit',false
      );
      v_cmd:=ops.prepare_domain_command(r.event_pk,'candidate_intake',r.lease_token,v_payload,'Candidate',null);
      v_finish:=ops.finish_event_success(r.worker_run_pk,r.lease_token,'candidate_proposal_prepared','candidate_proposal|'||r.raw_input_id,'CandidateLead',null,'ops.domain_commands:'||(v_cmd->>'command_pk'),jsonb_build_object('raw_input_id',r.raw_input_id,'command_pk',v_cmd->>'command_pk','validation_status',v_cmd->>'validation_status','master_apply_deferred_to','GOOGLE_SHEETS_DRIVE'),p_now);
      update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('candidate_command_pk',v_cmd->>'command_pk','candidate_command_validation',v_cmd->>'validation_status','candidate_worker_completed_at',p_now),updated_at=now() where raw_input_id=r.raw_input_id;
      v_commands:=v_commands+1;
    exception when others then
      begin perform ops.finish_event_failure(r.worker_run_pk,r.lease_token,'VALIDATION',sqlerrm,jsonb_build_object('raw_input_id',r.raw_input_id),p_now); exception when others then null; end;
      v_errors:=v_errors+1;
    end;
  end loop;

  return jsonb_build_object('routed_raw_events',v_routed,'candidate_events_created',v_candidate_events,'candidate_commands_prepared',v_commands,'reconciled_commands_prepared',v_reconciled_commands,'errors',v_errors,'actor',p_actor,'ran_at',p_now);
end;
$function$;
