#!/usr/bin/env node
// Local-only PostgreSQL integration harness for the MYC Shadow Import v3 guard.
// Every database write is inside a transaction that is rolled back. This file
// never accepts a host, URL, password, or connection string.

import assert from "node:assert/strict";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

const TARGET = process.env.MYC_TEST_CONTAINER ?? "myc-restore-20261016-bootstrap";
const MAX_DB_BYTES = 400 * 1024 * 1024;
const MAX_SHADOW_BYTES = 75 * 1024 * 1024;
const MAX_SESSION_ROWS = 1000;
const MAX_SESSION_BYTES = 2 * 1024 * 1024;
const SOURCE_CATALOG_RELATIONS = 934;
const SOURCE_CATALOG_SESSIONS = 3028;
const SOURCE_CATALOG_SHADOW_ROWS = new Set([36818, 786782]);

const tests = [];
const literal = value => `'${String(value).replaceAll("'", "''")}'`;
const sqlIdentity = {
  open: "ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)",
  stage: "ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)",
  validate: "ops.validate_shadow_session(uuid)",
};

function assertContainerName(name) {
  assert.match(name, /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/, "MYC_TEST_CONTAINER must be a Docker container name, never a host or URL");
  assert.equal(name.includes("://"), false, "network endpoints are forbidden");
}

function run(command, args, { input, timeout = 30000 } = {}) {
  const result = spawnSync(command, args, {
    input,
    encoding: "utf8",
    timeout,
    windowsHide: true,
    shell: false,
    maxBuffer: 2 * 1024 * 1024,
  });
  if (result.error) throw new Error(`${command} could not run: ${result.error.message}`);
  if (result.status !== 0) {
    const detail = String(result.stderr ?? "").trim().split(/\r?\n/).slice(-2).join(" ").slice(0, 500);
    throw new Error(`${command} exited ${result.status}${detail ? `: ${detail}` : ""}`);
  }
  return String(result.stdout ?? "").trim();
}

function inspectLocalDocker() {
  const context = run("docker", ["context", "show"]);
  const endpoint = run("docker", ["context", "inspect", context, "--format", "{{.Endpoints.docker.Host}}"]);
  assert.match(endpoint, /^(npipe:|unix:|tcp:\/\/(127\.0\.0\.1|localhost)(:|\/|$))/, "Docker context must be local; remote Docker contexts are forbidden");
  const inspected = run("docker", [
    "inspect", "--format",
    "{{.Name}}|{{.HostConfig.NetworkMode}}|{{json .NetworkSettings.Ports}}",
    TARGET,
  ]);
  const [name, networkMode, ports] = inspected.split("|");
  assert.equal(name, `/${TARGET}`, "the inspected container must match the explicitly selected local target");
  assert.equal(networkMode, "none", "restore container must have Docker network mode none");
  assert.ok(ports === "null" || ports === "{}", "restore container must not publish ports");
  return { context, endpointKind: endpoint.split(":")[0], container: TARGET, networkMode, publishedPorts: false };
}

const psqlArgs = [
  "exec", "-i", TARGET,
  "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1",
  "-U", "supabase_admin", "-d", "postgres", "-h", "/tmp",
];

function psql(sql, timeout = 30000) {
  return run("docker", psqlArgs, { input: sql, timeout });
}

function psqlJson(sql) {
  const out = psql(sql);
  return JSON.parse(out.split(/\r?\n/).filter(Boolean).at(-1));
}

function result(name, status, detail = {}) {
  tests.push({ name, status, ...detail });
}

function runCase(name, sql) {
  try {
    const output = psql(sql);
    if (output.startsWith("SKIP:")) result(name, "SKIP", { reason: output.slice(5, 300) });
    else result(name, "PASS", output ? { evidence: output.slice(-500) } : {});
  } catch (error) {
    result(name, "FAIL", { error: String(error.message).slice(0, 600) });
    throw error;
  }
}

function tx(testSql, label) {
  // The temporary gate change and all fixture rows are reverted together.
  return `BEGIN READ WRITE;\n${testSql}\nROLLBACK;\nSELECT ${literal(label)} || ':ROLLED_BACK';`;
}

function expectSqlError(fragment, statement) {
  return `DO $test$
DECLARE got text;
BEGIN
  BEGIN
    ${statement};
    RAISE EXCEPTION 'HARNESS_EXPECTED_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN
    got := SQLERRM;
  END;
  IF got = 'HARNESS_EXPECTED_REJECTION_NOT_RAISED' OR position(${literal(fragment)} in got) = 0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_REJECTION:%', got;
  END IF;
END
$test$;`;
}

function enabledGate() {
  return "UPDATE config.system_settings SET setting_value='true'::jsonb WHERE setting_key='migration_shadow_write_enabled';";
}

function revision() {
  return `sha256:${randomUUID().replaceAll("-", "")}${randomUUID().replaceAll("-", "")}`;
}

function v4Metadata(rev, { guard = "v4", rows = 1, bytes = 100, sourceRows = rows, baseline = "NULL" } = {}) {
  return `jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,'guard_required',${literal(guard)},'import_protocol','delta-v1','baseline_session_id',${baseline},'input_rows',${rows},'input_bytes',${bytes},'source_rows',${sourceRows},'source_revision',${literal(rev)})`;
}

function openCall({ fileId, rev, metadata = null, source = "'GOOGLE_SHEETS'", sourceOfTruth = "true", entities = "ARRAY['Partner']", snapshot = "now()" }) {
  const payload = metadata ?? v4Metadata(rev);
  return `ops.open_shadow_import_session(${source}, ${literal(fileId)}, 'integration fixture', ${literal(rev)}, ${snapshot}, ${sourceOfTruth}, ${entities}, ${payload}, 'shadow-guard.integration')`;
}

function directFixtureSession(fileId, rev, status = "OPEN") {
  return `INSERT INTO ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
VALUES('GOOGLE_SHEETS',${literal(fileId)},'integration fixture',${literal(rev)},now(),'${status}',false,ARRAY['Partner'],jsonb_build_object('guard_applied','v4','guard_required','v4','import_protocol','delta-v1','source_revision',${literal(rev)},'input_rows',1,'input_bytes',100,'source_rows',1,'baseline_session_id',null),'shadow-guard.integration')
RETURNING session_id;`;
}

async function concurrencyLockCheck() {
  // Hold the exact xact-lock key used by open_shadow_import_session, then
  // invoke the RPC in a second transaction and verify it waits for the lock.
  // The synthetic session and temporary gate change are rolled back.
  const first = spawn("docker", [
    "exec", "-i", TARGET, "psql", "-X", "-qAt", "-v", "ON_ERROR_STOP=1",
    "-U", "supabase_admin", "-d", "postgres", "-h", "/tmp",
    "-c", "BEGIN READ WRITE; SELECT pg_advisory_xact_lock(hashtextextended('MYC_SHADOW_IMPORT_V3',0)); SELECT 'LOCK_HELD'; SELECT pg_sleep(3); ROLLBACK;",
  ], { stdio: ["ignore", "pipe", "pipe"], windowsHide: true, shell: false });
  const closed = new Promise((resolve, reject) => {
    first.once("error", reject);
    first.once("close", (code, signal) => resolve({ code, signal }));
  });
  let stdout = "";
  let stderr = "";
  first.stdout.setEncoding("utf8");
  first.stderr.setEncoding("utf8");
  first.stdout.on("data", chunk => { stdout += chunk; });
  first.stderr.on("data", chunk => { stderr += chunk; });
  // psql may buffer stdout until the following pg_sleep completes, so do not
  // use its marker as a readiness signal. The delay lets the first statement
  // acquire the transaction lock before the RPC starts.
  await new Promise(resolve => setTimeout(resolve, 250));
  let waitedMs;
  try {
    const started = Date.now();
    psql(`BEGIN READ WRITE; ${enabledGate()} SELECT ${openCall({
      fileId: `guard-concurrent:${randomUUID()}`, rev: revision(),
    })}; ROLLBACK;`, 10000);
    waitedMs = Date.now() - started;
    assert.ok(waitedMs >= 1500, `concurrent open RPC did not wait on the snapshot lock (${waitedMs}ms)`);
  } finally {
    const exit = await closed;
    assert.equal(exit.code, 0, `lock-holder transaction did not roll back cleanly (${exit.signal ?? exit.code}): ${stderr.slice(-300)}`);
    assert.ok(stdout.includes("LOCK_HELD"), `lock holder did not report acquiring the lock: ${stderr.slice(-300)}`);
  }
  result("concurrent_snapshot_lock_serializes", "PASS", { mechanism: "open RPC waited for transaction-scoped advisory lock", waitedMs });
}

async function main() {
  assertContainerName(TARGET);
  const docker = inspectLocalDocker();
  const preflight = psqlJson(`SELECT json_build_object(
    'database', current_database(),
    'server_major', current_setting('server_version_num')::integer / 10000,
    'server_socket_only', inet_server_addr() IS NULL AND inet_client_addr() IS NULL,
    'relations', (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname !~ '^pg_' AND n.nspname<>'information_schema'),
    'session_count', (SELECT count(*) FROM ops.shadow_import_sessions),
    'shadow_row_count', (SELECT count(*) FROM ops.shadow_import_rows),
    'database_bytes', pg_database_size(current_database()),
    'shadow_bytes', pg_total_relation_size('ops.shadow_import_rows'::regclass),
    'shadow_gate', config.setting_is_true('migration_shadow_write_enabled'),
    'source_revision_count', (SELECT count(*) FROM ops.shadow_import_sessions WHERE source_system='GOOGLE_SHEETS' AND source_revision LIKE 'sha256:%'),
    'guard_open', position('datahub-shadow-import-v4' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure)) > 0,
    'baseline_rpc', to_regprocedure('ops.get_shadow_import_baseline(text,text,text[])') IS NOT NULL,
    'guard_stage', position('SHADOW_ROW_BUDGET_EXCEEDED' in pg_get_functiondef('ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure)) > 0,
    'guard_db_cap', position('419430400' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure)) > 0,
    'guard_shadow_cap', position('${MAX_SHADOW_BYTES}' in pg_get_functiondef('ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure)) > 0
  )::text;`);
  assert.equal(preflight.database, "postgres", "target must be the isolated postgres database");
  assert.equal(preflight.server_major, 17, "target must use PostgreSQL 17");
  assert.equal(preflight.server_socket_only, true, "psql must use only the container's local Unix socket");
  assert.equal(preflight.relations, SOURCE_CATALOG_RELATIONS, "target does not match the verified restore catalog relation count");
  assert.equal(preflight.session_count, SOURCE_CATALOG_SESSIONS, "target does not match the verified restore session inventory");
  assert.ok(SOURCE_CATALOG_SHADOW_ROWS.has(preflight.shadow_row_count), "target shadow row count is not a recognized verified restore state");
  assert.equal(preflight.shadow_gate, false, "shadow write gate must start disabled");
  result("isolated_restore_preflight", "PASS", {
    container: TARGET, network: docker.networkMode, database: preflight.database,
    relations: preflight.relations, sessions: preflight.session_count,
    shadowRows: preflight.shadow_row_count, databaseBytes: preflight.database_bytes,
    shadowBytes: preflight.shadow_bytes, writeGateInitiallyOff: true,
  });

  const baselineEffects = psqlJson(`SELECT json_build_object(
    'candidates',(SELECT count(*) FROM core.candidates),
    'revenues',(SELECT count(*) FROM finance.revenue),
    'commissions',(SELECT count(*) FROM finance.commissions),
    'journal_batches',(SELECT count(*) FROM finance.journal_batches),
    'domain_commands',(SELECT count(*) FROM ops.domain_commands),
    'apply_audits',(SELECT count(*) FROM ops.domain_command_apply_audit),
    'event_effects',(SELECT count(*) FROM ops.event_effects)
  )::text;`);

  const acl = psqlJson(`WITH f AS (
    SELECT p.oid,p.proowner,p.prosecdef,p.proconfig
    FROM pg_proc p WHERE p.oid IN (
      'ops.get_shadow_import_baseline(text,text,text[])'::regprocedure,
      'ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text)'::regprocedure,
      'ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb)'::regprocedure,
      'ops.validate_shadow_session(uuid)'::regprocedure
    )
  ) SELECT json_build_object(
    'functions',count(*),
    'owners_postgres',bool_and(pg_get_userbyid(proowner)='postgres'),
    'security_definer',bool_and(prosecdef),
    'empty_search_path',bool_and(position('search_path=""' in coalesce(array_to_string(proconfig,','),'')) > 0),
    'service_role_execute',bool_and(has_function_privilege('service_role',oid,'EXECUTE')),
    'anon_denied',bool_and(NOT has_function_privilege('anon',oid,'EXECUTE')),
    'authenticated_denied',bool_and(NOT has_function_privilege('authenticated',oid,'EXECUTE'))
  )::text FROM f;`);
  assert.deepEqual(acl, {
    functions: 4, owners_postgres: true, security_definer: true,
    empty_search_path: true, service_role_execute: true,
    anon_denied: true, authenticated_denied: true,
  }, "guard function owner/security/ACL identity changed from the verified source catalog");
  result("function_owner_search_path_acl_identity", "PASS", acl);

  if (!preflight.guard_open || !preflight.baseline_rpc || !preflight.guard_stage || !preflight.guard_db_cap || !preflight.guard_shadow_cap) {
    result("guard_installation", "BLOCKED", { reason: "the reviewed V4 guard with 400MiB database / 75MiB shadow limits is not installed on this isolated target" });
    throw new Error("Reviewed V4 guard is not installed; refusing to apply migrations or mutate the target.");
  }
  result("guard_installation", "PASS", { databaseLimitBytes: MAX_DB_BYTES, shadowLimitBytes: MAX_SHADOW_BYTES });

  const id = randomUUID();
  runCase("disabled_gate_fails_closed", tx(
    expectSqlError("migration shadow write gate is disabled", `PERFORM ${openCall({ fileId: `guard-test:${id}`, rev: revision() })}`),
    "disabled_gate_fails_closed",
  ));

  const protocolId = randomUUID();
  runCase("hash_protocol_rejects_unversioned_and_bad_hash", tx(`${enabledGate()}
    ${expectSqlError("SHADOW_HASH_PROTOCOL_REQUIRED", `PERFORM ${openCall({ fileId: `guard-protocol:${protocolId}`, rev: "not-a-sha256-revision" })}`)}
    ${(() => { const r = revision(); return expectSqlError("SHADOW_HASH_PROTOCOL_REQUIRED", `PERFORM ${openCall({ fileId: `guard-protocol:${protocolId}`, rev: r, metadata: v4Metadata(r, { guard: "v3" }) })}`); })()}
    SELECT 'hash_protocol_rejections:ok';`, "hash_protocol_rejects_unversioned_and_bad_hash"));

  const budgetId = randomUUID();
  runCase("input_row_and_byte_budgets_reject_overage", tx(`${enabledGate()}
    ${(() => { const r = revision(); return expectSqlError("SHADOW_INPUT_BUDGET_EXCEEDED", `PERFORM ${openCall({ fileId: `guard-budget:${budgetId}`, rev: r, metadata: v4Metadata(r, { rows: 1001, sourceRows: 1001 }) })}`); })()}
    ${(() => { const r = revision(); return expectSqlError("SHADOW_INPUT_BUDGET_EXCEEDED", `PERFORM ${openCall({ fileId: `guard-budget:${budgetId}`, rev: r, metadata: v4Metadata(r, { bytes: MAX_SESSION_BYTES + 1 }) })}`); })()}
    SELECT 'input_budgets:ok';`, "input_row_and_byte_budgets_reject_overage"));

  const duplicateId = randomUUID();
  const duplicateRev = revision();
  runCase("duplicate_valid_revision_rejected", tx(`${enabledGate()}
    ${directFixtureSession(`guard-duplicate:${duplicateId}`, duplicateRev, "VALIDATED")}
    ${expectSqlError("SHADOW_SNAPSHOT_ALREADY_EXISTS", `PERFORM ${openCall({ fileId: `guard-duplicate:${duplicateId}`, rev: duplicateRev })}`)}
    SELECT 'duplicate_revision:ok';`, "duplicate_valid_revision_rejected"));

  const incompleteId = randomUUID();
  const incompleteRev = revision();
  runCase("incomplete_revision_requires_review", tx(`${enabledGate()}
    ${directFixtureSession(`guard-incomplete:${incompleteId}`, incompleteRev, "FAILED")}
    ${expectSqlError("SHADOW_INCOMPLETE_SNAPSHOT_REQUIRES_REVIEW", `PERFORM ${openCall({ fileId: `guard-incomplete:${incompleteId}`, rev: incompleteRev })}`)}
    SELECT 'incomplete_revision:ok';`, "incomplete_revision_requires_review"));

  const sessionBudgetId = randomUUID();
  if (preflight.database_bytes >= MAX_DB_BYTES || preflight.shadow_bytes >= MAX_SHADOW_BYTES) {
    result("hashed_session_budget_stops_at_20", "SKIP", { reason: "database or shadow capacity stop takes precedence on this restored snapshot" });
  } else runCase("hashed_session_budget_stops_at_20", tx(`${enabledGate()}
DO $test$
DECLARE n integer; i integer; f text; r text; got text;
BEGIN
  SELECT count(*) INTO n FROM ops.shadow_import_sessions WHERE source_system='GOOGLE_SHEETS' AND source_revision LIKE 'sha256:%';
  IF n < 20 THEN
    FOR i IN 1..(20-n) LOOP
      f := 'guard-budget-fill:${sessionBudgetId}:' || i::text;
      r := 'sha256:' || repeat(md5(f),2);
      PERFORM ops.open_shadow_import_session('GOOGLE_SHEETS',f,'integration fixture',r,now(),true,ARRAY['Partner'],
        jsonb_build_object('function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,
          'guard_required','v4','import_protocol','delta-v1','baseline_session_id',null,'input_rows',1,'input_bytes',100,'source_rows',1,'source_revision',r),
        'shadow-guard.integration');
    END LOOP;
  END IF;
  BEGIN
    PERFORM ${openCall({ fileId: `guard-budget-stop:${sessionBudgetId}`, rev: revision() })};
    RAISE EXCEPTION 'HARNESS_EXPECTED_RETENTION_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_RETENTION_REJECTION_NOT_RAISED' OR position('SHADOW_RETENTION_ARCHIVE_REQUIRED' in got)=0 THEN
    RAISE EXCEPTION 'HARNESS_WRONG_RETENTION_REJECTION:%',got;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE;
END
$test$;
SELECT 'hashed_session_budget:transaction_rolled_back';`, "hashed_session_budget_stops_at_20"));

  const rowBudgetId = randomUUID();
  runCase("row_payload_budget_rejects_oversized_record", tx(`${enabledGate()}
DO $test$
DECLARE s uuid; got text; r text;
BEGIN
  r:='sha256:${randomUUID().replaceAll("-", "")}${randomUUID().replaceAll("-", "")}';
  INSERT INTO ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
  VALUES('GOOGLE_SHEETS','guard-row-size:${rowBudgetId}','integration fixture',r,now(),'OPEN',true,ARRAY['Partner'],
    jsonb_build_object('guard_applied','v4','guard_required','v4','import_protocol','delta-v1','function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,'source_revision',r,'baseline_session_id',null,'input_rows',1,'input_bytes',100,'source_rows',1),'shadow-guard.integration') RETURNING session_id INTO s;
  BEGIN
    PERFORM ops.stage_shadow_row(s,'Partner',2,'MYC-P-999998',jsonb_build_object('partner_id','MYC-P-999998','pad',repeat('x',32769)),jsonb_build_object('partner_id','MYC-P-999998'));
    RAISE EXCEPTION 'HARNESS_EXPECTED_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_REJECTION_NOT_RAISED' OR position('SHADOW_ROW_BUDGET_EXCEEDED' in got)=0 THEN RAISE EXCEPTION 'HARNESS_WRONG_REJECTION:%',got; END IF;
END
$test$;
SELECT 'row_payload_budget:ok';`, "row_payload_budget_rejects_oversized_record"));

  const countBudgetId = randomUUID();
  const countSession = randomUUID();
  runCase("session_row_budget_stops_at_1000", tx(`${enabledGate()}
DO $test$
DECLARE s uuid; i integer; got text; rev text;
BEGIN
  rev := 'sha256:' || repeat(md5('${countSession}'),2);
  INSERT INTO ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
  VALUES('GOOGLE_SHEETS','guard-row-count:${countBudgetId}','integration fixture',rev,now(),'OPEN',true,ARRAY['Partner'],
    jsonb_build_object('guard_applied','v4','guard_required','v4','import_protocol','delta-v1','function','datahub-shadow-import-v4','mode','read_only_sheets_to_shadow','allowlisted_fields_only',true,'source_revision',rev,'baseline_session_id',null,'input_rows',1000,'input_bytes',2097152,'source_rows',1000),'shadow-guard.integration') RETURNING session_id INTO s;
  FOR i IN 1..${MAX_SESSION_ROWS} LOOP
    PERFORM ops.stage_shadow_row(s,'Partner',i+1,'MYC-P-'||lpad(i::text,6,'0'),jsonb_build_object('partner_id','MYC-P-'||lpad(i::text,6,'0')),jsonb_build_object('partner_id','MYC-P-'||lpad(i::text,6,'0')));
  END LOOP;
  BEGIN
    PERFORM ops.stage_shadow_row(s,'Partner',${MAX_SESSION_ROWS + 2},'MYC-P-999997',jsonb_build_object('partner_id','MYC-P-999997'),jsonb_build_object('partner_id','MYC-P-999997'));
    RAISE EXCEPTION 'HARNESS_EXPECTED_REJECTION_NOT_RAISED';
  EXCEPTION WHEN OTHERS THEN got:=SQLERRM; END;
  IF got='HARNESS_EXPECTED_REJECTION_NOT_RAISED' OR position('SHADOW_ROW_COUNT_BUDGET_EXCEEDED' in got)=0 THEN RAISE EXCEPTION 'HARNESS_WRONG_REJECTION:%',got; END IF;
END
$test$;
SELECT 'row_count_budget:ok';`, "session_row_budget_stops_at_1000"));

  await concurrencyLockCheck();

  const finalEffects = psqlJson(`SELECT json_build_object(
    'candidates',(SELECT count(*) FROM core.candidates),
    'revenues',(SELECT count(*) FROM finance.revenue),
    'commissions',(SELECT count(*) FROM finance.commissions),
    'journal_batches',(SELECT count(*) FROM finance.journal_batches),
    'domain_commands',(SELECT count(*) FROM ops.domain_commands),
    'apply_audits',(SELECT count(*) FROM ops.domain_command_apply_audit),
    'event_effects',(SELECT count(*) FROM ops.event_effects)
  )::text;`);
  assert.deepEqual(finalEffects, baselineEffects, "guard integration tests changed a Candidate/Finance/master effect count");
  result("no_master_or_finance_effects", "PASS", { unchanged: Object.keys(finalEffects) });

  process.stdout.write(`${JSON.stringify({
    suite: "myc-shadow-guard.integration",
    status: tests.some(test => test.status === "SKIP") ? "PASS_WITH_SKIPS" : "PASS",
    target: docker,
    checks: tests,
  }, null, 2)}\n`);
}

main().catch(error => {
  process.stdout.write(`${JSON.stringify({
    suite: "myc-shadow-guard.integration",
    status: "FAIL",
    target: { container: TARGET },
    checks: tests,
    error: String(error.message).slice(0, 800),
  }, null, 2)}\n`);
  process.exitCode = 1;
});
