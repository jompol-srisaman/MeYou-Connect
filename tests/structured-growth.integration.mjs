#!/usr/bin/env node
// Bounded physical storage benchmark in a fresh template0 database inside the
// isolated MYC restore container. It reconstructs only three source table
// definitions from pg_dump schema metadata and inserts synthetic ops rows.

import assert from 'node:assert/strict';
import { createHash, randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';

const CONTAINER = 'myc-restore-20261016-bootstrap';
const DB = 'myc_capacity_benchmark_20261017';
const MAX_MS = 120_000;
const MAX_DB_BYTES = 300 * 1024 * 1024;
const TOKEN = randomUUID();
const MARKER = `MYC-STRUCTURED-GROWTH-BENCHMARK:${TOKEN}`;
const RESULT = 'C:\\Users\\HP\\MYC-Recovery-Private\\benchmark-result.json';
const started = Date.now();
const result = {
  status: 'RUNNING', benchmark: 'synthetic structured Raw/event/ledger storage model',
  created_at: new Date().toISOString(), container: CONTAINER, database: DB,
  identity_marker: MARKER, limits: { wall_seconds: MAX_MS / 1000, database_bytes: MAX_DB_BYTES },
  assumptions: [
    'Database is created from template0 and contains only the reconstructed ops.raw_inputs, ops.events, and ops.raw_datahub_sync_ledger structures plus ops enum and pgcrypto extension; source rows are never copied.',
    'Each synthetic message has a random 2,048-byte metadata payload encoded as base64 and an exactly 114-byte ASCII summary. This models structured data only; it is not provider traffic.',
    'Measured PostgreSQL bytes include table/index/TOAST allocation; WAL, external media objects, network traffic, and provider accounting are excluded.',
    'Rows are inserted directly into these three tables; no workers, HTTP routes, storage operations, domain-command processing, or business master schemas are created or invoked.'
  ],
  media_reference: {
    source: 'MYC_STORAGE_AUTHORITY_CAPACITY_20261017.md historical file-intake aggregate',
    intake_items: 171,
    checksum_bearing_mirrored_objects: 165,
    unresolved_mirrors: 6,
    known_size_metadata_bytes: 35235411,
    object_bytes_remeasured: false,
    included_in_postgresql_delta: false
  },
  stages: [], cleanup: { status: 'NOT_STARTED' }
};

function run(command, args, { input, timeout = 30_000 } = {}) {
  const remaining = MAX_MS - (Date.now() - started);
  if (remaining <= 0) throw new Error('benchmark exceeded the 120-second total runtime bound');
  const r = spawnSync(command, args, {
    input, encoding: 'utf8', timeout: Math.min(timeout, remaining),
    windowsHide: true, shell: false, maxBuffer: 2 * 1024 * 1024
  });
  if (r.error) throw new Error(`${command} could not run: ${r.error.message}`);
  if (r.status !== 0) {
    const detail = String(r.stderr ?? '').trim().split(/\r?\n/).slice(-3).join(' ').slice(0, 900);
    throw new Error(`${command} exited ${r.status}${detail ? `: ${detail}` : ''}`);
  }
  return String(r.stdout ?? '').trim();
}

function docker(args, options) { return run('docker', args, options); }
function psqlArgs(db = 'postgres') {
  return ['exec', '-i', CONTAINER, 'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'supabase_admin', '-d', db, '-h', '/tmp'];
}
function sql(db, statement, timeout) { return docker(psqlArgs(db), { input: statement, timeout }); }
function json(db, statement) { return JSON.parse(sql(db, statement).split(/\r?\n/).filter(Boolean).at(-1)); }

function sourceSchemaDump() {
  const dump = docker(['exec', CONTAINER, 'pg_dump', '-w', '-h', '/tmp', '-U', 'supabase_admin', '-d', 'postgres',
    '--schema-only', '--no-owner', '--no-acl', '--no-comments', '--table=ops.raw_inputs', '--table=ops.events', '--table=ops.raw_datahub_sync_ledger']);
  assert.match(dump, /CREATE TABLE ops\.raw_inputs/);
  assert.match(dump, /CREATE TABLE ops\.events/);
  assert.match(dump, /CREATE TABLE ops\.raw_datahub_sync_ledger/);
  assert.match(dump, /CREATE UNIQUE INDEX raw_inputs_source_ref_uq/);
  assert.match(dump, /events_raw_input_id_fkey/);
  assert.match(dump, /raw_datahub_sync_ledger_raw_input_id_fkey/);
  assert.doesNotMatch(dump, /COPY ops\.|INSERT INTO ops\./, 'schema dump must not carry table data');
  assert.equal((dump.match(/CREATE TABLE ops\./g) ?? []).length, 3, 'dump may contain only the three intended table definitions');
  return dump;
}

function assertLocalIsolatedContainer() {
  if (process.env.MYC_TEST_CONTAINER !== undefined) assert.equal(process.env.MYC_TEST_CONTAINER, CONTAINER, 'MYC_TEST_CONTAINER may not redirect this bounded mutation harness');
  assert.match(CONTAINER, /^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/);
  const context = docker(['context', 'show']);
  const endpoint = docker(['context', 'inspect', context, '--format', '{{.Endpoints.docker.Host}}']);
  assert.match(endpoint, /^(npipe:|unix:|tcp:\/\/(127\.0\.0\.1|localhost)(:|\/|$))/, 'Docker endpoint must be local');
  const identity = docker(['inspect', '--format', '{{.Name}}|{{.HostConfig.NetworkMode}}|{{json .NetworkSettings.Ports}}', CONTAINER]);
  const [name, network, ports] = identity.split('|');
  assert.equal(name, `/${CONTAINER}`);
  assert.equal(network, 'none', 'container must have network mode none');
  assert.ok(ports === 'null' || ports === '{}', 'container must publish no ports');
}

function assertBenchmarkDbIdentity() {
  const identity = json(DB, `SELECT json_build_object(
    'database', current_database(),
    'owner', pg_catalog.pg_get_userbyid(d.datdba),
    'comment', pg_catalog.shobj_description(d.oid,'pg_database'),
    'server_major', current_setting('server_version_num')::integer/10000,
    'socket_only', inet_server_addr() IS NULL AND inet_client_addr() IS NULL,
    'database_bytes', pg_database_size(current_database()),
    'raw_triggers', (SELECT count(*) FROM pg_trigger WHERE tgrelid='ops.raw_inputs'::regclass AND NOT tgisinternal),
    'event_triggers', (SELECT count(*) FROM pg_trigger WHERE tgrelid='ops.events'::regclass AND NOT tgisinternal),
    'ledger_triggers', (SELECT count(*) FROM pg_trigger WHERE tgrelid='ops.raw_datahub_sync_ledger'::regclass AND NOT tgisinternal),
    'business_schemas_present', (SELECT count(*) FROM pg_namespace WHERE nspname IN ('candidate','finance','core')),
    'raw_count', (SELECT count(*) FROM ops.raw_inputs),
    'event_count', (SELECT count(*) FROM ops.events),
    'ledger_count', (SELECT count(*) FROM ops.raw_datahub_sync_ledger)
  )::text FROM pg_database d WHERE d.datname=current_database();`);
  assert.equal(identity.database, DB);
  assert.equal(identity.owner, 'supabase_admin');
  assert.equal(identity.comment, MARKER, 'database identity marker must match this run token');
  assert.equal(identity.server_major, 17);
  assert.equal(identity.socket_only, true);
  assert.equal(identity.raw_triggers, 0, 'unexpected raw table triggers could cause side effects');
  assert.equal(identity.event_triggers, 0, 'unexpected event table triggers could cause side effects');
  assert.equal(identity.ledger_triggers, 0, 'unexpected ledger table triggers could cause side effects');
  assert.equal(identity.business_schemas_present, 0, 'benchmark database must not contain business master schemas');
  assert.ok(identity.database_bytes < MAX_DB_BYTES, 'cloned database already exceeds safety bound');
  return identity;
}

function createSql(batchSize, offset) {
  return `
BEGIN READ WRITE;
SET LOCAL lock_timeout='5s';
SET LOCAL statement_timeout='90000ms';
WITH fixture AS (
  SELECT i,
    pg_catalog.regexp_replace(pg_catalog.encode(extensions.gen_random_bytes(1024) || extensions.gen_random_bytes(1024),'base64'),'[[:space:]]','','g') AS payload_b64,
    clock_timestamp() AS occurred_at
  FROM generate_series(${offset + 1},${offset + batchSize}) AS g(i)
)
INSERT INTO ops.raw_inputs (
  raw_input_id, received_at, channel, sender_type, sender_ref, content_type, original_ref,
  raw_summary, classification, ai_parsed, sensitive, processing_status, source_system,
  source_account_ref, thread_id, message_id, entity_type_hint, natural_language_summary,
  consent_signal, metadata
)
SELECT 'MYC-RAW-'||lpad(i::text,6,'0'), occurred_at, 'BENCHMARK', 'system', 'synthetic-test-only',
  'application/json', 'bench://${TOKEN}/'||i,
  rpad('Synthetic structured benchmark message with fixed 114-byte descriptive summary; no person or provider data.',114,'.'),
  'channel.raw.received', false, false, 'RAW_STORED', 'MYC_CAPACITY_BENCH', 'MYC_CAPACITY_BENCH',
  'thread-benchmark', 'message-'||i, 'BENCHMARK',
  rpad('Synthetic structured benchmark message with fixed 114-byte descriptive summary; no person or provider data.',114,'.'),
  'TEST_FIXTURE', pg_catalog.jsonb_build_object('benchmark_marker','${MARKER}','ordinal',i,'payload_b64',payload_b64)
FROM fixture;

WITH fixture AS (
  SELECT i, clock_timestamp() AS occurred_at
  FROM generate_series(${offset + 1},${offset + batchSize}) AS g(i)
)
INSERT INTO ops.events (
  schema_version, source_system, event_id, idempotency_key, trace_id, event_type,
  occurred_at, received_at, processing_state, processing_attempt, raw_input_id, created_at, updated_at
)
SELECT 'myc-benchmark-v1', 'MYC_CAPACITY_BENCH', 'BENCH-${TOKEN}-EVENT-'||lpad(i::text,6,'0'),
  'BENCH-${TOKEN}-IDEMP-'||lpad(i::text,6,'0'), 'BENCH-${TOKEN}-TRACE-'||lpad(i::text,6,'0'),
  'channel.raw.received', occurred_at, occurred_at, 'RECEIVED'::ops.event_processing_state, 0,
  'MYC-RAW-'||lpad(i::text,6,'0'), occurred_at, occurred_at
FROM fixture;

INSERT INTO ops.raw_datahub_sync_ledger (
  stable_external_key, raw_input_id, source_system, source_account_ref, source_received_at,
  payload_checksum, sync_status, attempt_count
)
SELECT 'BENCH-${TOKEN}-RAW-'||lpad(i::text,6,'0'), 'MYC-RAW-'||lpad(i::text,6,'0'),
  'MYC_CAPACITY_BENCH', 'MYC_CAPACITY_BENCH', clock_timestamp(),
  md5('BENCH-${TOKEN}-CHECKSUM-'||i::text), 'PENDING', 0
FROM generate_series(${offset + 1},${offset + batchSize}) AS g(i);
COMMIT;
`;
}

function sample(label, expectedAdded) {
  const s = json(DB, `SELECT json_build_object(
    'label','${label}',
    'raw_rows',(SELECT count(*) FROM ops.raw_inputs WHERE source_system='MYC_CAPACITY_BENCH' AND source_account_ref='MYC_CAPACITY_BENCH'),
    'event_rows',(SELECT count(*) FROM ops.events WHERE source_system='MYC_CAPACITY_BENCH'),
    'ledger_rows',(SELECT count(*) FROM ops.raw_datahub_sync_ledger WHERE source_system='MYC_CAPACITY_BENCH'),
    'database_bytes',pg_database_size(current_database()),
    'raw_bytes',pg_total_relation_size('ops.raw_inputs'::regclass),
    'events_bytes',pg_total_relation_size('ops.events'::regclass),
    'ledger_bytes',pg_total_relation_size('ops.raw_datahub_sync_ledger'::regclass),
    'payload_min_chars',(SELECT min(length(metadata->>'payload_b64')) FROM ops.raw_inputs WHERE source_system='MYC_CAPACITY_BENCH'),
    'payload_max_chars',(SELECT max(length(metadata->>'payload_b64')) FROM ops.raw_inputs WHERE source_system='MYC_CAPACITY_BENCH'),
    'summary_min_bytes',(SELECT min(octet_length(raw_summary)) FROM ops.raw_inputs WHERE source_system='MYC_CAPACITY_BENCH'),
    'summary_max_bytes',(SELECT max(octet_length(raw_summary)) FROM ops.raw_inputs WHERE source_system='MYC_CAPACITY_BENCH')
  )::text;`);
  assert.equal(s.raw_rows, expectedAdded, `${label}: unexpected synthetic Raw count`);
  assert.equal(s.event_rows, expectedAdded, `${label}: unexpected synthetic event count`);
  assert.equal(s.ledger_rows, expectedAdded, `${label}: unexpected synthetic ledger count`);
  if (expectedAdded > 0) {
    assert.equal(s.payload_min_chars, 2732, `${label}: payload should represent 2,048 random bytes in base64`);
    assert.equal(s.payload_max_chars, 2732, `${label}: payload should represent 2,048 random bytes in base64`);
    assert.equal(s.summary_min_bytes, 114, `${label}: summary must be 114 bytes`);
    assert.equal(s.summary_max_bytes, 114, `${label}: summary must be 114 bytes`);
  }
  assert.ok(s.database_bytes < MAX_DB_BYTES, `${label}: database exceeded 300 MiB fixture bound`);
  return s;
}

async function save() {
  result.elapsed_seconds = Number(((Date.now() - started) / 1000).toFixed(2));
  await mkdir('C:\\Users\\HP\\MYC-Recovery-Private', { recursive: true });
  await writeFile(RESULT, `${JSON.stringify(result, null, 2)}\n`, { encoding: 'utf8' });
}

let created = false;
let outcomeError = null;
try {
  assertLocalIsolatedContainer();
  const preflightSql = `SELECT json_build_object(
    'server_major',current_setting('server_version_num')::integer/10000,
    'source_name',current_database(),
    'socket_only',inet_server_addr() IS NULL AND inet_client_addr() IS NULL,
    'target_exists',EXISTS(SELECT 1 FROM pg_database WHERE datname='${DB}'),
    'template0_bytes',pg_database_size('template0')
  )::text;`;
  const preflight = json('postgres', preflightSql);
  assert.equal(preflight.server_major, 17);
  assert.equal(preflight.source_name, 'postgres');
  assert.equal(preflight.socket_only, true);
  assert.equal(preflight.target_exists, false, 'benchmark DB already exists; refusing to reuse or drop it');
  assert.ok(preflight.template0_bytes < MAX_DB_BYTES, 'template0 size must remain below the benchmark bound');

  // template0 ensures no recovered rows or protected application state are copied.
  sql('postgres', `CREATE DATABASE ${DB} TEMPLATE template0 OWNER supabase_admin;`);
  created = true;
  sql('postgres', `COMMENT ON DATABASE ${DB} IS '${MARKER}';`);
  sql(DB, `CREATE SCHEMA ops; CREATE TYPE ops.event_processing_state AS ENUM ('RECEIVED','RAW_STORED','PARSED','VALIDATED','ROUTED','APPLIED','COMPLETED','NEEDS_REVIEW','DQ_HOLD','APPROVAL_REQUIRED','RETRY_WAIT','DEAD_LETTER','REJECTED','CANCELLED'); CREATE SCHEMA extensions; CREATE EXTENSION pgcrypto WITH SCHEMA extensions;`);
  const dump = sourceSchemaDump();
  result.schema_model = {
    source: 'pg_dump --schema-only from isolated local restore; selected Raw, Event, and DataHub ledger only',
    tables: 3,
    indexes: (dump.match(/CREATE (?:UNIQUE )?INDEX /g) ?? []).length,
    primary_and_unique_constraints: (dump.match(/ADD CONSTRAINT .* (?:PRIMARY KEY|UNIQUE) /g) ?? []).length,
    foreign_keys: (dump.match(/ADD CONSTRAINT .* FOREIGN KEY /g) ?? []).length,
    row_security_policies: (dump.match(/CREATE POLICY /g) ?? []).length,
    schema_sha256: createHash('sha256').update(dump, 'utf8').digest('hex'),
    data_included: false,
    modeled_extensions: ['pgcrypto'],
    modeled_business_schemas: false
  };
  sql(DB, dump, 30_000);
  const initialIdentity = assertBenchmarkDbIdentity();
  result.base = {
    database_bytes: initialIdentity.database_bytes,
    raw_rows: initialIdentity.raw_count,
    event_rows: initialIdentity.event_count,
    ledger_rows: initialIdentity.ledger_count,
    business_schemas_present: initialIdentity.business_schemas_present,
    template0_bytes: preflight.template0_bytes
  };
  const before = sample('before-fixture', 0);
  assert.equal(before.database_bytes, initialIdentity.database_bytes);

  sql(DB, createSql(1000, 0), 90_000);
  const at1k = sample('1000', 1000);
  result.stages.push({ ...at1k, delta: {
    database_bytes: at1k.database_bytes - before.database_bytes,
    raw_relation_bytes: at1k.raw_bytes - before.raw_bytes,
    events_relation_bytes: at1k.events_bytes - before.events_bytes,
    ledger_relation_bytes: at1k.ledger_bytes - before.ledger_bytes,
    bytes_per_raw_event_pair_database: Number(((at1k.database_bytes - before.database_bytes) / 1000).toFixed(2)),
    bytes_per_raw_relation_row: Number(((at1k.raw_bytes - before.raw_bytes) / 1000).toFixed(2)),
    bytes_per_event_relation_row: Number(((at1k.events_bytes - before.events_bytes) / 1000).toFixed(2))
  } });

  sql(DB, createSql(9000, 1000), 90_000);
  const at10k = sample('10000', 10_000);
  result.stages.push({ ...at10k, delta: {
    database_bytes: at10k.database_bytes - before.database_bytes,
    raw_relation_bytes: at10k.raw_bytes - before.raw_bytes,
    events_relation_bytes: at10k.events_bytes - before.events_bytes,
    ledger_relation_bytes: at10k.ledger_bytes - before.ledger_bytes,
    bytes_per_raw_event_pair_database: Number(((at10k.database_bytes - before.database_bytes) / 10_000).toFixed(2)),
    bytes_per_raw_relation_row: Number(((at10k.raw_bytes - before.raw_bytes) / 10_000).toFixed(2)),
    bytes_per_event_relation_row: Number(((at10k.events_bytes - before.events_bytes) / 10_000).toFixed(2))
  } });
  result.status = 'PASS';
} catch (error) {
  outcomeError = error;
  result.status = 'FAIL';
  result.error = String(error?.message ?? error).slice(0, 1000);
} finally {
  if (created) {
    try {
      // Only drop a database carrying this run's marker, without FORCE/CASCADE.
      const guard = json('postgres', `SELECT json_build_object(
        'exists',EXISTS(SELECT 1 FROM pg_database WHERE datname='${DB}'),
        'comment',pg_catalog.shobj_description((SELECT oid FROM pg_database WHERE datname='${DB}'),'pg_database'),
        'bytes',pg_database_size('${DB}')
      )::text;`);
      if (guard.exists) {
        assert.equal(guard.comment, MARKER, 'cleanup identity marker mismatch; refusing DROP DATABASE');
        assert.ok(guard.bytes < MAX_DB_BYTES, 'cleanup refused because benchmark DB exceeded 300 MiB bound');
        sql('postgres', `DROP DATABASE ${DB};`, 60_000);
        result.cleanup = { status: 'DROPPED_EXACT_MARKED_DATABASE', bytes_before_drop: guard.bytes, force: false, cascade: false };
      } else {
        result.cleanup = { status: 'ALREADY_ABSENT' };
      }
    } catch (error) {
      result.cleanup = { status: 'FAILED_SAFE', error: String(error?.message ?? error).slice(0, 1000) };
      if (!outcomeError) outcomeError = error;
      result.status = 'FAIL';
    }
  } else {
    result.cleanup = { status: 'NO_DATABASE_CREATED' };
  }
  try { await save(); }
  catch (error) { if (!outcomeError) outcomeError = error; result.status = 'FAIL'; }
}

if (outcomeError) {
  process.stderr.write(`structured-growth benchmark ${result.status}; private aggregate artifact: ${RESULT}; ${String(outcomeError.message ?? outcomeError).slice(0, 500)}\n`);
  process.exitCode = 1;
} else {
  process.stdout.write(`structured-growth benchmark ${result.status}; private aggregate artifact: ${RESULT}; stages=${result.stages.length}; rows=10000; elapsed_seconds=${result.elapsed_seconds}\n`);
}
