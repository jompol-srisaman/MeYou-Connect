#!/usr/bin/env node
// Isolated-only SQL integration for the LINE ingress guard candidate.
// No connection strings or remote Docker contexts are accepted. The first suite
// rolls back all writes. The two-session suite commits only reviewed DDL and a
// unique synthetic fixture, then deletes the fixture and verifies protected
// table fingerprints, counts and existing function owners/ACLs.

import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { spawn, spawnSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const TARGET = process.env.MYC_TEST_CONTAINER ?? 'myc-restore-20261016-bootstrap';
const guardSql = readFileSync(resolve(root, 'docs/runbooks/sql/MYC_CHANNEL_INGRESS_GUARDS_REVIEW.sql'), 'utf8');
const runtimeDefinitions = JSON.parse(readFileSync(resolve(root, 'tests/fixtures/myc-line-runtime-functions.json'), 'utf8'));
const runtimeSql = runtimeDefinitions
  .filter(f => ['secure_ingest_material_event', 'ingest_material_event', 'register_event', 'route_line_raw_event_v1', 'parse_line_candidate_raw_base_v1', 'parse_line_candidate_raw_v1', 'run_line_candidate_ingestion_tick', 'scheduler_tick', 'apply_failure_transition'].includes(f.name))
  .map(f => `${f.definition.trim().replace(/;?$/, ';')}`)
  .join('\n\n');
const literal = value => `'${String(value).replaceAll("'", "''")}'`;
const psqlArgs = ['exec', '-i', TARGET, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'supabase_admin', '-d', 'postgres', '-h', '/tmp'];

function run(command, args, { input, timeout = 30000 } = {}) {
  const result = spawnSync(command, args, {
    input,
    encoding: 'utf8',
    timeout,
    windowsHide: true,
    shell: false,
    maxBuffer: 1024 * 1024,
  });
  if (result.error) throw new Error(`${command} could not run: ${result.error.message}`);
  if (result.status !== 0) {
    const detail = String(result.stderr ?? '').trim().split(/\r?\n/).slice(-6).join(' ').slice(0, 1200);
    throw new Error(`${command} exited ${result.status}${detail ? `: ${detail}` : ''}`);
  }
  return String(result.stdout ?? '').trim();
}

function startPsql(input) {
  const child = spawn('docker', psqlArgs, { windowsHide: true, shell: false, stdio: ['pipe', 'pipe', 'pipe'] });
  let stdout = '';
  let stderr = '';
  let firstResolve;
  let firstReject;
  const firstLine = new Promise((resolve, reject) => { firstResolve = resolve; firstReject = reject; });
  child.stdout.setEncoding('utf8');
  child.stderr.setEncoding('utf8');
  child.stdout.on('data', chunk => {
    stdout += chunk;
    for (const line of stdout.split(/\r?\n/)) {
      if (!line || line.startsWith('NOTICE:') || line.startsWith('WARNING:')) continue;
      try { firstResolve(JSON.parse(line)); return; } catch {}
    }
  });
  child.stderr.on('data', chunk => { stderr += chunk; });
  const done = new Promise((resolve, reject) => child.on('close', code => code === 0 ? resolve(stdout) : reject(new Error(`concurrent psql failed: ${stderr.slice(-800)}`))));
  child.stdin.end(input);
  return { firstLine, done, kill: () => child.kill() };
}

const delay = ms => new Promise(resolve => setTimeout(resolve, ms));
function psql(input, timeout = 90000) {
  return run('docker', psqlArgs, { input, timeout });
}
function readJson(sql) {
  const lines = psql(`${sql}\n`).split(/\r?\n/).filter(Boolean);
  return JSON.parse(lines.at(-1));
}

function assertLocalIsolatedContainer() {
  assert.match(TARGET, /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/, 'MYC_TEST_CONTAINER must be a Docker container name, never a host or URL');
  const context = run('docker', ['context', 'show']);
  const endpoint = run('docker', ['context', 'inspect', context, '--format', '{{.Endpoints.docker.Host}}']);
  assert.match(endpoint, /^(npipe:|unix:|tcp:\/\/(127\.0\.0\.1|localhost)(:|\/|$))/, 'Docker context must be local');
  const inspected = run('docker', ['inspect', '--format', '{{.Name}}|{{.HostConfig.NetworkMode}}|{{json .NetworkSettings.Ports}}', TARGET]);
  const [name, networkMode, ports] = inspected.split('|');
  assert.equal(name, `/${TARGET}`, 'the inspected container must match the explicitly selected target');
  assert.equal(networkMode, 'none', 'restore container must have network mode none');
  assert.ok(ports === 'null' || ports === '{}', 'restore container must not publish ports');
}

test('LINE ingress SQL pairs accounts and rejects changed payloads without external effects', () => {
  assertLocalIsolatedContainer();
  const body = `
BEGIN READ WRITE;
CREATE TEMP TABLE _line_ingress_acl_before ON COMMIT DROP AS
SELECT n.nspname AS schema_name, p.proname, p.proowner, p.proacl
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid=p.pronamespace
WHERE (n.nspname='public' AND p.proname IN ('line_capture_ingest','line_capture_register_file'))
   OR (n.nspname='ops' AND p.proname IN ('complete_raw_capture_event','run_line_candidate_ingestion_tick'));
${runtimeSql}
${guardSql}
GRANT EXECUTE ON FUNCTION ops.line_capture_canonical_json(jsonb) TO supabase_admin;
GRANT EXECUTE ON FUNCTION ops.line_capture_canonical_envelope(jsonb) TO supabase_admin;
DO $channel_test$
DECLARE
  v_result jsonb;
  v_alloc jsonb;
  v_raw_id text;
  v_event_id text := 'LINE:OFFICIAL:fixture-ingress-conflict';
  v_envelope jsonb;
  v_changed jsonb;
  v_fingerprint text;
  v_a jsonb;
  v_b jsonb;
  v_raw ops.raw_inputs%rowtype;
  v_event ops.events%rowtype;
  v_source_account_ref text;
  v_real_event_id text;
  v_real_envelope jsonb;
  v_before_raw bigint;
  v_before_events bigint;
  v_before_map bigint;
  v_before_files bigint;
  v_registry jsonb;
  v_file_intake_pk uuid;
  v_file_count bigint;
  v_pipeline_result jsonb;
  v_tick_result jsonb;
  v_pipeline_raw_id text;
  v_pipeline_event_pk uuid;
  v_pipeline_event_id text := 'LINE:OFFICIAL:fixture-full-pipeline';
  v_pipeline_child_count bigint;
  v_pipeline_effect_count bigint;
  v_candidate_command_count bigint;
  v_finance_command_count bigint;
  v_apply_audit_count bigint;
  v_failure_raw_id text;
  v_failure_result jsonb;
  v_failure_event_id text := 'LINE:OFFICIAL:fixture-route-retry';
  v_failure_event_pk uuid;
  v_failure_state text;
  v_failure_attempt integer;
  v_failure_dead_letter_count bigint;
  v_held_state text;
  v_held_result jsonb;
  v_held_metadata jsonb;
  v_held_child_count bigint;
  v_held_command_count bigint;
BEGIN
  IF EXISTS (
    SELECT 1 FROM _line_ingress_acl_before b
    JOIN pg_catalog.pg_proc p ON p.proname=b.proname
    JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname=b.schema_name AND (p.proacl IS DISTINCT FROM b.proacl OR p.proowner IS DISTINCT FROM b.proowner)
  ) THEN
    RAISE EXCEPTION 'EXISTING_LINE_FUNCTION_OWNER_OR_ACL_CHANGED';
  END IF;
  IF has_function_privilege('anon', 'public.line_capture_ingest(text,text,timestamptz,integer,text,text,jsonb,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.line_capture_ingest(text,text,timestamptz,integer,text,text,jsonb,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.line_capture_ingest(text,text,timestamptz,integer,text,text,jsonb,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'public.line_capture_register_file(text,text,text,text,text,bigint,text,text,boolean,jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.line_capture_register_file(text,text,text,text,text,bigint,text,text,boolean,jsonb)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.line_capture_register_file(text,text,text,text,text,bigint,text,text,boolean,jsonb)', 'EXECUTE')
     OR has_function_privilege('anon', 'ops.line_capture_canonical_envelope(jsonb)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'ops.line_capture_canonical_envelope(jsonb)', 'EXECUTE')
     OR has_function_privilege('service_role', 'ops.line_capture_canonical_envelope(jsonb)', 'EXECUTE') THEN
    RAISE EXCEPTION 'LINE_RPC_ACL_BOUNDARY_FAILED';
  END IF;

  v_a := '{"z":1,"replyToken":"synthetic-a","deliveryContext":{"isRedelivery":false},"list":[2,1]}'::jsonb;
  v_b := '{"list":[2,1],"replyToken":"synthetic-b","z":1}'::jsonb;
  IF ops.line_capture_canonical_json(v_a) IS DISTINCT FROM ops.line_capture_canonical_json(v_b) THEN
    RAISE EXCEPTION 'CANONICAL_RETRY_NORMALIZATION_FAILED';
  END IF;

  v_result := public.line_capture_ingest(
    'line_official_webhook_test', 'fixture-pairing', now(), 1, repeat('a',64), repeat('b',64),
    '{"event_id":"LINE:OFFICIAL:fixture-pairing","source_account_ref":"LINE_OA:MYC_DATA_BOT"}'::jsonb, '{}'::jsonb
  );
  IF v_result->>'reason_code' <> 'LINE_ENDPOINT_ACCOUNT_MISMATCH' THEN
    RAISE EXCEPTION 'ENDPOINT_ACCOUNT_PAIRING_FAILED:%', v_result->>'reason_code';
  END IF;

  v_result := public.line_capture_ingest(
    'line_official_webhook_test', 'fixture-prefix', now(), 1, repeat('a',64), repeat('b',64),
    '{"event_id":"LINE:DATA_BOT:fixture-prefix","source_account_ref":"LINE_OA:MEYOU_CONNECT_OFFICIAL"}'::jsonb, '{}'::jsonb
  );
  IF v_result->>'reason_code' <> 'LINE_EVENT_ID_SCOPE_MISMATCH' THEN
    RAISE EXCEPTION 'EVENT_PREFIX_PAIRING_FAILED:%', v_result->>'reason_code';
  END IF;

  v_alloc := config.allocate_business_id('Raw Input', 'LINE_CAPTURE_TEST', jsonb_build_object('fixture', true));
  v_raw_id := v_alloc->>'allocated_id';
  INSERT INTO ops.raw_inputs(raw_input_id) VALUES (v_raw_id);
  v_envelope := jsonb_build_object(
    'event_id', v_event_id,
    'source_account_ref', 'LINE_OA:MEYOU_CONNECT_OFFICIAL',
    'metadata', jsonb_build_object('fixture_value', 'original')
  );
  v_fingerprint := pg_catalog.encode(extensions.digest(
    pg_catalog.convert_to(ops.line_capture_canonical_json(v_envelope)::text, 'UTF8'), 'sha256'), 'hex');
  INSERT INTO ops.channel_event_raw_map(source_system, source_account_ref, provider_event_id, raw_input_id, event_fingerprint)
  VALUES ('LINE', 'LINE_OA:MEYOU_CONNECT_OFFICIAL', v_event_id, v_raw_id, v_fingerprint);

  v_changed := pg_catalog.jsonb_set(v_envelope, '{metadata,fixture_value}', '"altered"'::jsonb);
  v_result := public.line_capture_ingest(
    'line_official_webhook_test', 'fixture-conflict', now(), 1, repeat('a',64), repeat('b',64), v_changed, '{}'::jsonb
  );
  IF v_result->>'reason_code' <> 'LINE_EVENT_ID_PAYLOAD_CONFLICT' THEN
    RAISE EXCEPTION 'CHANGED_PAYLOAD_NOT_REJECTED:%', v_result->>'reason_code';
  END IF;

  SELECT m.source_account_ref, m.provider_event_id
  INTO v_source_account_ref, v_real_event_id
  FROM ops.channel_event_raw_map AS m
  JOIN ops.raw_inputs AS r USING (raw_input_id)
  WHERE m.source_system='LINE'
    AND r.source_system='LINE'
    AND r.source_account_ref=m.source_account_ref
    AND r.channel='LINE'
    AND r.sender_type IS NOT NULL
    AND r.content_type IS NOT NULL
    AND r.original_ref IS NOT NULL
    AND r.raw_summary IS NOT NULL
    AND pg_catalog.jsonb_typeof(r.metadata->'provider_payload')='object'
    AND r.metadata->>'provider'='LINE'
    AND r.metadata->>'account_key'=CASE WHEN m.source_account_ref='LINE_OA:MEYOU_CONNECT_OFFICIAL' THEN 'OFFICIAL' ELSE 'DATA_BOT' END
    AND m.provider_event_id='LINE:' || (r.metadata->>'account_key') || ':' || coalesce(r.metadata#>>'{provider_payload,webhookEventId}',r.metadata#>>'{provider_payload,message,id}')
    AND r.content_type NOT IN ('LINE_IMAGE','LINE_VIDEO','LINE_AUDIO','LINE_FILE')
  ORDER BY m.created_at
  LIMIT 1;
  IF v_real_event_id IS NULL THEN RAISE EXCEPTION 'NO_VERIFIABLE_LEGACY_SAMPLE'; END IF;
  SELECT * INTO v_raw FROM ops.raw_inputs WHERE source_system='LINE' AND source_account_ref=v_source_account_ref
    AND raw_input_id=(SELECT raw_input_id FROM ops.channel_event_raw_map WHERE source_system='LINE' AND source_account_ref=v_source_account_ref AND provider_event_id=v_real_event_id);
  SELECT * INTO v_event FROM ops.events WHERE source_system='LINE' AND event_id=v_real_event_id AND raw_input_id=v_raw.raw_input_id AND event_type='channel.raw.received';
  IF NOT FOUND THEN RAISE EXCEPTION 'LEGACY_EVENT_LINEAGE_UNVERIFIABLE'; END IF;
  v_real_envelope := pg_catalog.jsonb_build_object(
    'schema_version',v_event.schema_version,'source_system',v_event.source_system,'channel',v_raw.channel,
    'event_id',v_event.event_id,'idempotency_key',v_event.idempotency_key,'trace_id',v_event.trace_id,
    'event_type',v_event.event_type,'occurred_at',v_event.occurred_at,'sender_type',v_raw.sender_type,
    'content_type',v_raw.content_type,'original_ref',v_raw.original_ref,'sender_ref',v_raw.sender_ref,
    'source_account_ref',v_raw.source_account_ref,'thread_id',v_raw.thread_id,'message_id',v_raw.message_id,
    'raw_summary',v_raw.raw_summary,'ai_parsed',v_raw.ai_parsed,'sensitive',v_raw.sensitive,
    'metadata',pg_catalog.jsonb_build_object(
      'provider',v_raw.metadata->'provider','account_key',v_raw.metadata->'account_key',
      'line_event_type',v_raw.metadata->'line_event_type','source_type',v_raw.metadata->'source_type',
      'is_redelivery',false,'provider_payload',v_raw.metadata->'provider_payload'
    )
  );
  SELECT count(*) INTO v_before_raw FROM ops.raw_inputs;
  SELECT count(*) INTO v_before_events FROM ops.events;
  SELECT count(*) INTO v_before_map FROM ops.channel_event_raw_map;
  SELECT count(*) INTO v_before_files FROM ops.file_intake;
  v_result := public.line_capture_ingest(
    CASE WHEN v_source_account_ref='LINE_OA:MEYOU_CONNECT_OFFICIAL' THEN 'line_official_webhook_test' ELSE 'line_group_bot_webhook_test' END,
    'clone-readonly-legacy-replay',now(),1,repeat('a',64),repeat('b',64),v_real_envelope,'{}'::jsonb
  );
  IF v_result->>'decision' <> 'REPLAY_DETECTED' OR v_result->>'raw_input_id' <> v_raw.raw_input_id
     OR v_result->>'media_recovery_required' <> 'false' THEN
    RAISE EXCEPTION 'VERIFIABLE_LEGACY_REPLAY_FAILED:%', v_result;
  END IF;
  IF (SELECT count(*) FROM ops.raw_inputs) <> v_before_raw
     OR (SELECT count(*) FROM ops.events) <> v_before_events
     OR (SELECT count(*) FROM ops.channel_event_raw_map) <> v_before_map
     OR (SELECT count(*) FROM ops.file_intake) <> v_before_files THEN
    RAISE EXCEPTION 'LEGACY_REPLAY_MUTATED_CAPTURE_OR_MASTER_EVIDENCE';
  END IF;

  v_alloc := config.allocate_business_id('Raw Input','LINE_CAPTURE_TEST',jsonb_build_object('fixture',true));
  v_raw_id := v_alloc->>'allocated_id';
  INSERT INTO ops.raw_inputs(raw_input_id,source_system,source_account_ref,channel,original_ref,classification,processing_status)
  VALUES(v_raw_id,'LINE','LINE_OA:MEYOU_CONNECT_OFFICIAL','LINE','line://fixture/file','channel.raw.received','RAW_STORED');
  v_registry := public.line_capture_register_file(v_raw_id,'LINE_OA:MEYOU_CONNECT_OFFICIAL','fixture-file-ref','fixture.bin','application/octet-stream',4,repeat('c',64),'MIRRORED',true,'{"fixture":true}'::jsonb);
  IF v_registry->>'mirror_status' <> 'MIRRORED' THEN RAISE EXCEPTION 'INITIAL_MEDIA_REGISTRY_FAILED'; END IF;
  BEGIN
    PERFORM public.line_capture_register_file(v_raw_id,'LINE_OA:MEYOU_CONNECT_OFFICIAL','fixture-file-ref','fixture.bin','application/octet-stream',4,repeat('d',64),'SOURCE_NOT_MIRRORED',true,'{}'::jsonb);
    RAISE EXCEPTION 'HARNESS_EXPECTED_CHECKSUM_CONFLICT_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'LINE_ATTACHMENT_CHECKSUM_CONFLICT' THEN RAISE; END IF;
  END;
  v_registry := public.line_capture_register_file(v_raw_id,'LINE_OA:MEYOU_CONNECT_OFFICIAL','fixture-file-ref',NULL,NULL,NULL,NULL,'SOURCE_NOT_MIRRORED',true,'{"retry":true}'::jsonb);
  IF v_registry->>'mirror_status' <> 'MIRRORED' THEN RAISE EXCEPTION 'MIRRORED_STATUS_DOWNGRADED'; END IF;
  SELECT count(*),(array_agg(file_intake_pk))[1] INTO v_file_count,v_file_intake_pk FROM ops.file_intake WHERE source_system='LINE' AND source_account_ref='LINE_OA:MEYOU_CONNECT_OFFICIAL' AND provider_file_ref='fixture-file-ref';
  IF v_file_count <> 1 OR NOT EXISTS (SELECT 1 FROM ops.file_intake WHERE file_intake_pk=v_file_intake_pk AND checksum_sha256=repeat('c',64) AND mirror_status='MIRRORED') THEN
    RAISE EXCEPTION 'MEDIA_REGISTRY_IMMUTABILITY_FAILED';
  END IF;

  -- Exercise the real capture -> secure ingest -> route -> derived child -> proposal path.
  v_envelope := jsonb_build_object(
    'schema_version','2.1','source_system','LINE','channel','LINE',
    'event_id',v_pipeline_event_id,'idempotency_key','fixture-full-pipeline-idem',
    'trace_id','fixture-full-pipeline-trace','event_type','channel.raw.received',
    'occurred_at',now(),'sender_type','LINE_USER','content_type','LINE_TEXT',
    'original_ref','line://OFFICIAL/fixture/full-pipeline','sender_ref','LINE_USER_ID_FIXTURE_01',
    'source_account_ref','LINE_OA:MEYOU_CONNECT_OFFICIAL','thread_id','fixture-thread',
    'message_id','fixture-full-pipeline-message',
    'raw_summary',E'ทดสอบ ตัวอย่าง\nเบอร์โทร: 0000000000\nวันเดือนปีเกิด: 01/01/2000\nวุฒิ: ม.6\nสมัครงาน Next Can',
    'ai_parsed',false,'sensitive',true,
    'metadata',jsonb_build_object(
      'provider','LINE','account_key','OFFICIAL','line_event_type','message','source_type','user','is_redelivery',false,
      'provider_payload',jsonb_build_object(
        'type','message','webhookEventId','fixture-full-pipeline','timestamp',extract(epoch from now())::bigint*1000,
        'source',jsonb_build_object('type','user','userId','LINE_USER_ID_FIXTURE_01'),
        'message',jsonb_build_object('id','fixture-full-pipeline-message','type','text','text','synthetic integration fixture')
      )
    )
  );
  v_pipeline_result := public.line_capture_ingest(
    'line_official_webhook_test','fixture-full-pipeline',now(),512,repeat('a',64),repeat('b',64),v_envelope,'{}'::jsonb
  );
  IF v_pipeline_result->>'decision' <> 'ALLOW'
     OR v_pipeline_result#>>'{capture_completion,downstream_route,classification}' <> 'CANDIDATE_LEAD' THEN
    RAISE EXCEPTION 'REAL_LINE_CAPTURE_PIPELINE_FAILED';
  END IF;
  v_pipeline_raw_id := v_pipeline_result->>'raw_input_id';
  v_pipeline_event_pk := (v_pipeline_result->>'event_pk')::uuid;
  SELECT count(*) INTO v_pipeline_child_count FROM ops.events
  WHERE raw_input_id=v_pipeline_raw_id AND event_type='candidate.lead.received'
    AND event_id='DERIVED:CANDIDATE_LEAD:'||v_pipeline_raw_id;
  SELECT count(*) INTO v_pipeline_effect_count FROM ops.event_effects
  WHERE event_pk=v_pipeline_event_pk AND effect_key='line_ingestion_classification|'||v_pipeline_raw_id;
  IF v_pipeline_child_count <> 1 OR v_pipeline_effect_count <> 1 THEN
    RAISE EXCEPTION 'LINE_CLASSIFICATION_CHILD_NOT_IDEMPOTENT';
  END IF;
  UPDATE ops.events SET received_at='0001-01-01 00:00:00+00'
  WHERE raw_input_id=v_pipeline_raw_id AND event_id='DERIVED:CANDIDATE_LEAD:'||v_pipeline_raw_id;
  v_tick_result := ops.run_line_candidate_ingestion_tick(now()+interval '1 day',1,'channel-ingress-integration');
  SELECT count(*) INTO v_candidate_command_count FROM ops.domain_commands
  WHERE source_raw_input_id=v_pipeline_raw_id AND target_entity_type='Candidate';
  SELECT count(*) INTO v_finance_command_count FROM ops.domain_commands
  WHERE source_raw_input_id=v_pipeline_raw_id AND target_entity_type='Finance';
  SELECT count(*) INTO v_apply_audit_count FROM ops.domain_command_apply_audit a
  JOIN ops.domain_commands c USING (command_pk) WHERE c.source_raw_input_id=v_pipeline_raw_id;
  IF v_candidate_command_count <> 1 OR v_finance_command_count <> 0 OR v_apply_audit_count <> 0 THEN
    RAISE EXCEPTION 'LINE_CANDIDATE_PROPOSAL_OR_MASTER_BOUNDARY_FAILED';
  END IF;
  PERFORM ops.run_line_candidate_ingestion_tick(now()+interval '2 days',1,'channel-ingress-integration-replay');
  IF (SELECT count(*) FROM ops.domain_commands WHERE source_raw_input_id=v_pipeline_raw_id AND target_entity_type='Candidate') <> 1
     OR (SELECT count(*) FROM ops.domain_commands WHERE source_raw_input_id=v_pipeline_raw_id AND target_entity_type='Finance') <> 0 THEN
    RAISE EXCEPTION 'LINE_CANDIDATE_REPLAY_CREATED_DUPLICATE';
  END IF;

  -- Held and terminal states must not route, create effects, or prepare commands.
  DELETE FROM ops.event_effects WHERE event_pk=v_pipeline_event_pk AND effect_key='line_ingestion_classification|'||v_pipeline_raw_id;
  SELECT metadata INTO v_held_metadata FROM ops.raw_inputs WHERE raw_input_id=v_pipeline_raw_id;
  SELECT count(*) INTO v_held_child_count FROM ops.events WHERE raw_input_id=v_pipeline_raw_id AND event_type='candidate.lead.received';
  SELECT count(*) INTO v_held_command_count FROM ops.domain_commands WHERE source_raw_input_id=v_pipeline_raw_id;
  FOREACH v_held_state IN ARRAY ARRAY['NEEDS_REVIEW','DQ_HOLD','REJECTED','APPROVAL_REQUIRED','COMPLETED','CANCELLED','DEAD_LETTER'] LOOP
    UPDATE ops.events SET processing_state=v_held_state::ops.event_processing_state WHERE event_pk=v_pipeline_event_pk;
    v_held_result:=ops.complete_raw_capture_event(v_pipeline_event_pk);
    IF v_held_result->>'reason'<>'STATE_NOT_ELIGIBLE' OR v_held_result->>'processing_state'<>v_held_state THEN
      RAISE EXCEPTION 'HELD_LINE_EVENT_CAPTURE_COMPLETION_NOT_NOOP:%',v_held_state;
    END IF;
    PERFORM ops.run_line_candidate_ingestion_tick(now()+interval '10 days',1,'channel-ingress-held-state-test');
    IF EXISTS(SELECT 1 FROM ops.event_effects WHERE event_pk=v_pipeline_event_pk AND effect_key='line_ingestion_classification|'||v_pipeline_raw_id)
       OR (SELECT metadata FROM ops.raw_inputs WHERE raw_input_id=v_pipeline_raw_id) IS DISTINCT FROM v_held_metadata
       OR (SELECT count(*) FROM ops.events WHERE raw_input_id=v_pipeline_raw_id AND event_type='candidate.lead.received')<>v_held_child_count
       OR (SELECT count(*) FROM ops.domain_commands WHERE source_raw_input_id=v_pipeline_raw_id)<>v_held_command_count
       OR (SELECT processing_state::text FROM ops.events WHERE event_pk=v_pipeline_event_pk)<>v_held_state THEN
      RAISE EXCEPTION 'HELD_LINE_EVENT_CREATED_SIDE_EFFECT:%',v_held_state;
    END IF;
  END LOOP;

  -- A controlled route exception proves the existing worker retry/DLQ policy is bounded.
  EXECUTE $install_route_failure$
    CREATE OR REPLACE FUNCTION ops.route_line_raw_event_v1(p_event_pk uuid)
    RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
    AS $route_failure_fixture$
    BEGIN
      RAISE EXCEPTION USING ERRCODE='P0001', MESSAGE='synthetic route failure';
    END;
    $route_failure_fixture$
  $install_route_failure$;
  v_envelope := jsonb_set(v_envelope,'{event_id}',to_jsonb(v_failure_event_id),true);
  v_envelope := jsonb_set(v_envelope,'{idempotency_key}',to_jsonb('fixture-route-retry-idem'::text),true);
  v_envelope := jsonb_set(v_envelope,'{trace_id}',to_jsonb('fixture-route-retry-trace'::text),true);
  v_envelope := jsonb_set(v_envelope,'{original_ref}',to_jsonb('line://OFFICIAL/fixture/route-retry'::text),true);
  v_envelope := jsonb_set(v_envelope,'{raw_summary}',to_jsonb('synthetic route failure fixture'::text),true);
  v_envelope := jsonb_set(v_envelope,'{metadata,provider_payload,webhookEventId}',to_jsonb('fixture-route-retry'::text),true);
  v_failure_result := public.line_capture_ingest(
    'line_official_webhook_test','fixture-route-retry',now(),128,repeat('c',64),repeat('d',64),v_envelope,'{}'::jsonb
  );
  IF v_failure_result->>'decision' <> 'ALLOW'
     OR v_failure_result#>>'{capture_completion,processing_state}' <> 'RETRY_WAIT' THEN
    RAISE EXCEPTION 'LINE_ROUTE_FAILURE_DID_NOT_ENTER_RETRY_WAIT';
  END IF;
  v_failure_raw_id := v_failure_result->>'raw_input_id';
  v_failure_event_pk := (v_failure_result->>'event_pk')::uuid;
  UPDATE ops.events SET received_at='0001-01-01 00:00:00+00' WHERE event_pk=v_failure_event_pk;
  PERFORM ops.run_line_candidate_ingestion_tick(now()+interval '1 day',1,'channel-ingress-retry-1');
  PERFORM ops.run_line_candidate_ingestion_tick(now()+interval '2 days',1,'channel-ingress-retry-2');
  PERFORM ops.run_line_candidate_ingestion_tick(now()+interval '3 days',1,'channel-ingress-retry-3');
  SELECT processing_state::text,processing_attempt INTO v_failure_state,v_failure_attempt
  FROM ops.events WHERE event_pk=v_failure_event_pk;
  SELECT count(*) INTO v_failure_dead_letter_count FROM ops.dead_letters WHERE event_pk=v_failure_event_pk;
  IF v_failure_state <> 'DEAD_LETTER' OR v_failure_attempt <> 4 OR v_failure_dead_letter_count <> 1 THEN
    RAISE EXCEPTION 'LINE_ROUTE_FAILURE_DID_NOT_REACH_BOUNDED_DLQ';
  END IF;
  PERFORM ops.run_line_candidate_ingestion_tick(now()+interval '4 days',1,'channel-ingress-after-dlq');
  IF (SELECT processing_attempt FROM ops.events WHERE event_pk=v_failure_event_pk) <> 4 THEN
    RAISE EXCEPTION 'LINE_DEAD_LETTER_WAS_RETRIED';
  END IF;
END
$channel_test$;
ROLLBACK;
SELECT 'CHANNEL_INGRESS_GUARDS:ROLLED_BACK';
`;
  const output = psql(body, 60000);
  assert.match(output, /CHANNEL_INGRESS_GUARDS:ROLLED_BACK/);
});

test('LINE event-first locking serializes completion and candidate routing across two sessions', async () => {
  assertLocalIsolatedContainer();
  const runId = randomUUID().replaceAll('-', '').toUpperCase();
  const rawId = `MYC-RAW-${String((Number.parseInt(runId.slice(-6), 16) % 900000) + 100000).padStart(6, '0')}`;
  const eventId = `LINE:OFFICIAL:fixture-lock-order-${runId}`;
  const endpointKey = `line_race_pause_${runId.toLowerCase()}`;
  const triggerName = `line_race_pause_${runId.toLowerCase()}`;
  const triggerFunction = `line_race_pause_${runId.toLowerCase()}`;
  const heartbeatBefore = readJson("SELECT coalesce((SELECT to_jsonb(h) FROM ops.worker_heartbeats h WHERE worker_key='candidate_intake' AND worker_instance='db_scheduler' AND environment='test'),'null'::jsonb)::text;");
  assert.equal(readJson(`SELECT jsonb_build_object('count',count(*))::text FROM ops.raw_inputs WHERE raw_input_id=${literal(rawId)};`).count, 0, 'synthetic Raw ID must be unused before the test');
  const baseline = readJson(`SELECT jsonb_build_object(
    'raw_count',(SELECT count(*) FROM ops.raw_inputs),
    'raw_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY raw_input_id),'')) FROM ops.raw_inputs r),''),
    'event_count',(SELECT count(*) FROM ops.events),
    'event_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(e)::text),'' ORDER BY event_pk),'')) FROM ops.events e),''),
    'map_count',(SELECT count(*) FROM ops.channel_event_raw_map),
    'map_hash',coalesce((SELECT md5(coalesce(string_agg(md5((to_jsonb(m)-'event_fingerprint')::text),'' ORDER BY source_system,source_account_ref,provider_event_id),'')) FROM ops.channel_event_raw_map m),''),
    'effect_count',(SELECT count(*) FROM ops.event_effects),
    'effect_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(e)::text),'' ORDER BY event_pk,effect_key),'')) FROM ops.event_effects e),''),
    'command_count',(SELECT count(*) FROM ops.domain_commands),
    'command_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(c)::text),'' ORDER BY command_pk),'')) FROM ops.domain_commands c),''),
    'finance_commands',(SELECT count(*) FROM ops.domain_commands WHERE target_entity_type='Finance'),
    'line_functions',coalesce((SELECT md5(coalesce(string_agg(n.nspname||'.'||p.proname||':'||p.proowner::text||':'||coalesce(p.proacl::text,''),'|' ORDER BY n.nspname,p.proname,p.oid),'')) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname IN ('line_capture_ingest','line_capture_register_file')) OR (n.nspname='ops' AND p.proname IN ('complete_raw_capture_event','run_line_candidate_ingestion_tick'))),'')
  )::text;`);
  let committedFixture = false;
  let lockHolder;
  let routeWorker;
  let captureCompleter;
  try {
    psql(`BEGIN READ WRITE;\n${runtimeSql}\n${guardSql}\nGRANT EXECUTE ON FUNCTION ops.line_capture_canonical_json(jsonb) TO supabase_admin;\nGRANT EXECUTE ON FUNCTION ops.line_capture_canonical_envelope(jsonb) TO supabase_admin;\nCOMMIT;\n`);
    const setup = `
BEGIN READ WRITE;
INSERT INTO ops.raw_inputs(raw_input_id,channel,content_type,original_ref,raw_summary,source_system,source_account_ref,thread_id,message_id,metadata)
VALUES(${literal(rawId)},'LINE','LINE_EVENT_FOLLOW',${literal(`line://OFFICIAL/fixture/${runId}`)},'Synthetic LINE event lock-order fixture','LINE','LINE_OA:MEYOU_CONNECT_OFFICIAL','fixture-thread',${literal(runId)},jsonb_build_object('fixture_channel_race_run',${literal(runId)},'provider','LINE','provider_payload',jsonb_build_object('type','follow','source',jsonb_build_object('type','user','userId','LINE_USER_ID_FIXTURE_01'))));
INSERT INTO ops.events(schema_version,source_system,event_id,idempotency_key,trace_id,event_type,occurred_at,received_at,raw_input_id,processing_state)
VALUES('2.1','LINE',${literal(eventId)},${literal(`idem-${runId}`)},${literal(`trace-${runId}`)},'channel.raw.received',now(),'0001-01-01 00:00:00+00',${literal(rawId)},'RAW_STORED');
INSERT INTO ops.channel_event_raw_map(source_system,source_account_ref,provider_event_id,raw_input_id)
VALUES('LINE','LINE_OA:MEYOU_CONNECT_OFFICIAL',${literal(eventId)},${literal(rawId)});
CREATE FUNCTION ops.${triggerFunction}() RETURNS trigger LANGUAGE plpgsql SET search_path TO '' AS $pause$
BEGIN PERFORM pg_catalog.pg_sleep(1.5); RETURN NEW; END; $pause$;
CREATE TRIGGER ${triggerName} BEFORE UPDATE OF classification,metadata ON ops.raw_inputs
FOR EACH ROW WHEN (OLD.raw_input_id=${literal(rawId)}) EXECUTE FUNCTION ops.${triggerFunction}();
COMMIT;
SELECT 'LINE_RACE_FIXTURE_COMMITTED';
`;
    committedFixture = true;
    assert.match(psql(setup), /LINE_RACE_FIXTURE_COMMITTED/);

    const locksHeld = readJson(`SELECT jsonb_build_object('locked',coalesce((SELECT jsonb_agg(event_pk) FROM (SELECT event_pk FROM ops.events WHERE event_type='candidate.lead.received' AND processing_state='RAW_STORED' ORDER BY event_pk FOR UPDATE) AS locked_events),'[]'::jsonb))::text;`);
    const holdSql = `BEGIN; SELECT coalesce(jsonb_agg(event_pk),'[]'::jsonb)::text FROM (SELECT event_pk FROM ops.events WHERE event_type='candidate.lead.received' AND processing_state='RAW_STORED' ORDER BY event_pk FOR UPDATE) AS locked_events; SELECT 'LINE_RACE_LOCKS_HELD'; SELECT pg_catalog.pg_sleep(4); COMMIT;`;
    lockHolder = startPsql(holdSql);
    const heldRows = await lockHolder.firstLine;
    assert.equal(heldRows.length, locksHeld.locked.length);

    routeWorker = startPsql(`BEGIN; SET LOCAL statement_timeout='8s'; SELECT ops.run_line_candidate_ingestion_tick(now(),1,'channel-lock-order-worker')::text; COMMIT;`);
    await delay(300);
    captureCompleter = startPsql(`BEGIN; SET LOCAL statement_timeout='8s'; SELECT ops.complete_raw_capture_event((SELECT event_pk FROM ops.events WHERE event_id=${literal(eventId)}))::text; COMMIT;`);
    const [workerOutput, completeOutput] = await Promise.all([routeWorker.done, captureCompleter.done]);
    await lockHolder.done;
    const workerResult = JSON.parse(workerOutput.split(/\r?\n/).filter(Boolean)[0]);
    const completeResult = JSON.parse(completeOutput.split(/\r?\n/).filter(Boolean)[0]);
    assert.equal(workerResult.errors, 0, 'concurrent candidate routing should not deadlock');
    assert.ok(workerResult.routed_raw_events >= 1);
    assert.equal(completeResult.reason, 'STATE_NOT_ELIGIBLE', 'completion must observe and preserve the worker terminal state');
    assert.equal(completeResult.processing_state, 'COMPLETED');
    assert.deepEqual(readJson(`SELECT jsonb_build_object(
      'state',(SELECT processing_state::text FROM ops.events WHERE event_id=${literal(eventId)}),
      'effect_count',(SELECT count(*) FROM ops.event_effects WHERE event_pk=(SELECT event_pk FROM ops.events WHERE event_id=${literal(eventId)})),
      'candidate_children',(SELECT count(*) FROM ops.events WHERE raw_input_id=${literal(rawId)} AND event_type='candidate.lead.received'),
      'commands',(SELECT count(*) FROM ops.domain_commands WHERE source_raw_input_id=${literal(rawId)})
    )::text;`), { state: 'COMPLETED', effect_count: 1, candidate_children: 0, commands: 0 });
  } finally {
    if (routeWorker) await routeWorker.done.catch(() => {});
    if (captureCompleter) await captureCompleter.done.catch(() => {});
    if (lockHolder) await lockHolder.done.catch(() => {});
    if (committedFixture) {
      psql(`BEGIN READ WRITE;
DROP TRIGGER IF EXISTS ${triggerName} ON ops.raw_inputs;
DROP FUNCTION IF EXISTS ops.${triggerFunction}();
DELETE FROM ops.event_effects WHERE event_pk IN (SELECT event_pk FROM ops.events WHERE event_id=${literal(eventId)});
DELETE FROM ops.domain_commands WHERE source_raw_input_id=${literal(rawId)};
DELETE FROM ops.events WHERE raw_input_id=${literal(rawId)} AND event_id<>${literal(eventId)};
DELETE FROM ops.events WHERE event_id=${literal(eventId)};
DELETE FROM ops.channel_event_raw_map WHERE source_system='LINE' AND source_account_ref='LINE_OA:MEYOU_CONNECT_OFFICIAL' AND provider_event_id=${literal(eventId)} AND raw_input_id=${literal(rawId)};
DELETE FROM ops.raw_inputs WHERE raw_input_id=${literal(rawId)} AND metadata->>'fixture_channel_race_run'=${literal(runId)};
${heartbeatBefore === null ? `DELETE FROM ops.worker_heartbeats WHERE worker_key='candidate_intake' AND worker_instance='db_scheduler' AND environment='test';` : `UPDATE ops.worker_heartbeats SET status=${literal(heartbeatBefore.status)},version=${heartbeatBefore.version === null ? 'NULL' : literal(heartbeatBefore.version)},last_seen_at=${literal(heartbeatBefore.last_seen_at)}::timestamptz,metadata=${literal(JSON.stringify(heartbeatBefore.metadata))}::jsonb,created_at=${literal(heartbeatBefore.created_at)}::timestamptz,updated_at=${literal(heartbeatBefore.updated_at)}::timestamptz WHERE worker_key='candidate_intake' AND worker_instance='db_scheduler' AND environment='test';`}
COMMIT;`);
    }
  }
  const after = readJson(`SELECT jsonb_build_object(
    'raw_count',(SELECT count(*) FROM ops.raw_inputs),
    'raw_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(r)::text),'' ORDER BY raw_input_id),'')) FROM ops.raw_inputs r),''),
    'event_count',(SELECT count(*) FROM ops.events),
    'event_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(e)::text),'' ORDER BY event_pk),'')) FROM ops.events e),''),
    'map_count',(SELECT count(*) FROM ops.channel_event_raw_map),
    'map_hash',coalesce((SELECT md5(coalesce(string_agg(md5((to_jsonb(m)-'event_fingerprint')::text),'' ORDER BY source_system,source_account_ref,provider_event_id),'')) FROM ops.channel_event_raw_map m),''),
    'effect_count',(SELECT count(*) FROM ops.event_effects),
    'effect_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(e)::text),'' ORDER BY event_pk,effect_key),'')) FROM ops.event_effects e),''),
    'command_count',(SELECT count(*) FROM ops.domain_commands),
    'command_hash',coalesce((SELECT md5(coalesce(string_agg(md5(to_jsonb(c)::text),'' ORDER BY command_pk),'')) FROM ops.domain_commands c),''),
    'finance_commands',(SELECT count(*) FROM ops.domain_commands WHERE target_entity_type='Finance'),
    'line_functions',coalesce((SELECT md5(coalesce(string_agg(n.nspname||'.'||p.proname||':'||p.proowner::text||':'||coalesce(p.proacl::text,''),'|' ORDER BY n.nspname,p.proname,p.oid),'')) FROM pg_catalog.pg_proc p JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace WHERE (n.nspname='public' AND p.proname IN ('line_capture_ingest','line_capture_register_file')) OR (n.nspname='ops' AND p.proname IN ('complete_raw_capture_event','run_line_candidate_ingestion_tick'))),'')
  )::text;`);
  assert.deepEqual(after, baseline, 'committed concurrency fixture cleanup must restore protected rows and existing owners/ACLs');
  assert.deepEqual(readJson("SELECT coalesce((SELECT to_jsonb(h) FROM ops.worker_heartbeats h WHERE worker_key='candidate_intake' AND worker_instance='db_scheduler' AND environment='test'),'null'::jsonb)::text;"), heartbeatBefore);
});

