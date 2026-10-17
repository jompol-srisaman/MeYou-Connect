#!/usr/bin/env node
// Local-only integration checks for the V4 delta shadow-import contract.
// Mutations are synthetic and live inside one transaction that is rolled back.
// This harness can reach only the specifically named network-isolated clone.

import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

const TARGET = "myc-restore-20261016-bootstrap";
const EXPECTED_ROWS = 36818;
const EXPECTED_FINGERPRINT = "-2770658449854450349";
const EXPECTED_SESSIONS = 3028;
const DATAHUB_FILE_ID = "1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc";
const DATAHUB_ENTITIES = ["Candidate", "Cashbook", "Client", "Commission", "Data_Quality", "FollowUp", "Job", "Partner", "Placement", "Revenue"];
const DB_CAP = 419430400;
const SHADOW_CAP = 78643200;
const tests = [];
const q = value => `'${String(value).replaceAll("'", "''")}'`;
const uuid = () => randomUUID();
const rev = () => `sha256:${uuid().replaceAll("-", "")}${uuid().replaceAll("-", "")}`;

function run(command, args, { input, timeout = 30000 } = {}) {
  const r = spawnSync(command, args, { input, encoding: "utf8", timeout, windowsHide: true, shell: false, maxBuffer: 2 * 1024 * 1024 });
  if (r.error) throw new Error(`${command} failed: ${r.error.message}`);
  if (r.status !== 0) {
    const err = String(r.stderr ?? "").trim().split(/\r?\n/).slice(-3).join(" ").slice(0, 500);
    throw new Error(`${command} exited ${r.status}${err ? `: ${err}` : ""}`);
  }
  return String(r.stdout ?? "").trim();
}

if (process.env.MYC_TEST_CONTAINER !== undefined) assert.equal(process.env.MYC_TEST_CONTAINER, TARGET, "target override is forbidden");
assert.match(TARGET, /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/);
const context = run("docker", ["context", "show"]);
const endpoint = run("docker", ["context", "inspect", context, "--format", "{{.Endpoints.docker.Host}}"]);
assert.match(endpoint, /^(npipe:|unix:|tcp:\/\/(127\.0\.0\.1|localhost)(:|\/|$))/, "Docker context must be local");
const inspect = run("docker", ["inspect", "--format", "{{.Name}}|{{.HostConfig.NetworkMode}}|{{json .NetworkSettings.Ports}}", TARGET]);
const [container, networkMode, ports] = inspect.split("|");
assert.equal(container, `/${TARGET}`);
assert.equal(networkMode, "none", "clone must have network mode none");
assert.ok(ports === "null" || ports === "{}", "clone must publish no ports");

const psqlArgs = ["exec", "-i", TARGET, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "supabase_admin", "-d", "postgres", "-h", "/tmp"];
const psql = (sql, timeout = 30000) => run("docker", psqlArgs, { input: sql, timeout });
const json = sql => JSON.parse(psql(sql).split(/\r?\n/).filter(Boolean).at(-1));
const record = (name, status, detail = {}) => tests.push({ name, status, ...detail });

const baseline = json(`SELECT json_build_object(
 'database',current_database(),'user',current_user,'server_major',current_setting('server_version_num')::int/10000,
 'socket_only',inet_server_addr() IS NULL AND inet_client_addr() IS NULL,
 'relations',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'),
 'sessions',(SELECT count(*) FROM ops.shadow_import_sessions),
 'rows',(SELECT count(*) FROM ops.shadow_import_rows),
 'fingerprint',coalesce((SELECT sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text FROM ops.shadow_import_rows r),'0'),
 'gate',config.setting_is_true('migration_shadow_write_enabled'),
 'db_bytes',pg_database_size(current_database()),
 'shadow_bytes',pg_total_relation_size('ops.shadow_import_rows'::regclass),
 'master_counts',json_build_object('candidates',(SELECT count(*) FROM core.candidates),'revenues',(SELECT count(*) FROM finance.revenue),
  'commissions',(SELECT count(*) FROM finance.commissions),'journal_batches',(SELECT count(*) FROM finance.journal_batches),
  'domain_commands',(SELECT count(*) FROM ops.domain_commands),'event_effects',(SELECT count(*) FROM ops.event_effects)),
 'open_v4',position('delta-v1' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure))>0,
 'db_cap',position('419430400' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure))>0,
 'shadow_cap',position('78643200' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure))>0,
 'open_caps_before_legacy_branch',position('419430400' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure)) < position('IF p_source_system <> ''GOOGLE_SHEETS''' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure)),
 'stage_caps_before_google_branch',position('419430400' in pg_get_functiondef('ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure)) < position('IF v_session.source_system=''GOOGLE_SHEETS''' in pg_get_functiondef('ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure)),
 'global_lock',position('MYC_SHADOW_IMPORT_V3' in pg_get_functiondef('ops.get_shadow_import_baseline(text,text,text[])'::regprocedure))>0,
 'baseline_rpc',to_regprocedure('ops.get_shadow_import_baseline(text,text,text[])') IS NOT NULL,
 'stage_v4',position('SHADOW_ACCEPTED_SESSION_SEALED' in pg_get_functiondef('ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure))>0,
 'validate_v4',position('SHADOW_INCOMPLETE_DELTA_SESSION' in pg_get_functiondef('ops.validate_shadow_session(uuid)'::regprocedure))>0
)::text;`);
assert.equal(baseline.database, "postgres");
assert.equal(baseline.user, "supabase_admin");
assert.equal(baseline.server_major, 17);
assert.equal(baseline.socket_only, true);
assert.equal(baseline.relations, 934);
assert.equal(baseline.sessions, EXPECTED_SESSIONS);
assert.equal(baseline.rows, EXPECTED_ROWS);
assert.equal(baseline.fingerprint, EXPECTED_FINGERPRINT);
assert.equal(baseline.gate, false);
assert.ok(baseline.db_bytes < DB_CAP && baseline.shadow_bytes < SHADOW_CAP);
assert.ok(baseline.open_v4 && baseline.db_cap && baseline.shadow_cap && baseline.open_caps_before_legacy_branch && baseline.stage_caps_before_google_branch && baseline.global_lock && baseline.baseline_rpc && baseline.stage_v4 && baseline.validate_v4, "reviewed V4 guard must already be installed");
record("isolated_clone_identity_and_restore_fingerprint", "PASS", { container: TARGET, networkMode, publishedPorts: false, sessions: baseline.sessions, shadowRows: baseline.rows, shadowFingerprint: baseline.fingerprint, gateInitiallyOff: true });

const privileges = json(`WITH f AS (
 SELECT p.oid,p.proowner,p.prosecdef,p.proconfig FROM pg_proc p WHERE p.oid IN (
  'ops.get_shadow_import_baseline(text,text,text[])'::regprocedure,
  'ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure,
  'ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure,
  'ops.validate_shadow_session(uuid)'::regprocedure
 )
) SELECT json_build_object('count',count(*),'owner_postgres',bool_and(pg_get_userbyid(proowner)='postgres'),
 'security_definer',bool_and(prosecdef),'empty_search_path',bool_and(position('search_path=""' in coalesce(array_to_string(proconfig,','),''))>0),
 'service_role',bool_and(has_function_privilege('service_role',oid,'EXECUTE')),
 'anon_denied',bool_and(NOT has_function_privilege('anon',oid,'EXECUTE')),
 'authenticated_denied',bool_and(NOT has_function_privilege('authenticated',oid,'EXECUTE')))::text FROM f;`);
assert.deepEqual(privileges, { count: 4, owner_postgres: true, security_definer: true, empty_search_path: true, service_role: true, anon_denied: true, authenticated_denied: true });
record("rpc_owner_acl_and_search_path", "PASS", privileges);

const preservedFileState = json(`SELECT json_build_object(
 'legacy_open',(SELECT count(*) FROM ops.shadow_import_sessions WHERE source_system='GOOGLE_SHEETS' AND source_file_id='${DATAHUB_FILE_ID}' AND status IN ('OPEN','STAGED') AND (source_revision IS NULL OR source_revision NOT LIKE 'sha256:%')),
 'legacy_invalid_rows',(SELECT count(*) FROM ops.shadow_import_rows r JOIN ops.shadow_import_sessions s USING(session_id)
   WHERE s.source_system='GOOGLE_SHEETS' AND s.source_file_id='${DATAHUB_FILE_ID}' AND s.status IN ('VALIDATED','RECONCILED')
     AND s.metadata->>'import_protocol' IS DISTINCT FROM 'delta-v1' AND r.validation_status IN ('INVALID','SKIPPED'))
)::text;`);
assert.ok(preservedFileState.legacy_open >= 1, "preserved Data Hub file should contain the known unhashed legacy OPEN session");
assert.ok(preservedFileState.legacy_invalid_rows >= 4, "preserved Data Hub file should contain known historical invalid rows");
const actualBaseline = json(`SELECT ops.get_shadow_import_baseline('GOOGLE_SHEETS','${DATAHUB_FILE_ID}',ARRAY[${DATAHUB_ENTITIES.map(q).join(",")}])::text;`);
assert.equal(actualBaseline.entity_scope.length, DATAHUB_ENTITIES.length);
assert.deepEqual(actualBaseline.entity_scope, DATAHUB_ENTITIES);
assert.ok(actualBaseline.baseline_session_id, "preserved Data Hub file should retain its accepted baseline watermark");
assert.ok(actualBaseline.rows.length <= 1000);
record("preserved_datahub_baseline_ignores_legacy_open_and_historical_invalid", "PASS", {
  legacyOpenSessions: preservedFileState.legacy_open,
  historicalInvalidRows: preservedFileState.legacy_invalid_rows,
  baselineSessionIdPresent: true,
  baselineRowCount: actualBaseline.rows.length,
  entityScopeCount: actualBaseline.entity_scope.length,
});

const file = `delta-fixture:${uuid()}`;
const oldRevision = rev();
const changedRevision = rev();
const inflightRevision = rev();
const nextRevision = rev();
const budgetRevision = rev();
const limitFile = `delta-limits:${uuid()}`;
const limitRevision = rev();
const incompleteFile = `delta-incomplete:${uuid()}`;
const incompleteRevision = rev();
const script = `
SET lock_timeout='5s'; SET statement_timeout='45s';
BEGIN READ WRITE;
UPDATE config.system_settings SET setting_value='true'::jsonb WHERE setting_key='migration_shadow_write_enabled';
DO $delta$
DECLARE
  f text := ${q(file)}; old_rev text := ${q(oldRevision)}; new_rev text := ${q(changedRevision)};
  inflight_rev text := ${q(inflightRevision)}; next_rev text := ${q(nextRevision)};
  s0 uuid; s1 uuid; s2 uuid; got uuid; b jsonb; row_count integer; msg text;
  m jsonb; raw jsonb; normalized jsonb; row_id uuid;
BEGIN
  -- Empty baseline has a deterministic empty shape and exact requested scope.
  b := ops.get_shadow_import_baseline('GOOGLE_SHEETS',f,ARRAY['Candidate']);
  IF b->>'baseline_session_id' IS NOT NULL OR b->'rows'<>'[]'::jsonb OR b->'entity_scope'<>'["Candidate"]'::jsonb THEN
    RAISE EXCEPTION 'HARNESS_EMPTY_BASELINE_MISMATCH';
  END IF;

  -- Seed one accepted historical delta with two records; this transaction
  -- rolls back after the real RPCs exercise the next delta.
  INSERT INTO ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by,created_at)
  VALUES('GOOGLE_SHEETS',f,'fixture',old_rev,now()-interval '2 minutes','VALIDATED',true,ARRAY['Candidate'],
   jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','guard_required','v4','import_protocol','delta-v1','source_revision',old_rev,'allowlisted_fields_only',true,'input_rows',2,'input_bytes',500,'source_rows',2,'baseline_session_id',null),
   'shadow-delta.integration',now()-interval '2 minutes') RETURNING session_id INTO s0;
  INSERT INTO ops.shadow_import_rows(session_id,entity_key,source_sheet,source_row_number,source_pk,raw_record,normalized_record,row_hash,validation_status,validation_issues)
  SELECT s0,'Candidate',m.source_sheet,v.rownum,v.pk,v.rec,v.rec,md5(v.rec::text),'VALID','[]'::jsonb
  FROM ops.migration_entity_map m CROSS JOIN (VALUES
   (2,'MYC-C-999991',jsonb_build_object('candidate_id','MYC-C-999991','nickname','Before')),
   (3,'MYC-C-999992',jsonb_build_object('candidate_id','MYC-C-999992','nickname','Retained'))
  ) AS v(rownum,pk,rec) WHERE m.entity_key='Candidate';
  b := ops.get_shadow_import_baseline('GOOGLE_SHEETS',f,ARRAY['Candidate']);
  IF (b->>'baseline_session_id')::uuid IS DISTINCT FROM s0 OR jsonb_array_length(b->'rows')<>2 THEN
    RAISE EXCEPTION 'HARNESS_SEEDED_BASELINE_MISMATCH';
  END IF;

  -- Changed-only delta points at the accepted baseline and stages one updated
  -- record; validation seals the session and latest-per-key merge preserves
  -- the untouched second record.
  m := jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow',
   'allowlisted_fields_only',true,'guard_required','v4','import_protocol','delta-v1',
   'baseline_session_id',s0,'input_rows',1,'input_bytes',500,'source_rows',2,'source_revision',new_rev);
  s1 := ops.open_shadow_import_session('GOOGLE_SHEETS',f,'fixture',new_rev,now(),true,ARRAY['Candidate'],m,'shadow-delta.integration');
  raw := jsonb_build_object('candidate_id','MYC-C-999991','nickname','After');
  normalized := raw;
  row_id := ops.stage_shadow_row(s1,'Candidate',2,'MYC-C-999991',raw,normalized);
  IF row_id IS NULL THEN RAISE EXCEPTION 'HARNESS_STAGE_DID_NOT_RETURN_ID'; END IF;
  b := ops.validate_shadow_session(s1);
  IF (b->>'valid')::int<>1 OR (b->>'invalid')::int<>0 OR (b->>'skipped')::int<>0 THEN
    RAISE EXCEPTION 'HARNESS_DELTA_VALIDATION_MISMATCH';
  END IF;
  b := ops.get_shadow_import_baseline('GOOGLE_SHEETS',f,ARRAY['Candidate']);
  IF (b->>'baseline_session_id')::uuid IS DISTINCT FROM s1 OR jsonb_array_length(b->'rows')<>2
     OR (SELECT e.value->'normalized_record'->>'nickname' FROM jsonb_array_elements(b->'rows') e(value) WHERE e.value->>'source_pk'='MYC-C-999991') IS DISTINCT FROM 'After'
     OR (SELECT e.value->'normalized_record'->>'nickname' FROM jsonb_array_elements(b->'rows') e(value) WHERE e.value->>'source_pk'='MYC-C-999992') IS DISTINCT FROM 'Retained' THEN
    RAISE EXCEPTION 'HARNESS_DELTA_MERGE_MISMATCH';
  END IF;

  -- A retry of the identical accepted revision is idempotent, and the row
  -- writer cannot mutate an accepted session.
  got := ops.open_shadow_import_session('GOOGLE_SHEETS',f,'fixture',new_rev,now()+interval '1 day',true,ARRAY['Candidate'],m,'shadow-delta.integration');
  IF got IS DISTINCT FROM s1 THEN RAISE EXCEPTION 'HARNESS_IDEMPOTENT_OPEN_MISMATCH'; END IF;
  BEGIN
    PERFORM ops.stage_shadow_row(s1,'Candidate',2,'MYC-C-999991',raw,normalized);
    RAISE EXCEPTION 'HARNESS_EXPECTED_SEALED_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    IF msg='HARNESS_EXPECTED_SEALED_REJECTION_NOT_RAISED' OR position('SHADOW_ACCEPTED_SESSION_SEALED' in msg)=0 THEN RAISE; END IF;
  END;

  m := jsonb_set(jsonb_set(m,'{source_revision}',to_jsonb('${rev()}'::text)),'{baseline_session_id}',to_jsonb(s1::text));
  BEGIN
    PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS',f,'fixture',m->>'source_revision',now()-interval '1 second',true,ARRAY['Candidate'],m,'shadow-delta.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_OUT_OF_ORDER_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    IF msg='HARNESS_EXPECTED_OUT_OF_ORDER_REJECTION_NOT_RAISED' OR position('SHADOW_SNAPSHOT_OUT_OF_ORDER' in msg)=0 THEN RAISE; END IF;
  END;
  m := jsonb_set(m,'{source_revision}',to_jsonb('${rev()}'::text));
  BEGIN
    PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS',f,'fixture',m->>'source_revision',now()+interval '6 minutes',true,ARRAY['Candidate'],m,'shadow-delta.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_FUTURE_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    IF msg='HARNESS_EXPECTED_FUTURE_REJECTION_NOT_RAISED' OR position('SHADOW_SNAPSHOT_TIME_INVALID' in msg)=0 THEN RAISE; END IF;
  END;

  -- Old baseline and inflight writes fail closed.
  m := jsonb_set(jsonb_set(m,'{source_revision}',to_jsonb(next_rev)),'{baseline_session_id}',to_jsonb(s0::text));
  BEGIN
    PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS',f,'fixture',next_rev,now(),true,ARRAY['Candidate'],m,'shadow-delta.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_STALE_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    IF msg='HARNESS_EXPECTED_STALE_REJECTION_NOT_RAISED' OR position('SHADOW_STALE_BASELINE' in msg)=0 THEN RAISE; END IF;
  END;

  m := jsonb_set(jsonb_set(m,'{source_revision}',to_jsonb(inflight_rev)),'{baseline_session_id}',to_jsonb(s1::text));
  s2 := ops.open_shadow_import_session('GOOGLE_SHEETS',f,'fixture',inflight_rev,now(),true,ARRAY['Candidate'],m,'shadow-delta.integration');
  BEGIN
    PERFORM ops.get_shadow_import_baseline('GOOGLE_SHEETS',f,ARRAY['Candidate']);
    RAISE EXCEPTION 'HARNESS_EXPECTED_INFLIGHT_BASELINE_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    IF msg='HARNESS_EXPECTED_INFLIGHT_BASELINE_REJECTION_NOT_RAISED' OR position('SHADOW_IMPORT_IN_PROGRESS' in msg)=0 THEN RAISE; END IF;
  END;
  m := jsonb_set(jsonb_set(m,'{source_revision}',to_jsonb(next_rev)),'{baseline_session_id}',to_jsonb(s1::text));
  BEGIN
    PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS',f,'fixture',next_rev,now(),true,ARRAY['Candidate'],m,'shadow-delta.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_CONCURRENT_OPEN_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS msg = MESSAGE_TEXT;
    IF msg='HARNESS_EXPECTED_CONCURRENT_OPEN_REJECTION_NOT_RAISED' OR position('SHADOW_IMPORT_IN_PROGRESS' in msg)=0 THEN RAISE; END IF;
  END;
END
$delta$;
SELECT 'delta-baseline-merge-idempotency-stale-inflight:PASS';
DO $limits$
DECLARE s uuid; msg text; m jsonb; raw jsonb; non_google_row uuid;
BEGIN
  -- Preserve the pre-existing alternate-source contract below physical caps.
  s:=ops.open_shadow_import_session('LOCAL_FIXTURE','delta-nongoogle-${uuid()}','fixture','plain-test-revision',now(),false,ARRAY[]::text[],NULL,'shadow-delta.integration');
  non_google_row:=ops.stage_shadow_row(s,'Candidate',2,'fixture-candidate',jsonb_build_object('candidate_id','fixture-candidate'),jsonb_build_object('candidate_id','fixture-candidate'));
  IF non_google_row IS NULL THEN RAISE EXCEPTION 'HARNESS_NON_GOOGLE_STAGE_FAILED'; END IF;

  m:=jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,
   'guard_required','v4','import_protocol','delta-v1','baseline_session_id',null,'input_rows',1,'input_bytes',500,
   'source_rows',1,'source_revision','${limitRevision}');
  s:=ops.open_shadow_import_session('GOOGLE_SHEETS','${limitFile}','fixture','${limitRevision}',NULL,true,ARRAY['Candidate'],m,'shadow-delta.integration');
  IF NOT EXISTS (SELECT 1 FROM ops.shadow_import_sessions x WHERE x.session_id=s AND x.snapshot_at BETWEEN now()-interval '1 second' AND now()+interval '1 second') THEN
    RAISE EXCEPTION 'HARNESS_NULL_SNAPSHOT_DID_NOT_DEFAULT_TO_NOW';
  END IF;
  raw:=jsonb_build_object('candidate_id','MYC-C-999993','nickname','One');
  PERFORM ops.stage_shadow_row(s,'Candidate',2,'MYC-C-999993',raw,raw);
  BEGIN PERFORM ops.stage_shadow_row(s,'Candidate',3,'MYC-C-999994',jsonb_build_object('candidate_id','MYC-C-999994'),jsonb_build_object('candidate_id','MYC-C-999994')); RAISE EXCEPTION 'HARNESS_NO_SESSION_ROW_CAP';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT; IF position('SHADOW_ROW_COUNT_BUDGET_EXCEEDED' in msg)=0 THEN RAISE; END IF; END;

  m:=jsonb_set(m,'{input_rows}','2'::jsonb);
  m:=jsonb_set(m,'{source_rows}','2'::jsonb);
  m:=jsonb_set(m,'{source_revision}',to_jsonb('${incompleteRevision}'::text));
  s:=ops.open_shadow_import_session('GOOGLE_SHEETS','${incompleteFile}','fixture','${incompleteRevision}',now(),true,ARRAY['Candidate'],m,'shadow-delta.integration');
  raw:=jsonb_build_object('candidate_id','MYC-C-999995','nickname','One');
  PERFORM ops.stage_shadow_row(s,'Candidate',2,'MYC-C-999995',raw,raw);
  BEGIN PERFORM ops.validate_shadow_session(s); RAISE EXCEPTION 'HARNESS_NO_INCOMPLETE_DELTA_REJECTION';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT; IF position('SHADOW_INCOMPLETE_DELTA_SESSION' in msg)=0 THEN RAISE; END IF; END;

  m:=jsonb_set(m,'{input_rows}','1'::jsonb);
  m:=jsonb_set(m,'{source_rows}','1'::jsonb);
  m:=jsonb_set(m,'{source_revision}',to_jsonb('${rev()}'::text));
  s:=ops.open_shadow_import_session('GOOGLE_SHEETS','${limitFile}:large','fixture',m->>'source_revision',now(),true,ARRAY['Candidate'],m,'shadow-delta.integration');
  BEGIN PERFORM ops.stage_shadow_row(s,'Candidate',2,'MYC-C-999996',
    jsonb_build_object('candidate_id','MYC-C-999996','pad',repeat('x',32769)),jsonb_build_object('candidate_id','MYC-C-999996'));
    RAISE EXCEPTION 'HARNESS_NO_ROW_SIZE_REJECTION';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS msg=MESSAGE_TEXT; IF position('SHADOW_ROW_BUDGET_EXCEEDED' in msg)=0 THEN RAISE; END IF; END;
END
$limits$;
SELECT 'alternate-source-low-side-and-delta-budgets:PASS';
DO $reject$
DECLARE got text; m jsonb := jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,'guard_required','v4','import_protocol','delta-v1','baseline_session_id',null,'input_rows',1,'input_bytes',100,'source_rows',1,'source_revision','${budgetRevision}');
BEGIN
  BEGIN PERFORM ops.get_shadow_import_baseline('GOOGLE_SHEETS','${file}',ARRAY['Candidate','Candidate']); RAISE EXCEPTION 'HARNESS_NO_DUP_SCOPE_ERROR';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got=MESSAGE_TEXT; IF position('SHADOW_BASELINE_INVALID' in got)=0 THEN RAISE; END IF; END;
  BEGIN PERFORM ops.get_shadow_import_baseline('GOOGLE_SHEETS','${file}',ARRAY['not-an-entity']); RAISE EXCEPTION 'HARNESS_NO_UNKNOWN_SCOPE_ERROR';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got=MESSAGE_TEXT; IF position('SHADOW_BASELINE_INVALID' in got)=0 THEN RAISE; END IF; END;
  BEGIN PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS','${file}','fixture',m->>'source_revision',now(),true,ARRAY['Candidate'],NULL,'test'); RAISE EXCEPTION 'HARNESS_NO_NULL_METADATA_ERROR';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got=MESSAGE_TEXT; IF position('SHADOW_HASH_PROTOCOL_REQUIRED' in got)=0 THEN RAISE; END IF; END;
  m := jsonb_set(m,'{input_rows}','1001'::jsonb);
  BEGIN PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS','${file}', 'fixture','${budgetRevision}',now(),true,ARRAY['Candidate'],m,'test'); RAISE EXCEPTION 'HARNESS_NO_ROW_BUDGET_ERROR';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got=MESSAGE_TEXT; IF position('SHADOW_INPUT_BUDGET_EXCEEDED' in got)=0 THEN RAISE; END IF; END;
END
$reject$;
SELECT 'scope-protocol-input-budgets:PASS';
ROLLBACK;
SELECT 'transaction-rolled-back';`;

try {
  const output = psql(script, 60000);
  assert.match(output, /delta-baseline-merge-idempotency-stale-inflight:PASS/);
  assert.match(output, /scope-protocol-input-budgets:PASS/);
  assert.match(output, /alternate-source-low-side-and-delta-budgets:PASS/);
  assert.match(output, /transaction-rolled-back/);
  record("delta_baseline_merge_idempotency_stale_and_inflight", "PASS");
  record("scope_protocol_and_input_budgets", "PASS");
} catch (error) {
  record("delta_transactional_integration", "FAIL", { error: String(error.message).slice(0, 700) });
  throw error;
}

const gateResult = psql(`DO $gate$
DECLARE got text;
BEGIN
  BEGIN
    PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS','delta-disabled-${uuid()}','fixture','${rev()}',now(),true,ARRAY['Candidate'],
      jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,'guard_required','v4','import_protocol','delta-v1','baseline_session_id',null,'input_rows',1,'input_bytes',100,'source_rows',1,'source_revision','${rev()}'),'test');
    RAISE EXCEPTION 'HARNESS_DISABLED_GATE_BYPASSED';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS got=MESSAGE_TEXT;
    IF position('migration shadow write gate is disabled' in got)=0 THEN RAISE; END IF;
  END;
END
$gate$;
SELECT 'disabled-gate:PASS';`);
assert.match(gateResult, /disabled-gate:PASS/);
record("disabled_write_gate_fails_closed", "PASS");

async function advisoryLockCheck() {
  const first = spawn("docker", ["exec", "-i", TARGET, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "supabase_admin", "-d", "postgres", "-h", "/tmp",
    "-c", "BEGIN; SELECT pg_advisory_xact_lock(hashtextextended('MYC_SHADOW_IMPORT_V3',0)); SELECT pg_sleep(2); ROLLBACK;"],
  { stdio: ["ignore", "pipe", "pipe"], windowsHide: true, shell: false });
  let stderr = "";
  first.stderr.setEncoding("utf8");
  first.stderr.on("data", chunk => { stderr += chunk; });
  const closed = new Promise((resolve, reject) => {
    first.once("error", reject);
    first.once("close", (code, signal) => resolve({ code, signal }));
  });
  await new Promise(resolve => setTimeout(resolve, 250));
  const started = Date.now();
  try {
    const b = json(`SELECT ops.get_shadow_import_baseline('GOOGLE_SHEETS','delta-lock-${uuid()}',ARRAY['Candidate'])::text;`);
    assert.equal(b.baseline_session_id, null);
    assert.deepEqual(b.rows, []);
    assert.deepEqual(b.entity_scope, ["Candidate"]);
    const waitedMs = Date.now() - started;
    assert.ok(waitedMs >= 1200, `baseline call did not serialize on the advisory lock (${waitedMs}ms)`);
    const exit = await closed;
    assert.equal(exit.code, 0, `lock holder failed (${exit.signal ?? exit.code}): ${stderr.slice(-300)}`);
    record("global_advisory_lock_serializes_baseline_with_writer", "PASS", { waitedMs });
  } catch (error) {
    await closed;
    record("global_advisory_lock_serializes_baseline_with_writer", "FAIL", { error: String(error.message).slice(0, 500) });
    throw error;
  }
}
await advisoryLockCheck();

const final = json(`SELECT json_build_object(
 'sessions',(SELECT count(*) FROM ops.shadow_import_sessions),
 'rows',(SELECT count(*) FROM ops.shadow_import_rows),
 'fingerprint',coalesce((SELECT sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text FROM ops.shadow_import_rows r),'0'),
 'gate',config.setting_is_true('migration_shadow_write_enabled'),
 'master_counts',json_build_object('candidates',(SELECT count(*) FROM core.candidates),'revenues',(SELECT count(*) FROM finance.revenue),
  'commissions',(SELECT count(*) FROM finance.commissions),'journal_batches',(SELECT count(*) FROM finance.journal_batches),
  'domain_commands',(SELECT count(*) FROM ops.domain_commands),'event_effects',(SELECT count(*) FROM ops.event_effects))
)::text;`);
assert.equal(final.sessions, EXPECTED_SESSIONS);
assert.equal(final.rows, EXPECTED_ROWS);
assert.equal(final.fingerprint, EXPECTED_FINGERPRINT);
assert.equal(final.gate, false);
assert.deepEqual(final.master_counts, baseline.master_counts);
record("rollback_preserved_snapshot_and_gate", "PASS", { sessions: final.sessions, rows: final.rows, fingerprint: final.fingerprint, gateOff: !final.gate });
process.stdout.write(`${JSON.stringify({ suite: "myc-shadow-delta.integration", status: tests.every(t => t.status === "PASS") ? "PASS" : "FAIL", tests, target: TARGET, networkMode, publishedPorts: false }, null, 2)}\n`);
