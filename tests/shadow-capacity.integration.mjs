#!/usr/bin/env node
// Physical-capacity integration harness for a disposable, network-isolated MYC clone.
// It writes only synthetic data in rollback transactions and compacts only the
// clone's ops.shadow_import_rows table after rollback.

import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

const TARGET = "myc-restore-20261016-bootstrap";
const DB_CAP = 419430400;
const SHADOW_CAP = 78643200;
const MAX_DB_FIXTURE_BYTES = 450 * 1024 * 1024;
const EXPECTED_ROWS = 36818;
const EXPECTED_FINGERPRINT = "-2770658449854450349";
const EXPECTED_SESSIONS = 3028;
const MAX_CHILD_MS = 120000;
const startedAt = Date.now();
const checks = [];
const quote = value => `'${String(value).replaceAll("'", "''")}'`;

function run(command, args, { input, timeout = 30000 } = {}) {
  const result = spawnSync(command, args, {
    input, encoding: "utf8", timeout, windowsHide: true, shell: false,
    maxBuffer: 3 * 1024 * 1024,
  });
  if (result.error) throw new Error(`${command} failed: ${result.error.message}`);
  if (result.status !== 0) {
    const detail = String(result.stderr ?? "").trim().split(/\r?\n/).slice(-3).join(" ").slice(0, 700);
    throw new Error(`${command} exited ${result.status}${detail ? `: ${detail}` : ""}`);
  }
  return String(result.stdout ?? "").trim();
}

if (process.env.MYC_TEST_CONTAINER !== undefined) {
  assert.equal(process.env.MYC_TEST_CONTAINER, TARGET, "MYC_TEST_CONTAINER may not redirect this bounded mutation harness");
}
assert.match(TARGET, /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/, "target must be a local Docker container name, never a host/URL");

const context = run("docker", ["context", "show"]);
const endpoint = run("docker", ["context", "inspect", context, "--format", "{{.Endpoints.docker.Host}}"]);
assert.match(endpoint, /^(npipe:|unix:|tcp:\/\/(127\.0\.0\.1|localhost)(:|\/|$))/, "Docker context must be local");
const inspect = run("docker", ["inspect", "--format", "{{.Name}}|{{.HostConfig.NetworkMode}}|{{json .NetworkSettings.Ports}}", TARGET]);
const [containerName, networkMode, publishedPorts] = inspect.split("|");
assert.equal(containerName, `/${TARGET}`, "container identity mismatch");
assert.equal(networkMode, "none", "target must have Docker network mode none");
assert.ok(publishedPorts === "null" || publishedPorts === "{}", "target must publish no ports");

const psqlArgs = ["exec", "-i", TARGET, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1", "-U", "supabase_admin", "-d", "postgres", "-h", "/tmp"];
function psql(sql, timeout = 30000) {
  const remaining = MAX_CHILD_MS - (Date.now() - startedAt);
  if (remaining <= 0) throw new Error("capacity integration exceeded its 120-second total time bound");
  return run("docker", psqlArgs, { input: sql, timeout: Math.min(timeout, remaining) });
}
function psqlCleanup(sql) {
  // Cleanup has its own 60-second allowance even if the bounded test window expires.
  return run("docker", psqlArgs, { input: sql, timeout: 60000 });
}
function json(sql) {
  return JSON.parse(psql(sql).split(/\r?\n/).filter(Boolean).at(-1));
}
function check(name, status, details = {}) {
  checks.push({ name, status, ...details });
}

const baseline = json(`SELECT json_build_object(
  'database',current_database(),
  'current_user',current_user,
  'server_major',current_setting('server_version_num')::integer/10000,
  'socket_only',inet_server_addr() IS NULL AND inet_client_addr() IS NULL,
  'user_schema_relations',(SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'),
  'shadow_rows',(SELECT count(*) FROM ops.shadow_import_rows),
  'shadow_fingerprint',coalesce((SELECT sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text FROM ops.shadow_import_rows r),'0'),
  'sessions',(SELECT count(*) FROM ops.shadow_import_sessions),
  'database_bytes',pg_database_size(current_database()),
  'shadow_bytes',pg_total_relation_size('ops.shadow_import_rows'::regclass),
  'gate',config.setting_is_true('migration_shadow_write_enabled'),
  'v4_guard',position('datahub-shadow-import-v4' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure))>0,
  'baseline_rpc',to_regprocedure('ops.get_shadow_import_baseline(text,text,text[])') IS NOT NULL,
  'db_guard',position('${DB_CAP}' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure))>0,
  'shadow_guard',position('${SHADOW_CAP}' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure))>0,
  'open_generic_cap_first',position('${DB_CAP}' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure)) < position('IF p_source_system <> ''GOOGLE_SHEETS''' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure)),
  'stage_generic_cap_first',position('${DB_CAP}' in pg_get_functiondef('ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure)) < position('IF v_session.source_system=''GOOGLE_SHEETS''' in pg_get_functiondef('ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure))
)::text;`);

assert.equal(baseline.database, "postgres");
assert.equal(baseline.current_user, "supabase_admin");
assert.equal(baseline.server_major, 17);
assert.equal(baseline.socket_only, true);
assert.equal(baseline.user_schema_relations, 934);
assert.equal(baseline.shadow_rows, EXPECTED_ROWS);
assert.equal(baseline.shadow_fingerprint, EXPECTED_FINGERPRINT);
assert.equal(baseline.sessions, EXPECTED_SESSIONS);
assert.equal(baseline.gate, false);
assert.equal(baseline.v4_guard, true);
assert.equal(baseline.baseline_rpc, true);
assert.equal(baseline.db_guard, true);
assert.equal(baseline.shadow_guard, true);
assert.equal(baseline.open_generic_cap_first, true);
assert.equal(baseline.stage_generic_cap_first, true);
assert.ok(baseline.database_bytes < DB_CAP, "baseline must be below the database cap");
assert.ok(baseline.shadow_bytes < SHADOW_CAP, "baseline must be below the shadow cap");
check("isolated_clone_identity_and_baseline", "PASS", {
  dockerContext: context, endpointKind: endpoint.split(":")[0], container: TARGET,
  networkMode, publishedPorts: false, database: baseline.database,
  rows: baseline.shadow_rows, fingerprint: baseline.shadow_fingerprint,
  sessions: baseline.sessions, databaseBytes: baseline.database_bytes,
  shadowBytes: baseline.shadow_bytes, gateInitiallyOff: true,
});

const sessionId = randomUUID();
const nonGoogleSessionId = randomUUID();
const fileOpenId = `capacity-open-${randomUUID()}`;
const fileRevision = `sha256:${randomUUID().replaceAll("-", "")}${randomUUID().replaceAll("-", "")}`;
const fileStageId = `capacity-stage-${randomUUID()}`;
const stageRevision = `sha256:${randomUUID().replaceAll("-", "")}${randomUUID().replaceAll("-", "")}`;
const v4Meta = (revision, rows = 1, bytes = 100, sourceRows = rows) =>
  `jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,'guard_required','v4','import_protocol','delta-v1','baseline_session_id',null,'input_rows',${rows},'input_bytes',${bytes},'source_rows',${sourceRows},'source_revision','${revision}')`;

const shadowBoundarySql = `
SET lock_timeout='5s';
SET statement_timeout='110s';
BEGIN READ WRITE;
UPDATE config.system_settings SET setting_value='true'::jsonb WHERE setting_key='migration_shadow_write_enabled';
INSERT INTO ops.shadow_import_sessions(session_id,source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
VALUES('${sessionId}','GOOGLE_SHEETS','${fileStageId}','capacity integration fixture','${stageRevision}',now(),'OPEN',true,ARRAY['Partner'],${v4Meta(stageRevision,400,2097152,400)},'shadow-capacity.integration');
INSERT INTO ops.shadow_import_sessions(session_id,source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
VALUES('${nonGoogleSessionId}','LOCAL_FIXTURE','capacity-nongoogle-shadow','local fixture','fixture-revision',now(),'OPEN',false,ARRAY[]::text[],'{}'::jsonb,'shadow-capacity.integration');
WITH payloads AS (
  SELECT i, string_agg(md5(i::text || ':' || g::text), '' ORDER BY g) AS payload
  FROM generate_series(1,400) AS rows(i)
  CROSS JOIN generate_series(1,1024) AS grams(g)
  GROUP BY i
), ins AS (
  INSERT INTO ops.shadow_import_rows(session_id,entity_key,source_sheet,source_row_number,source_pk,raw_record,normalized_record,row_hash)
  SELECT '${sessionId}'::uuid,'Partner',m.source_sheet,i+1,'capacity-fixture-'||i,
    jsonb_build_object('payload',payload),jsonb_build_object('payload',payload),
    md5(jsonb_build_object('payload',payload)::text)
  FROM payloads CROSS JOIN ops.migration_entity_map m
  WHERE m.entity_key='Partner'
  RETURNING 1
)
SELECT count(*) FROM ins;
DO $test$
DECLARE shadow_bytes bigint; db_bytes bigint; got text; sid uuid;
BEGIN
  shadow_bytes:=pg_total_relation_size('ops.shadow_import_rows'::regclass);
  db_bytes:=pg_database_size(current_database());
  IF shadow_bytes < ${SHADOW_CAP} THEN RAISE EXCEPTION 'HARNESS_SHADOW_FIXTURE_TOO_SMALL:%',shadow_bytes; END IF;
  IF db_bytes >= ${DB_CAP} THEN RAISE EXCEPTION 'HARNESS_DATABASE_CAP_PRECEDED_SHADOW_TEST:%',db_bytes; END IF;
  BEGIN
    PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS',${quote(fileOpenId)},'capacity fixture','${fileRevision}',now(),true,ARRAY['Partner'],
      ${v4Meta(fileRevision)},'shadow-capacity.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_SHADOW_OPEN_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_SHADOW_OPEN_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_SHADOW_OPEN_REJECTION:%',got;
  END IF;
  BEGIN
    PERFORM ops.open_shadow_import_session('LOCAL_FIXTURE','capacity-nongoogle-open','local fixture','fixture-revision',now(),false,ARRAY[]::text[],NULL,'shadow-capacity.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_NONGOOGLE_SHADOW_OPEN_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_NONGOOGLE_SHADOW_OPEN_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_NONGOOGLE_SHADOW_OPEN_REJECTION:%',got;
  END IF;
  SELECT session_id INTO sid FROM ops.shadow_import_sessions WHERE session_id='${sessionId}'::uuid;
  BEGIN
    PERFORM ops.stage_shadow_row(sid,'Partner',999999,'capacity-stage-fixture','{}'::jsonb,'{}'::jsonb);
    RAISE EXCEPTION 'HARNESS_EXPECTED_SHADOW_STAGE_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_SHADOW_STAGE_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_SHADOW_STAGE_REJECTION:%',got;
  END IF;
  BEGIN
    PERFORM ops.stage_shadow_row('${nonGoogleSessionId}'::uuid,'Partner',999999,'capacity-stage-fixture','{}'::jsonb,'{}'::jsonb);
    RAISE EXCEPTION 'HARNESS_EXPECTED_NONGOOGLE_SHADOW_STAGE_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_NONGOOGLE_SHADOW_STAGE_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_NONGOOGLE_SHADOW_STAGE_REJECTION:%',got;
  END IF;
  RAISE NOTICE 'HARNESS_SHADOW_CAPACITY_VERIFIED shadow_bytes=% db_bytes=%',shadow_bytes,db_bytes;
END
$test$;
SELECT json_build_object('measured_shadow_bytes',pg_total_relation_size('ops.shadow_import_rows'::regclass),'measured_database_bytes',pg_database_size(current_database()))::text;
ROLLBACK;
SELECT json_build_object('shadow_bytes_after_fixture',pg_total_relation_size('ops.shadow_import_rows'::regclass),'gate',config.setting_is_true('migration_shadow_write_enabled'))::text;
`;

const databaseBoundarySql = `
SET lock_timeout='5s';
SET statement_timeout='110s';
BEGIN READ WRITE;
UPDATE config.system_settings SET setting_value='true'::jsonb WHERE setting_key='migration_shadow_write_enabled';
CREATE UNLOGGED TABLE public.shadow_capacity_fixture_${sessionId.replaceAll("-", "")} (payload text);
ALTER TABLE public.shadow_capacity_fixture_${sessionId.replaceAll("-", "")} ALTER COLUMN payload SET STORAGE EXTERNAL;
INSERT INTO public.shadow_capacity_fixture_${sessionId.replaceAll("-", "")} (payload)
SELECT repeat(md5(i::text),32) FROM generate_series(1,280000) AS rows(i);
INSERT INTO ops.shadow_import_sessions(session_id,source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
VALUES('${sessionId}','GOOGLE_SHEETS','${fileStageId}','capacity integration fixture','${stageRevision}',now(),'OPEN',true,ARRAY['Partner'],${v4Meta(stageRevision,1,100,1)},'shadow-capacity.integration');
INSERT INTO ops.shadow_import_sessions(session_id,source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
VALUES('${nonGoogleSessionId}','LOCAL_FIXTURE','capacity-nongoogle-database','local fixture','fixture-revision',now(),'OPEN',false,ARRAY[]::text[],'{}'::jsonb,'shadow-capacity.integration');
DO $test$
DECLARE db_bytes bigint; shadow_bytes bigint; got text; sid uuid;
BEGIN
  db_bytes:=pg_database_size(current_database());
  shadow_bytes:=pg_total_relation_size('ops.shadow_import_rows'::regclass);
  IF db_bytes < ${DB_CAP} THEN RAISE EXCEPTION 'HARNESS_DATABASE_FIXTURE_TOO_SMALL:%',db_bytes; END IF;
  IF db_bytes > ${MAX_DB_FIXTURE_BYTES} THEN RAISE EXCEPTION 'HARNESS_DATABASE_FIXTURE_EXCEEDED_BOUND:%',db_bytes; END IF;
  IF shadow_bytes >= ${SHADOW_CAP} THEN RAISE EXCEPTION 'HARNESS_SHADOW_CAP_PRECEDED_DATABASE_TEST:%',shadow_bytes; END IF;
  BEGIN
    PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS',${quote(fileOpenId)},'capacity fixture','${fileRevision}',now(),true,ARRAY['Partner'],
      ${v4Meta(fileRevision)},'shadow-capacity.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_DB_OPEN_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_DB_OPEN_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_DB_OPEN_REJECTION:%',got;
  END IF;
  BEGIN
    PERFORM ops.open_shadow_import_session('LOCAL_FIXTURE','capacity-nongoogle-db-open','local fixture','fixture-revision',now(),false,ARRAY[]::text[],NULL,'shadow-capacity.integration');
    RAISE EXCEPTION 'HARNESS_EXPECTED_NONGOOGLE_DB_OPEN_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_NONGOOGLE_DB_OPEN_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_NONGOOGLE_DB_OPEN_REJECTION:%',got;
  END IF;
  SELECT session_id INTO sid FROM ops.shadow_import_sessions WHERE session_id='${sessionId}'::uuid;
  BEGIN
    PERFORM ops.stage_shadow_row(sid,'Partner',999999,'capacity-stage-fixture','{}'::jsonb,'{}'::jsonb);
    RAISE EXCEPTION 'HARNESS_EXPECTED_DB_STAGE_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_DB_STAGE_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_DB_STAGE_REJECTION:%',got;
  END IF;
  BEGIN
    PERFORM ops.stage_shadow_row('${nonGoogleSessionId}'::uuid,'Partner',999999,'capacity-stage-fixture','{}'::jsonb,'{}'::jsonb);
    RAISE EXCEPTION 'HARNESS_EXPECTED_NONGOOGLE_DB_STAGE_STOP_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_NONGOOGLE_DB_STAGE_STOP_NOT_RAISED' OR position('SHADOW_CAPACITY_STOP' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_NONGOOGLE_DB_STAGE_REJECTION:%',got;
  END IF;
  RAISE NOTICE 'HARNESS_DB_CAPACITY_VERIFIED shadow_bytes=% db_bytes=%',shadow_bytes,db_bytes;
END
$test$;
SELECT json_build_object('measured_shadow_bytes',pg_total_relation_size('ops.shadow_import_rows'::regclass),'measured_database_bytes',pg_database_size(current_database()))::text;
ROLLBACK;
SELECT json_build_object('database_bytes_after_fixture',pg_database_size(current_database()),'shadow_bytes_after_fixture',pg_total_relation_size('ops.shadow_import_rows'::regclass),'gate',config.setting_is_true('migration_shadow_write_enabled'))::text;
`;

let cleanupAttempted = false;
let cleanupDurationMs = 0;
let executionFailure = null;
try {
  const shadowOutput = psql(shadowBoundarySql, MAX_CHILD_MS);
  const shadowLines = shadowOutput.split(/\r?\n/).filter(Boolean);
  const shadowEvidence = JSON.parse(shadowLines.find(line => line.includes('"measured_shadow_bytes"')));
  const shadowAfter = JSON.parse(shadowLines.at(-1));
  assert.ok(shadowEvidence.measured_shadow_bytes >= SHADOW_CAP, "shadow relation did not cross the physical cap");
  assert.ok(shadowEvidence.measured_database_bytes < DB_CAP, "database cap must remain below threshold during shadow test");
  assert.equal(shadowAfter.gate, false);
  check("physical_shadow_cap_blocks_google_and_non_google_open_and_stage", "PASS", {
    fixtureRows: 400, measuredShadowBytes: shadowEvidence.measured_shadow_bytes,
    measuredDatabaseBytes: shadowEvidence.measured_database_bytes, nonGoogleOpenAndStageStopped: true, afterRollback: shadowAfter,
  });

  psql("SET lock_timeout='5s'; SET statement_timeout='55s'; VACUUM (FULL, ANALYZE) ops.shadow_import_rows;", MAX_CHILD_MS);
  const compact = json(`SELECT json_build_object(
    'shadow_rows',(SELECT count(*) FROM ops.shadow_import_rows),
    'shadow_fingerprint',coalesce((SELECT sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text FROM ops.shadow_import_rows r),'0'),
    'sessions',(SELECT count(*) FROM ops.shadow_import_sessions),
    'shadow_bytes',pg_total_relation_size('ops.shadow_import_rows'::regclass),
    'gate',config.setting_is_true('migration_shadow_write_enabled')
  )::text;`);
  assert.equal(compact.shadow_rows, EXPECTED_ROWS);
  assert.equal(compact.shadow_fingerprint, EXPECTED_FINGERPRINT);
  assert.equal(compact.sessions, EXPECTED_SESSIONS);
  assert.equal(compact.gate, false);
  assert.ok(compact.shadow_bytes < SHADOW_CAP, "shadow table must be compacted below75MiB before the database-boundary test");
  check("shadow_boundary_rollback_compacted_before_database_test", "PASS", compact);

  const dbOutput = psql(databaseBoundarySql, MAX_CHILD_MS);
  const dbLines = dbOutput.split(/\r?\n/).filter(Boolean);
  const dbEvidence = JSON.parse(dbLines.find(line => line.includes('"measured_database_bytes"')));
  const dbAfter = JSON.parse(dbLines.at(-1));
  assert.ok(dbEvidence.measured_database_bytes >= DB_CAP, "database did not cross the physical cap");
  assert.ok(dbEvidence.measured_database_bytes <= MAX_DB_FIXTURE_BYTES, "database fixture exceeded the 450 MiB bound");
  assert.ok(dbEvidence.measured_shadow_bytes < SHADOW_CAP, "shadow cap must remain below threshold during database test");
  assert.equal(dbAfter.gate, false);
  check("physical_database_cap_blocks_google_and_non_google_open_and_stage", "PASS", {
    fixtureRows: 280000, fixturePayloadBytesPerRow: 1024,
    measuredDatabaseBytes: dbEvidence.measured_database_bytes,
    measuredShadowBytes: dbEvidence.measured_shadow_bytes, nonGoogleOpenAndStageStopped: true, afterRollback: dbAfter,
  });
} catch (error) {
  check("capacity_boundary_execution", "FAIL", { error: String(error.message).slice(0, 900) });
  executionFailure = error;
} finally {
  cleanupAttempted = true;
  // VACUUM FULL is intentionally limited to this clone's shadow table. It is
  // required because rolled-back inserts can leave allocated relation pages.
  // This path retains a separate bounded cleanup budget if the test times out.
  const cleanupStarted = Date.now();
  psqlCleanup("SET lock_timeout='5s'; SET statement_timeout='55s'; VACUUM (FULL, ANALYZE) ops.shadow_import_rows;");
  cleanupDurationMs = Date.now() - cleanupStarted;
}

assert.equal(cleanupAttempted, true);
const final = json(`SELECT json_build_object(
  'shadow_rows',(SELECT count(*) FROM ops.shadow_import_rows),
  'shadow_fingerprint',coalesce((SELECT sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text FROM ops.shadow_import_rows r),'0'),
  'sessions',(SELECT count(*) FROM ops.shadow_import_sessions),
  'database_bytes',pg_database_size(current_database()),
  'shadow_bytes',pg_total_relation_size('ops.shadow_import_rows'::regclass),
  'gate',config.setting_is_true('migration_shadow_write_enabled')
)::text;`);
assert.equal(final.shadow_rows, EXPECTED_ROWS, "shadow row count must be restored exactly");
assert.equal(final.shadow_fingerprint, EXPECTED_FINGERPRINT, "shadow fingerprint must be restored exactly");
assert.equal(final.sessions, EXPECTED_SESSIONS, "session count must be restored exactly");
assert.equal(final.gate, false, "shadow-write gate must remain disabled");
assert.ok(final.shadow_bytes < SHADOW_CAP, "compacted retained shadow table must be below the cap");
check("rollback_and_compaction_restored_verified_baseline", "PASS", final);

process.stdout.write(`${JSON.stringify({
  suite: "myc-shadow-capacity.integration",
  status: executionFailure ? "FAIL" : "PASS",
  target: { container: TARGET, networkMode, publishedPorts: false, databaseBytesAfterCleanup: final.database_bytes },
  caps: { shadowBytes: SHADOW_CAP, databaseBytes: DB_CAP },
  elapsedMs: Date.now() - startedAt, cleanupDurationMs,
  checks,
  ...(executionFailure ? { error: String(executionFailure.message).slice(0, 900) } : {}),
}, null, 2)}\n`);
if (executionFailure) process.exitCode = 1;
