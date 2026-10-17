import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { webcrypto } from 'node:crypto';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const deployedFiles = {
  OFFICIAL: resolve(repoRoot, 'supabase/functions/line-official-webhook/index.ts'),
  DATA_BOT: resolve(repoRoot, 'supabase/functions/line-group-bot-webhook/index.ts'),
};
const functionFixturePath = resolve(repoRoot, 'tests/fixtures/myc-line-runtime-functions.json');

function loadFunction(account, options = {}) {
  const source = readFileSync(deployedFiles[account], 'utf8')
    .replace(/\r\n/g, '\n')
    .replace(/^import .*;\n/gm, '');
  const js = stripTypeScriptTypes(source, { mode: 'strip' });
  let handler;
  const rpcCalls = [];
  const uploadCalls = [];
  const responseFor = options.responseFor ?? (() => ({ decision: 'ALLOW', reason_code: null, raw_input_id: 'MYC-RAW-FIXTURE' }));
  const client = {
    rpc: async (name, args) => {
      rpcCalls.push({ name, args });
      if (name === 'line_capture_register_file' && (options.registryFailure || options.registryFailureCount > 0)) {
        if (options.registryFailureCount > 0) options.registryFailureCount--;
        return { data: null, error: { code: 'FIXTURE_FAILURE', message: 'fixture registry failure' } };
      }
      return { data: name === 'line_capture_ingest' ? responseFor(args, rpcCalls) : null, error: null };
    },
    storage: { from: bucket => ({ upload: async (objectKey, bytes, config) => {
      uploadCalls.push({ bucket, objectKey, bytes: bytes.length, config });
      if (options.rejectNonAsciiStorageKeys && /[^\x00-\x7f]/.test(objectKey)) return { error: { message: 'Invalid key: non-ASCII path component' } };
      if (options.alreadyExistsOnRepeat && uploadCalls.length > 1) return { error: { message: 'already exists' } };
      return { error: null };
    } }) },
  };
  const env = {
    SUPABASE_URL: 'https://fixture.invalid',
    SUPABASE_SERVICE_ROLE_KEY: 'fixture-service-key',
    LINE_OFFICIAL_CHANNEL_SECRET: 'fixture-official-secret',
    LINE_OFFICIAL_CHANNEL_ACCESS_TOKEN: options.accessToken ? 'fixture-official-token' : '',
    LINE_BOT_CHANNEL_SECRET: 'fixture-bot-secret',
    LINE_BOT_CHANNEL_ACCESS_TOKEN: options.accessToken ? 'fixture-bot-token' : '',
    LINE_ALLOW_CANONICAL_FALLBACK_EVENT_ID: options.allowCanonicalFallback ? 'true' : '',
  };
  const remoteCalls = [];
  const deferred = [];
  const context = vm.createContext({
    TextEncoder, TextDecoder, Uint8Array, Request, Response, URL, URLSearchParams,
    crypto: webcrypto, btoa, atob,
    console: { warn() {}, error() {} },
    createClient: () => client,
    Deno: { env: { get: name => env[name] }, serve: fn => { handler = fn; } },
    fetch: async (url, init = {}) => {
      const u = String(url);
      remoteCalls.push({ url: u, init });
      if (u.includes('/content')) {
        if (options.attachmentFailureCount > 0) {
          options.attachmentFailureCount--;
          return new Response(null, { status: options.attachmentFailureStatus ?? 503 });
        }
        return new Response(Uint8Array.from(options.attachmentBytes ?? [1, 2, 3, 4]), { headers: { 'content-type': 'image/png' } });
      }
      if (u.includes('/profile/')) return Response.json({ displayName: 'Fixture' });
      if (u.includes('/summary')) return Response.json({ groupName: 'Fixture group' });
      throw new Error(`Unexpected mocked network request: ${new URL(u).host}`);
    },
  });
  if (options.edgeRuntime) context.EdgeRuntime = { waitUntil: promise => deferred.push(promise) };
  vm.runInContext(js, context);
  return { get handler() { return handler; }, rpcCalls, uploadCalls, remoteCalls, deferred, edgeRuntimeAvailable: vm.runInContext('Boolean(globalThis.EdgeRuntime?.waitUntil)', context) };
}

async function signedRequest(f, account, payload, secretOverride) {
  const source = JSON.stringify(payload);
  const bytes = new TextEncoder().encode(source);
  const secret = secretOverride ?? (account === 'OFFICIAL' ? 'fixture-official-secret' : 'fixture-bot-secret');
  const key = await webcrypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const sig = new Uint8Array(await webcrypto.subtle.sign('HMAC', key, bytes));
  const signature = Buffer.from(sig).toString('base64');
  const response = await f.handler(new Request('https://fixture.invalid', {
    method: 'POST', headers: { 'x-line-signature': signature }, body: bytes,
  }));
  return { response, body: await response.json(), bytes };
}

const testDeployed = test;

testDeployed('bad HMAC signature is rejected before any RPC or network call', async () => {
  for (const account of ['OFFICIAL', 'DATA_BOT']) {
    const f = loadFunction(account);
    const body = new TextEncoder().encode(JSON.stringify({ events: [{ type: 'message', webhookEventId: 'fixture-event' }] }));
    const r = await f.handler(new Request('https://fixture.invalid', { method: 'POST', headers: { 'x-line-signature': 'invalid' }, body }));
    assert.equal(r.status, 401);
    assert.deepEqual(f.rpcCalls, []);
    assert.deepEqual(f.remoteCalls, []);
  }
});

testDeployed('valid signature uses account-scoped event, replay, client and source refs', async () => {
  const event = { type: 'message', webhookEventId: 'fixture-shared-provider-id', timestamp: 1_800_000_000_000, source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-message', type: 'text', text: 'synthetic fixture text' }, replyToken: 'fixture-reply-secret', authorization: 'fixture-auth-secret' };
  const captures = [];
  for (const account of ['OFFICIAL', 'DATA_BOT']) {
    const f = loadFunction(account);
    const { response, body } = await signedRequest(f, account, { events: [event] });
    assert.equal(response.status, 200);
    assert.equal(body.captured, 1);
    const args = f.rpcCalls.find(c => c.name === 'line_capture_ingest').args;
    captures.push(args);
    const expectedAccount = account === 'OFFICIAL' ? 'OFFICIAL' : 'DATA_BOT';
    const expectedSource = account === 'OFFICIAL' ? 'LINE_OA:MEYOU_CONNECT_OFFICIAL' : 'LINE_OA:MYC_DATA_BOT';
    assert.equal(args.p_event_envelope.event_id, `LINE:${expectedAccount}:fixture-shared-provider-id`);
    assert.equal(args.p_event_envelope.source_account_ref, expectedSource);
    assert.equal(args.p_security_metadata.account_key, expectedAccount);
    assert.equal(args.p_event_envelope.idempotency_key.length, 64);
    assert.equal(args.p_replay_key_hash.length, 64);
    assert.equal(args.p_client_key_hash.length, 64);
    assert.equal(args.p_payload_bytes > 0, true);
    assert.equal(args.p_event_envelope.event_type, 'channel.raw.received');
    assert.equal(args.p_event_envelope.sensitive, true);
    assert.equal(args.p_event_envelope.ai_parsed, false);
    const sanitized = args.p_event_envelope.metadata.provider_payload;
    assert.equal('replyToken' in sanitized, false);
    assert.equal('authorization' in sanitized, false);
    assert.equal(sanitized.message.text, 'synthetic fixture text');
    assert.equal(f.rpcCalls.some(c => c.name === 'register_event'), false);
    assert.deepEqual(f.rpcCalls.map(c => c.name).sort(), ['line_capture_enrich_context', 'line_capture_ingest']);
  }
  assert.notEqual(captures[0].p_event_envelope.event_id, captures[1].p_event_envelope.event_id);
  assert.notEqual(captures[0].p_client_key_hash, captures[1].p_client_key_hash);
});

testDeployed('provider redelivery retries stable identifiers and accepts explicit replay decision', async () => {
  const f = loadFunction('OFFICIAL', { responseFor: (_args, calls) => calls.filter(c => c.name === 'line_capture_ingest').length === 1
    ? { decision: 'ALLOW', raw_input_id: 'MYC-RAW-FIXTURE' }
    : { decision: 'REPLAY_DETECTED', reason_code: 'REPLAY_DETECTED', raw_input_id: 'MYC-RAW-FIXTURE' } });
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-redelivery', deliveryContext: { isRedelivery: true }, source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-message', type: 'text', text: 'synthetic retry' } }] };
  const first = await signedRequest(f, 'OFFICIAL', payload);
  const second = await signedRequest(f, 'OFFICIAL', payload);
  assert.equal(first.response.status, 200);
  assert.equal(second.response.status, 200);
  const captures = f.rpcCalls.filter(c => c.name === 'line_capture_ingest').map(c => c.args);
  assert.equal(captures.length, 2);
  assert.equal(captures[0].p_event_envelope.event_id, captures[1].p_event_envelope.event_id);
  assert.equal(captures[0].p_replay_key_hash, captures[1].p_replay_key_hash);
  assert.equal(captures[1].p_event_envelope.metadata.is_redelivery, true);
  assert.equal(f.rpcCalls.every(c => ['line_capture_ingest', 'line_capture_enrich_context'].includes(c.name)), true);
});

testDeployed('changed content under a repeated provider ID is sent to SQL with the same scoped identity for conflict review', async () => {
  const f = loadFunction('OFFICIAL');
  const first = { events: [{ type: 'message', webhookEventId: 'fixture-collision', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-message', type: 'text', text: 'synthetic original' } }] };
  const changed = { events: [{ type: 'message', webhookEventId: 'fixture-collision', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-message', type: 'text', text: 'synthetic altered' } }] };
  await signedRequest(f, 'OFFICIAL', first);
  await signedRequest(f, 'OFFICIAL', changed);
  const envelopes = f.rpcCalls.filter(c => c.name === 'line_capture_ingest').map(c => c.args.p_event_envelope);
  assert.equal(envelopes[0].event_id, envelopes[1].event_id);
  assert.notEqual(envelopes[0].metadata.provider_payload.message.text, envelopes[1].metadata.provider_payload.message.text);
  assert.equal(f.rpcCalls.filter(c => c.name === 'line_capture_ingest').length, 2);
});

testDeployed('missing stable provider ID is rejected unless canonical fallback is explicitly enabled', async () => {
  const f = loadFunction('OFFICIAL');
  const first = { events: [{ type: 'join', timestamp: 1_800_000_000_000, source: { type: 'group', groupId: 'fixture-group', userId: 'fixture-user' } }] };
  const reordered = { events: [{ source: { userId: 'fixture-user', groupId: 'fixture-group', type: 'group' }, timestamp: 1_800_000_000_000, type: 'join' }] };
  const missingId = await signedRequest(f, 'OFFICIAL', first);
  assert.equal(missingId.response.status, 400);
  assert.equal(missingId.body.failures[0].code, 'STABLE_PROVIDER_EVENT_ID_REQUIRED');
  assert.deepEqual(f.rpcCalls, []);
  const g = loadFunction('OFFICIAL', { allowCanonicalFallback: true });
  await signedRequest(g, 'OFFICIAL', first);
  await signedRequest(g, 'OFFICIAL', reordered);
  const ids = g.rpcCalls.filter(c => c.name === 'line_capture_ingest').map(c => c.args.p_event_envelope.event_id);
  assert.equal(ids[0], ids[1]);
  assert.match(ids[0], /^LINE:OFFICIAL:fallback:[0-9a-f]{64}$/);
  assert.match(ids[1], /^LINE:OFFICIAL:fallback:[0-9a-f]{64}$/);
});

testDeployed('canonical fallback omits redelivery context and flags consistently', async () => {
  const f = loadFunction('OFFICIAL', { allowCanonicalFallback: true });
  const ordinary = { events: [{ type: 'join', timestamp: 1_800_000_000_000, source: { type: 'group', groupId: 'fixture-group' } }] };
  const redelivered = { events: [{ type: 'join', timestamp: 1_800_000_000_000, source: { type: 'group', groupId: 'fixture-group' }, deliveryContext: { isRedelivery: true } }] };
  await signedRequest(f, 'OFFICIAL', ordinary);
  await signedRequest(f, 'OFFICIAL', redelivered);
  const captures = f.rpcCalls.filter(c => c.name === 'line_capture_ingest').map(c => c.args.p_event_envelope);
  assert.equal(captures[0].event_id, captures[1].event_id);
});

testDeployed('attachment content is mirrored and registered as sensitive for the source account', async () => {
  const f = loadFunction('DATA_BOT', { accessToken: true });
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-file-event', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-file-id', type: 'image', fileName: 'fixture.png' } }] };
  const { response } = await signedRequest(f, 'DATA_BOT', payload);
  assert.equal(response.status, 200);
  assert.equal(f.uploadCalls.length, 1);
  assert.equal(f.uploadCalls[0].bucket, 'raw-inbox-private');
  assert.match(f.uploadCalls[0].objectKey, /^raw\/MYC-RAW-FIXTURE\/fixture-file-id\//);
  const registry = f.rpcCalls.find(c => c.name === 'line_capture_register_file');
  assert.ok(registry);
  assert.equal(registry.args.p_source_account_ref, 'LINE_OA:MYC_DATA_BOT');
  assert.equal(registry.args.p_sensitive, true);
  assert.equal(registry.args.p_mirror_status, 'MIRRORED');
  assert.equal(registry.args.p_metadata.registry_state, 'PENDING_DOCS_WRITE_GATE');
});

testDeployed('Thai original filenames stay in registry metadata while new storage keys use ASCII checksum names', async () => {
  for (const account of ['OFFICIAL', 'DATA_BOT']) {
    const f = loadFunction(account, { accessToken: true, rejectNonAsciiStorageKeys: true });
    const originalFilename = 'เอกสารแนบ.png';
    const payload = { events: [{ type: 'message', webhookEventId: `fixture-thai-filename-${account}`, source: { type: 'user', userId: 'fixture-user' }, message: { id: `fixture-thai-file-${account}`, type: 'image', fileName: originalFilename } }] };
    const { response } = await signedRequest(f, account, payload);
    assert.equal(response.status, 200);
    assert.equal(f.uploadCalls.length, 1);
    const registry = f.rpcCalls.find(c => c.name === 'line_capture_register_file');
    assert.equal(registry.args.p_original_filename, originalFilename);
    assert.equal(registry.args.p_mirror_status, 'MIRRORED');
    assert.match(f.uploadCalls[0].objectKey, new RegExp(`^raw/MYC-RAW-FIXTURE/fixture-thai-file-${account}/${registry.args.p_checksum_sha256}\\.png$`));
    assert.doesNotMatch(f.uploadCalls[0].objectKey, /[^\x00-\x7f]/);
  }
});

testDeployed('missing LINE content token preserves raw capture, records it, and requests retry', async () => {
  const f = loadFunction('DATA_BOT');
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-file-no-token', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-file-no-token-id', type: 'image' } }] };
  const { response, body } = await signedRequest(f, 'DATA_BOT', payload);
  assert.equal(response.status, 503);
  assert.equal(body.captured, 1);
  assert.deepEqual(f.rpcCalls.map(c => c.name).sort(), ['line_capture_enrich_context', 'line_capture_ingest', 'line_capture_register_file'].sort());
  const registry = f.rpcCalls.find(c => c.name === 'line_capture_register_file');
  assert.equal(registry.args.p_mirror_status, 'SOURCE_NOT_MIRRORED');
  assert.equal(registry.args.p_metadata.error, 'LINE_ACCESS_TOKEN_UNAVAILABLE');
  assert.equal(f.uploadCalls.length, 0);
});

testDeployed('attachment registry RPC failure returns retryable HTTP failure', async () => {
  const f = loadFunction('DATA_BOT', { accessToken: true, registryFailure: true, edgeRuntime: true });
  assert.equal(f.edgeRuntimeAvailable, true);
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-unregistered-file', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-file-id', type: 'image', fileName: 'fixture.png' } }] };
  const { response } = await signedRequest(f, 'DATA_BOT', payload);
  assert.equal(f.uploadCalls.length, 1);
  assert.ok(f.rpcCalls.some(c => c.name === 'line_capture_register_file'));
  assert.equal(response.status, 503);
});

testDeployed('transient attachment failure retries on replay against the same raw ID', async () => {
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-media-download-retry', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-media-download-file', type: 'image' } }] };
  const f = loadFunction('DATA_BOT', {
    accessToken: true,
    attachmentFailureCount: 1,
    responseFor: (_args, calls) => calls.filter(c => c.name === 'line_capture_ingest').length === 1
      ? { decision: 'ALLOW', raw_input_id: 'MYC-RAW-RETRY-FIXTURE' }
      : { decision: 'REPLAY_DETECTED', reason_code: 'REPLAY_DETECTED', raw_input_id: 'MYC-RAW-RETRY-FIXTURE', media_recovery_required: true },
  });
  const first = await signedRequest(f, 'DATA_BOT', payload);
  const second = await signedRequest(f, 'DATA_BOT', payload);
  assert.equal(first.response.status, 503);
  assert.equal(second.response.status, 200);
  assert.equal(second.body.results[0].raw_input_id, 'MYC-RAW-RETRY-FIXTURE');
  assert.equal(f.rpcCalls.filter(c => c.name === 'line_capture_ingest').length, 2);
  assert.deepEqual(f.rpcCalls.filter(c => c.name === 'line_capture_register_file').map(c => c.args.p_mirror_status), ['SOURCE_NOT_MIRRORED', 'MIRRORED']);
  assert.equal(f.uploadCalls.length, 1);
});

testDeployed('multi-event batches finish later captures and enforce aggregate media budget', async () => {
  const events = ['a', 'b', 'c', 'd'].map(suffix => ({ type: 'message', webhookEventId: `fixture-budget-${suffix}`, source: { type: 'user', userId: 'fixture-user' }, message: { id: `fixture-budget-file-${suffix}`, type: 'image' } }));
  const seen = new Map();
  const f = loadFunction('OFFICIAL', {
    accessToken: true,
    attachmentBytes: new Uint8Array(9 * 1024 * 1024).fill(7),
    responseFor: args => {
      const id = args.p_event_envelope.event_id;
      const count = (seen.get(id) ?? 0) + 1;
      seen.set(id, count);
      return count === 1
        ? { decision: 'ALLOW', raw_input_id: `RAW-${id.slice(-1)}` }
        : { decision: 'REPLAY_DETECTED', reason_code: 'REPLAY_DETECTED', raw_input_id: `RAW-${id.slice(-1)}`, media_recovery_required: id.endsWith('c') || id.endsWith('d') };
    },
  });
  const first = await signedRequest(f, 'OFFICIAL', { events });
  assert.equal(first.response.status, 503);
  assert.equal(f.rpcCalls.filter(c => c.name === 'line_capture_ingest').length, 4, 'all events must capture despite the deferred attachments');
  assert.equal(f.uploadCalls.length, 2, 'the 20 MiB aggregate budget allows two 9 MiB files');
  const registryStates = f.rpcCalls.filter(c => c.name === 'line_capture_register_file').map(c => c.args.p_mirror_status);
  assert.deepEqual(registryStates, ['MIRRORED', 'MIRRORED', 'SOURCE_NOT_MIRRORED', 'SOURCE_NOT_MIRRORED']);
  const retry = await signedRequest(f, 'OFFICIAL', { events });
  assert.equal(retry.response.status, 200);
  assert.equal(f.uploadCalls.length, 4, 'retry progresses deferred files without downloading completed mirrors');
  assert.equal(f.rpcCalls.filter(c => c.name === 'line_capture_ingest').length, 8);
});

testDeployed('oversized attachment is recorded as not mirrored without upload', async () => {
  const f = loadFunction('OFFICIAL', { accessToken: true, attachmentBytes: new Uint8Array(11 * 1024 * 1024).fill(7) });
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-large-file', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-large-file-id', type: 'image' } }] };
  const { response, body } = await signedRequest(f, 'OFFICIAL', payload);
  assert.equal(response.status, 200);
  assert.equal(f.uploadCalls.length, 0);
  const registry = f.rpcCalls.find(c => c.name === 'line_capture_register_file');
  assert.equal(registry.args.p_mirror_status, 'SOURCE_NOT_MIRRORED');
  assert.equal(registry.args.p_metadata.error, 'ATTACHMENT_TOO_LARGE');
  assert.equal(body.results[0].attachment_status, 'HELD');
  assert.equal(body.results[0].attachment_reason, 'ATTACHMENT_TOO_LARGE');
});

testDeployed('permanent LINE media not-found is held with an actionable safe reason', async () => {
  const f = loadFunction('OFFICIAL', { accessToken: true, attachmentFailureCount: 1, attachmentFailureStatus: 404 });
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-media-not-found', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-media-missing-file', type: 'image' } }] };
  const { response, body } = await signedRequest(f, 'OFFICIAL', payload);
  assert.equal(response.status, 200);
  assert.equal(body.results[0].attachment_status, 'HELD');
  assert.equal(body.results[0].attachment_reason, 'LINE_CONTENT_NOT_FOUND');
  const registry = f.rpcCalls.find(c => c.name === 'line_capture_register_file');
  assert.equal(registry.args.p_mirror_status, 'SOURCE_NOT_MIRRORED');
  assert.equal(registry.args.p_metadata.error, 'LINE_CONTENT_NOT_FOUND');
});

testDeployed('oversized signed request is rejected before capture RPC', async () => {
  const f = loadFunction('OFFICIAL');
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-large', message: { type: 'text', text: 'x'.repeat(2 * 1024 * 1024) } }] };
  const { response, bytes } = await signedRequest(f, 'OFFICIAL', payload);
  assert.equal(response.status, 413);
  assert.deepEqual(f.rpcCalls, []);
});

testDeployed('multi-event batch sends whole webhook byte count for every captured event', async () => {
  const f = loadFunction('OFFICIAL');
  const payload = { events: [
    { type: 'message', webhookEventId: 'fixture-batch-a', message: { type: 'text', text: 'first' } },
    { type: 'message', webhookEventId: 'fixture-batch-b', message: { type: 'text', text: 'second' } },
  ] };
  const { response, bytes } = await signedRequest(f, 'OFFICIAL', payload);
  const captures = f.rpcCalls.filter(c => c.name === 'line_capture_ingest');
  assert.equal(response.status, 200);
  assert.equal(captures.length, 2);
  assert.equal(captures[0].args.p_payload_bytes, bytes.byteLength);
  assert.equal(captures[1].args.p_payload_bytes, bytes.byteLength);
});

test('deployed SQL snapshot shows capture lineage and existing register_event silently returns matched event', () => {
  const functions = JSON.parse(readFileSync(functionFixturePath, 'utf8'));
  const capture = functions.find(f => f.name === 'line_capture_ingest')?.definition ?? '';
  const register = functions.find(f => f.name === 'register_event')?.definition ?? '';
  assert.match(capture, /ops\.secure_ingest_material_event\s*\(/);
  assert.doesNotMatch(capture, /ops\.register_event\s*\(/);
  assert.match(capture, /source_account_ref=v_source_account_ref and provider_event_id=v_provider_event_id/);
  assert.match(register, /where source_system = p_source_system and event_id = p_event_id;[\s\S]*?if found then return v_event; end if;/);
  assert.match(register, /where idempotency_key = p_idempotency_key;[\s\S]*?if found then return v_event; end if;/);
  assert.doesNotMatch(register, /payload|envelope|content_hash/i);
});

test('deployed capture SQL lineage is backed by secure ingest and raw routing definitions', () => {
  const functions = JSON.parse(readFileSync(functionFixturePath, 'utf8'));
  const capture = functions.find(f => f.name === 'line_capture_ingest')?.definition ?? '';
  const secure = functions.find(f => f.name === 'secure_ingest_material_event')?.definition ?? '';
  const route = functions.find(f => f.name === 'route_line_raw_event_v1')?.definition ?? '';
  assert.match(capture, /ops\.secure_ingest_material_event\s*\(/);
  assert.match(capture, /ops\.complete_raw_capture_event\s*\(/);
  assert.match(secure, /ops\.ingest_material_event\s*\(/);
  assert.match(route, /candidate\.lead\.received/i);
  assert.match(route, /ops\.register_event\s*\(/);
});

test('review SQL pairs endpoint and source account and rejects changed payload under an existing key', () => {
  const sqlPath = resolve(repoRoot, 'docs/runbooks/sql/MYC_CHANNEL_INGRESS_GUARDS_REVIEW.sql');
  const sql = readFileSync(sqlPath, 'utf8');
  assert.match(sql, /line_official_webhook_test[\s\S]*?LINE_OA:MEYOU_CONNECT_OFFICIAL/);
  assert.match(sql, /line_group_bot_webhook_test[\s\S]*?LINE_OA:MYC_DATA_BOT/);
  assert.match(sql, /LINE_EVENT_ID_SCOPE_MISMATCH/);
  assert.match(sql, /LINE_EVENT_ID_PAYLOAD_CONFLICT/);
  assert.match(sql, /line_capture_canonical_json/);
  assert.match(sql, /line_capture_canonical_envelope/);
  assert.match(sql, /event_fingerprint/);
  assert.match(sql, /LINE_EXISTING_FINGERPRINT_REQUIRES_REVIEW/);
  assert.match(sql, /REVOKE ALL ON FUNCTION ops\.line_capture_canonical_json/i);
  assert.match(sql, /media_recovery_required/);
  assert.match(sql, /LINE_ATTACHMENT_CHECKSUM_CONFLICT/);
  assert.match(sql, /v_existing\.mirror_status = 'MIRRORED'/);
  assert.match(sql, /ops\.apply_failure_transition\(p_event_pk,'candidate_intake','TRANSIENT'/i);
  assert.match(sql, /ops\.apply_failure_transition\(r\.event_pk,'candidate_intake','TRANSIENT'/i);
  assert.match(sql, /RETRY_WAIT/);
  assert.match(sql, /DEAD_LETTER/);
  assert.match(sql, /processing_state NOT IN[\s\S]*?STATE_NOT_ELIGIBLE/);
  assert.match(sql, /FOR UPDATE OF e SKIP LOCKED/i);
  assert.doesNotMatch(sql, /REVOKE ALL ON FUNCTION public\.line_capture_ingest/i);
  const integration = readFileSync(resolve(repoRoot, 'tests/channel-ingress.integration.mjs'), 'utf8');
  assert.match(integration, /has_function_privilege\('anon'/i);
  assert.match(integration, /p\.proowner IS DISTINCT FROM b\.proowner/);
  assert.match(integration, /STATE_NOT_ELIGIBLE/);
  assert.match(sql, /line_capture_register_file/i);
});

test('fixture describes secure ingest, registration, enrichment and routing without invoking helper', () => {
  const functions = JSON.parse(readFileSync(functionFixturePath, 'utf8'));
  const names = functions.map(f => f.name);
  assert.equal(new Set(names).size, names.length);
  for (const name of ['secure_ingest_material_event', 'route_line_raw_event_v1', 'line_capture_register_file', 'line_capture_enrich_context']) assert.ok(names.includes(name));
  assert.equal(names.includes('invokehelper'), false);
  const complete = functions.find(f => f.name === 'complete_raw_capture_event')?.definition ?? '';
  assert.match(complete, /DOWNSTREAM_ROUTE_ERROR/);
  const scheduler = functions.find(f => f.name === 'scheduler_tick')?.definition ?? '';
  const candidateTick = functions.find(f => f.name === 'run_line_candidate_ingestion_tick')?.definition ?? '';
  assert.match(scheduler, /ops\.run_line_candidate_ingestion_tick\s*\(/);
  assert.match(candidateTick, /ops\.route_line_raw_event_v1\s*\(/);
  assert.match(candidateTick, /ops\.claim_events\('candidate_intake'/);
  assert.ok(functions.some(f => f.name === 'apply_failure_transition'));
  assert.ok(functions.some(f => f.name === 'parse_line_candidate_raw_base_v1'));
  assert.ok(functions.some(f => f.name === 'parse_line_candidate_raw_v1'));
  assert.ok(functions.filter(f => f.source?.includes('LINE user identifiers replaced')).length === 5);
});

testDeployed('oversized event batch is rejected before any write RPC', async () => {
  const f = loadFunction('OFFICIAL');
  const payload = { events: Array.from({ length: 101 }, (_, i) => ({ type: 'join', webhookEventId: `fixture-${i}` })) };
  const { response, body } = await signedRequest(f, 'OFFICIAL', payload);
  assert.equal(response.status, 413);
  assert.equal(body.error, 'EVENT_COUNT_LIMIT_EXCEEDED');
  assert.deepEqual(f.rpcCalls, []);
});

testDeployed('REPLAY_DETECTED skips enrichment and attachment mirroring', async () => {
  const f = loadFunction('DATA_BOT', { accessToken: true, responseFor: () => ({ decision: 'REPLAY_DETECTED', reason_code: 'REPLAY_DETECTED', raw_input_id: 'MYC-RAW-FIXTURE' }) });
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-replay-no-effects', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-file-id', type: 'image' } }] };
  const { response } = await signedRequest(f, 'DATA_BOT', payload);
  assert.equal(response.status, 200);
  assert.deepEqual(f.rpcCalls.map(c => c.name), ['line_capture_ingest']);
  assert.equal(f.remoteCalls.length, 0);
  assert.equal(f.uploadCalls.length, 0);
});

testDeployed('REPLAY_DETECTED retries missing media registry without enrichment and skips completed media', async () => {
  const payload = { events: [{ type: 'message', webhookEventId: 'fixture-media-recovery', source: { type: 'user', userId: 'fixture-user' }, message: { id: 'fixture-media-recovery-id', type: 'image' } }] };
  const recovery = loadFunction('DATA_BOT', {
    accessToken: true,
    responseFor: (_args, calls) => calls.filter(c => c.name === 'line_capture_ingest').length === 1
      ? { decision: 'ALLOW', raw_input_id: 'MYC-RAW-FIXTURE' }
      : { decision: 'REPLAY_DETECTED', reason_code: 'REPLAY_DETECTED', raw_input_id: 'MYC-RAW-FIXTURE', media_recovery_required: true },
    registryFailureCount: 1,
    alreadyExistsOnRepeat: true,
  });
  const first = await signedRequest(recovery, 'DATA_BOT', payload);
  const second = await signedRequest(recovery, 'DATA_BOT', payload);
  assert.equal(first.response.status, 503);
  assert.equal(second.response.status, 200);
  assert.equal(second.body.results[0].raw_input_id, 'MYC-RAW-FIXTURE');
  assert.equal(recovery.rpcCalls.filter(c => c.name === 'line_capture_ingest').length, 2);
  assert.equal(recovery.rpcCalls.filter(c => c.name === 'line_capture_enrich_context').length, 1);
  assert.equal(recovery.rpcCalls.filter(c => c.name === 'line_capture_register_file').length, 2);
  assert.equal(recovery.rpcCalls.filter(c => c.name === 'line_capture_register_file')[1].args.p_mirror_status, 'MIRRORED');
  assert.equal(recovery.uploadCalls.length, 2, 'the retry must tolerate storage already containing the attachment');

  const completed = loadFunction('DATA_BOT', { accessToken: true, responseFor: () => ({ decision: 'REPLAY_DETECTED', reason_code: 'REPLAY_DETECTED', raw_input_id: 'MYC-RAW-FIXTURE', media_recovery_required: false }) });
  const completeResult = await signedRequest(completed, 'DATA_BOT', payload);
  assert.equal(completeResult.response.status, 200);
  assert.deepEqual(completed.rpcCalls.map(c => c.name), ['line_capture_ingest']);
  assert.equal(completed.remoteCalls.length, 0);
});


