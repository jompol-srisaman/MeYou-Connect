import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const ACCOUNT_KEY = "OFFICIAL";
const SOURCE_ACCOUNT_REF = "LINE_OA:MEYOU_CONNECT_OFFICIAL";
const ENDPOINT_KEY = "line_official_webhook_test";
const SECRET_ENV = "LINE_OFFICIAL_CHANNEL_SECRET";
const TOKEN_ENV = "LINE_OFFICIAL_CHANNEL_ACCESS_TOKEN";
const RAW_BUCKET = "raw-inbox-private";
const MAX_REQUEST_BYTES = 2 * 1024 * 1024;
const MAX_EVENT_COUNT = 100;
const MAX_ATTACHMENT_BYTES = 10 * 1024 * 1024;
const MAX_BATCH_ATTACHMENT_BYTES = 20 * 1024 * 1024;
const FUNCTION_VERSION = "line-capture-v1.1-rpc";

type ProviderRecord = Record<string, unknown>;
type LineSource = ProviderRecord & {
  type?: string;
  userId?: string;
  groupId?: string;
  roomId?: string;
};
type LineMessage = ProviderRecord & {
  id?: string;
  type?: string;
  text?: string;
  fileName?: string;
  fileSize?: number;
  title?: string;
  address?: string;
  latitude?: number;
  longitude?: number;
  packageId?: string;
  stickerId?: string;
};
type LineEvent = ProviderRecord & {
  type?: string;
  webhookEventId?: string;
  timestamp?: number;
  source?: LineSource;
  message?: LineMessage;
  deliveryContext?: ProviderRecord & { isRedelivery?: boolean };
};
type LineProfile = ProviderRecord & {
  displayName?: string;
  groupName?: string;
  pictureUrl?: string;
  statusMessage?: string;
  language?: string;
};
type LineThread = { displayName?: string | null; pictureUrl?: string | null };
type AttachmentFields = {
  originalFilename?: string | null;
  contentType?: string | null;
  sizeBytes?: number | null;
  checksum?: string | null;
  metadata?: ProviderRecord;
};
type MirrorStatus = "SOURCE_NOT_MIRRORED" | "MIRRORED";
type BoundedBody = { tooLarge: true; bytes: null } | { tooLarge: false; bytes: Uint8Array };
class AttachmentRegistryError extends Error {
  readonly mediaBytesUsed: number;
  constructor(mediaBytesUsed: number) {
    super("ATTACHMENT_REGISTRY_RETRY_REQUIRED");
    this.mediaBytesUsed = mediaBytesUsed;
  }
}
type EdgeRuntimeGlobal = typeof globalThis & {
  EdgeRuntime?: { waitUntil?: (promise: Promise<unknown>) => void };
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
let SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
if (!SERVICE_KEY) {
  try {
    SERVICE_KEY = JSON.parse(Deno.env.get("SUPABASE_SECRET_KEYS") ?? "{}").default ?? "";
  } catch {
    SERVICE_KEY = "";
  }
}
const supabaseAdmin = SUPABASE_URL && SERVICE_KEY
  ? createClient(SUPABASE_URL, SERVICE_KEY, { auth: { persistSession: false, autoRefreshToken: false } })
  : null;

const enc = new TextEncoder();
const dec = new TextDecoder();

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

async function sha256Hex(input: string | Uint8Array): Promise<string> {
  const bytes = typeof input === "string" ? enc.encode(input) : input;
  const owned = new ArrayBuffer(bytes.byteLength);
  new Uint8Array(owned).set(bytes);
  const digest = new Uint8Array(await crypto.subtle.digest("SHA-256", owned));
  return Array.from(digest).map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function verifyLineSignature(body: Uint8Array, secret: string, signatureB64: string | null): Promise<boolean> {
  if (!secret || !signatureB64) return false;
  try {
    const key = await crypto.subtle.importKey(
      "raw",
      enc.encode(secret),
      { name: "HMAC", hash: "SHA-256" },
      false,
      ["verify"],
    );
    const sig = Uint8Array.from(atob(signatureB64), (c) => c.charCodeAt(0));
    const ownedSignature = new ArrayBuffer(sig.byteLength);
    new Uint8Array(ownedSignature).set(sig);
    const ownedBody = new ArrayBuffer(body.byteLength);
    new Uint8Array(ownedBody).set(body);
    return await crypto.subtle.verify("HMAC", key, ownedSignature, ownedBody);
  } catch {
    return false;
  }
}

function stripProviderSecrets(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(stripProviderSecrets);
  if (!value || typeof value !== "object") return value;
  const out: ProviderRecord = {};
  for (const [k, v] of Object.entries(value)) {
    if (["replytoken", "quotetoken", "accesstoken", "refreshtoken", "authorization"].includes(k.toLowerCase())) continue;
    out[k] = stripProviderSecrets(v);
  }
  return out;
}

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (!value || typeof value !== "object") return value;
  const record = value as ProviderRecord;
  const result: ProviderRecord = {};
  for (const key of Object.keys(record).sort()) {
    if (["replytoken", "quotetoken", "accesstoken", "refreshtoken", "authorization", "deliverycontext", "delivery_context", "isredelivery", "is_redelivery"].includes(key.toLowerCase())) continue;
    result[key] = canonicalize(record[key]);
  }
  return result;
}

async function readBoundedBody(req: Request, limit: number): Promise<BoundedBody> {
  const reader = req.body?.getReader();
  if (!reader) return { bytes: new Uint8Array(), tooLarge: false };
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel();
        return { bytes: null, tooLarge: true };
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return { bytes, tooLarge: false };
}

async function readBoundedResponse(response: Response, limit: number): Promise<Uint8Array> {
  const reader = response.body?.getReader();
  if (!reader) return new Uint8Array();
  const chunks: Uint8Array[] = [];
  let total = 0;
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      if (!value) continue;
      total += value.byteLength;
      if (total > limit) {
        await reader.cancel();
        throw new Error("ATTACHMENT_TOO_LARGE");
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

function sourceInfo(event: LineEvent): { source: LineSource; type: string; threadRef: string | null; userId: string | null } {
  const source = event?.source ?? {};
  const type = String(source.type ?? "unknown");
  const threadRef = source.groupId ?? source.roomId ?? source.userId ?? null;
  const userId = source.userId ?? null;
  return { source, type, threadRef, userId };
}

function contentType(event: LineEvent): string {
  if (event?.type === "message") return `LINE_${String(event?.message?.type ?? "UNKNOWN").toUpperCase()}`;
  return `LINE_EVENT_${String(event?.type ?? "UNKNOWN").toUpperCase()}`;
}

function rawSummary(event: LineEvent): string {
  if (event?.type !== "message") return `[LINE EVENT] ${String(event?.type ?? "unknown")}`;
  const m = event?.message ?? {};
  switch (m.type) {
    case "text": return String(m.text ?? "");
    case "file": return `[FILE] ${String(m.fileName ?? "file")} (${String(m.fileSize ?? "?")} bytes)`;
    case "location": return `[LOCATION] ${String(m.title ?? "")} ${String(m.address ?? "")} (${String(m.latitude ?? "")},${String(m.longitude ?? "")})`;
    case "sticker": return `[STICKER] package=${String(m.packageId ?? "")} sticker=${String(m.stickerId ?? "")}`;
    case "image": return "[IMAGE]";
    case "video": return "[VIDEO]";
    case "audio": return "[AUDIO]";
    default: return `[MESSAGE] ${String(m.type ?? "unknown")}`;
  }
}

function safeName(name: unknown): string {
  return String(name ?? "file").replace(/[\\/\u0000\r\n]/g, "_").slice(0, 180) || "file";
}

function extensionForMime(mime: string | null | undefined): string {
  const map: Record<string, string> = {
    "image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp",
    "video/mp4": "mp4", "audio/m4a": "m4a", "audio/mp4": "m4a", "audio/mpeg": "mp3",
    "application/pdf": "pdf",
  };
  return map[String(mime ?? "").split(";")[0].trim().toLowerCase()] ?? "bin";
}

async function rpc(name: string, args: ProviderRecord): Promise<unknown> {
  if (!supabaseAdmin) throw new Error("SUPABASE_ADMIN_NOT_CONFIGURED");
  const { data, error } = await supabaseAdmin.rpc(name, args);
  if (error) throw new Error(`${name}:${error.code ?? "ERR"}`);
  return data;
}

async function fetchProfile(event: LineEvent, accessToken: string): Promise<LineProfile | null> {
  const { source, type, userId } = sourceInfo(event);
  if (!accessToken || !userId) return null;
  let url = `https://api.line.me/v2/bot/profile/${encodeURIComponent(userId)}`;
  if (type === "group" && source.groupId) {
    url = `https://api.line.me/v2/bot/group/${encodeURIComponent(source.groupId)}/member/${encodeURIComponent(userId)}`;
  } else if (type === "room" && source.roomId) {
    url = `https://api.line.me/v2/bot/room/${encodeURIComponent(source.roomId)}/member/${encodeURIComponent(userId)}`;
  }
  try {
    const r = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } });
    if (!r.ok) return null;
    return await r.json() as LineProfile;
  } catch {
    return null;
  }
}

async function fetchThread(event: LineEvent, accessToken: string, profile: LineProfile | null): Promise<LineThread | null> {
  const { source, type, threadRef } = sourceInfo(event);
  if (!threadRef) return null;
  if (type === "group" && source.groupId && accessToken) {
    try {
      const r = await fetch(`https://api.line.me/v2/bot/group/${encodeURIComponent(source.groupId)}/summary`, {
        headers: { authorization: `Bearer ${accessToken}` },
      });
      if (r.ok) {
        const g = await r.json() as LineProfile;
        return { displayName: g.groupName ?? null, pictureUrl: g.pictureUrl ?? null };
      }
    } catch {
    }
  }
  if (type === "user" && profile) {
    return { displayName: profile.displayName ?? null, pictureUrl: profile.pictureUrl ?? null };
  }
  return null;
}

async function enrichContext(event: LineEvent, rawInputId: string | null, occurredAt: string, accessToken: string): Promise<void> {
  if (!rawInputId) return;
  const { type, threadRef, userId } = sourceInfo(event);
  const profile = await fetchProfile(event, accessToken);
  const thread = await fetchThread(event, accessToken, profile);
  try {
    await rpc("line_capture_enrich_context", {
      p_raw_input_id: rawInputId,
      p_source_account_ref: SOURCE_ACCOUNT_REF,
      p_occurred_at: occurredAt,
      p_identity_ref: userId,
      p_identity_type: "USER",
      p_identity_display_name: profile?.displayName ?? null,
      p_identity_picture_url: profile?.pictureUrl ?? null,
      p_identity_status_message: profile?.statusMessage ?? null,
      p_identity_language: profile?.language ?? null,
      p_thread_ref: threadRef,
      p_thread_type: String(type).toUpperCase(),
      p_thread_display_name: thread?.displayName ?? null,
      p_thread_picture_url: thread?.pictureUrl ?? null,
      p_metadata: { source_type: type, account_key: ACCOUNT_KEY },
    });
  } catch (err) {
    console.warn("line_context_enrich_failed", { account: ACCOUNT_KEY, reason: "RPC_FAILED" });
  }
}

async function registerFile(rawInputId: string, m: LineMessage, status: MirrorStatus, fields: AttachmentFields): Promise<void> {
  try {
    await rpc("line_capture_register_file", {
      p_raw_input_id: rawInputId,
      p_source_account_ref: SOURCE_ACCOUNT_REF,
      p_provider_file_ref: String(m.id),
      p_original_filename: fields.originalFilename ?? null,
      p_content_type: fields.contentType ?? null,
      p_size_bytes: fields.sizeBytes ?? null,
      p_checksum_sha256: fields.checksum ?? null,
      p_mirror_status: status,
      p_sensitive: true,
      p_metadata: fields.metadata ?? {},
    });
  } catch {
    throw new Error("ATTACHMENT_REGISTRY_RETRY_REQUIRED");
  }
}

async function recordFile(rawInputId: string, m: LineMessage, status: MirrorStatus, fields: AttachmentFields, mediaBytesUsed: number): Promise<void> {
  try {
    await registerFile(rawInputId, m, status, fields);
  } catch {
    throw new AttachmentRegistryError(mediaBytesUsed);
  }
}

type AttachmentOutcome = { retryable: boolean; bytesUsed: number; status?: "MIRRORED" | "DEFERRED" | "HELD"; reason?: string };

async function mirrorAttachment(event: LineEvent, rawInputId: string | null, accessToken: string, remainingBatchBytes: number): Promise<AttachmentOutcome> {
  if (!supabaseAdmin || !rawInputId || event?.type !== "message") return { retryable: false, bytesUsed: 0 };
  const m = event?.message ?? {};
  if (typeof m.type !== "string" || !["image", "video", "audio", "file"].includes(m.type) || !m.id) return { retryable: false, bytesUsed: 0 };
  if (!accessToken) {
    await recordFile(rawInputId, m, "SOURCE_NOT_MIRRORED", {
      originalFilename: m.fileName ?? null,
      contentType: m.type ?? null,
      sizeBytes: m.fileSize ?? null,
      checksum: null,
      metadata: { error: "LINE_ACCESS_TOKEN_UNAVAILABLE", message_type: m.type },
    }, 0);
    console.warn("attachment_not_mirrored", { account: ACCOUNT_KEY, message_type: m.type, reason: "LINE_ACCESS_TOKEN_UNAVAILABLE" });
    return { retryable: true, bytesUsed: 0, status: "DEFERRED", reason: "LINE_ACCESS_TOKEN_UNAVAILABLE" };
  }
  if (remainingBatchBytes <= 0) {
    await recordFile(rawInputId, m, "SOURCE_NOT_MIRRORED", {
      originalFilename: m.fileName ?? null, contentType: m.type ?? null, sizeBytes: m.fileSize ?? null,
      checksum: null, metadata: { error: "BATCH_MEDIA_BUDGET_DEFERRED", message_type: m.type },
    }, 0);
    return { retryable: true, bytesUsed: 0, status: "DEFERRED", reason: "BATCH_MEDIA_BUDGET_DEFERRED" };
  }
  let bytes: Uint8Array | null = null;
  let mime = "application/octet-stream";
  let checksum;
  let original;
  let objectPath;
  let mirrorError: string | null = null;
  let retryable = false;
  let bytesUsed = 0;
  try {
    const r = await fetch(`https://api-data.line.me/v2/bot/message/${encodeURIComponent(m.id)}/content`, {
      headers: { authorization: `Bearer ${accessToken}` },
    });
    if (!r.ok) {
      if (r.status === 404 || r.status === 410) mirrorError = "LINE_CONTENT_NOT_FOUND";
      else { mirrorError = "ATTACHMENT_MIRROR_FAILED"; retryable = true; }
      throw new Error(mirrorError);
    }
    const streamLimit = Math.min(MAX_ATTACHMENT_BYTES, remainingBatchBytes);
    bytes = await readBoundedResponse(r, streamLimit);
    bytesUsed = bytes.byteLength;
    mime = r.headers.get("content-type")?.split(";")[0]?.trim() || mime;
    checksum = await sha256Hex(bytes);
    original = safeName(m.fileName ?? `${m.id}.${extensionForMime(mime)}`);
    const storedName = `${checksum}.${extensionForMime(mime)}`;
    objectPath = `raw/${rawInputId}/${m.id}/${storedName}`;
    const { error: uploadError } = await supabaseAdmin.storage.from(RAW_BUCKET).upload(objectPath, bytes, {
      contentType: mime,
      upsert: false,
    });
    if (uploadError && !String(uploadError.message).toLowerCase().includes("already exists")) {
      retryable = true;
      throw uploadError;
    }
  } catch (err) {
    if (!mirrorError) {
      if (err instanceof Error && err.message === "ATTACHMENT_TOO_LARGE") {
        mirrorError = remainingBatchBytes < MAX_ATTACHMENT_BYTES ? "BATCH_MEDIA_BUDGET_DEFERRED" : "ATTACHMENT_TOO_LARGE";
        retryable = mirrorError === "BATCH_MEDIA_BUDGET_DEFERRED";
        if (retryable) bytesUsed = remainingBatchBytes;
      } else {
        mirrorError = "ATTACHMENT_MIRROR_FAILED";
        retryable = true;
      }
    }
  }
  if (mirrorError) {
    await recordFile(rawInputId, m, "SOURCE_NOT_MIRRORED", {
      originalFilename: m.fileName ?? null,
      contentType: m.type ?? null,
      sizeBytes: m.fileSize ?? null,
      checksum: null,
      metadata: { error: mirrorError, message_type: m.type },
    }, bytesUsed);
    console.warn("attachment_not_mirrored", { account: ACCOUNT_KEY, message_type: m.type, reason: mirrorError });
    return { retryable, bytesUsed, status: retryable ? "DEFERRED" : "HELD", reason: mirrorError };
  }
  if (!bytes || !checksum || !original || !objectPath) {
    await recordFile(rawInputId, m, "SOURCE_NOT_MIRRORED", {
      originalFilename: m.fileName ?? null,
      contentType: m.type ?? null,
      sizeBytes: m.fileSize ?? null,
      checksum: null,
      metadata: { error: "ATTACHMENT_MIRROR_FAILED", message_type: m.type },
    }, bytesUsed);
    return { retryable: true, bytesUsed, status: "DEFERRED", reason: "ATTACHMENT_MIRROR_FAILED" };
  }
  await recordFile(rawInputId, m, "MIRRORED", {
    originalFilename: original,
    contentType: mime,
    sizeBytes: bytes.length,
    checksum,
    metadata: { storage_bucket: RAW_BUCKET, object_key: objectPath, registry_state: "PENDING_DOCS_WRITE_GATE", message_type: m.type },
  }, bytesUsed);
  return { retryable: false, bytesUsed, status: "MIRRORED" };
}

async function ingestEvent(event: LineEvent, payloadBytes: number, receivedAt: Date, accessToken: string, remainingBatchBytes: number): Promise<ProviderRecord> {
  const sanitized = stripProviderSecrets(event);
  const stableProviderId = event?.webhookEventId ?? event?.message?.id;
  let providerEventId;
  if (stableProviderId !== undefined && stableProviderId !== null && String(stableProviderId).trim()) {
    providerEventId = String(stableProviderId);
  } else if (Deno.env.get("LINE_ALLOW_CANONICAL_FALLBACK_EVENT_ID") === "true") {
    providerEventId = `fallback:${await sha256Hex(JSON.stringify(canonicalize(sanitized)) ?? "null")}`;
  } else {
    throw new Error("STABLE_PROVIDER_EVENT_ID_REQUIRED");
  }
  const eventId = `LINE:${ACCOUNT_KEY}:${providerEventId}`;
  const eventHash = await sha256Hex(eventId);
  const idempotencyKey = await sha256Hex(`IDEMPOTENCY|${eventId}`);
  const replayHash = await sha256Hex(`REPLAY|${eventId}`);
  const clientHash = await sha256Hex(`LINE_CLIENT|${ACCOUNT_KEY}`);
  const traceId = `TR-${eventHash.slice(0, 32)}`;
  const { type, threadRef, userId } = sourceInfo(event);
  const messageId = event?.message?.id ? String(event.message.id) : null;
  const occurredAt = event?.timestamp ? new Date(Number(event.timestamp)).toISOString() : receivedAt.toISOString();
  const originalRef = `line://${ACCOUNT_KEY}/${threadRef ?? "unknown"}/${messageId ?? providerEventId}`;
  const envelope = {
    schema_version: "2.1",
    source_system: "LINE",
    channel: "LINE",
    event_id: eventId,
    idempotency_key: idempotencyKey,
    trace_id: traceId,
    event_type: "channel.raw.received",
    occurred_at: occurredAt,
    sender_type: `LINE_${String(type).toUpperCase()}`,
    content_type: contentType(event),
    original_ref: originalRef,
    sender_ref: userId,
    source_account_ref: SOURCE_ACCOUNT_REF,
    thread_id: threadRef,
    message_id: messageId,
    raw_summary: rawSummary(event),
    ai_parsed: false,
    sensitive: true,
    metadata: {
      provider: "LINE",
      account_key: ACCOUNT_KEY,
      line_event_type: event?.type ?? "unknown",
      source_type: type,
      is_redelivery: Boolean(event?.deliveryContext?.isRedelivery),
      provider_payload: sanitized,
    },
  };
  const securityMetadata = {
    provider: "LINE",
    account_key: ACCOUNT_KEY,
    function_version: FUNCTION_VERSION,
    is_redelivery: Boolean(event?.deliveryContext?.isRedelivery),
  };
  const requestId = `REQ-LINE-${ACCOUNT_KEY}-${eventHash.slice(0, 28)}`;
  const result = await rpc("line_capture_ingest", {
    p_endpoint_key: ENDPOINT_KEY,
    p_request_id: requestId,
    p_request_timestamp: receivedAt.toISOString(),
    p_payload_bytes: payloadBytes,
    p_replay_key_hash: replayHash,
    p_client_key_hash: clientHash,
    p_event_envelope: envelope,
    p_security_metadata: securityMetadata,
  });
  const capture = result && typeof result === "object" ? result as ProviderRecord : {};
  const decision = typeof capture.decision === "string" ? capture.decision : "DENY";
  const reason = typeof capture.reason_code === "string" ? capture.reason_code : null;
  if (decision !== "ALLOW" && reason !== "REPLAY_DETECTED") {
    throw new Error(`INGRESS_${reason ?? decision}`);
  }
  const rawInputId = typeof capture.raw_input_id === "string" ? capture.raw_input_id : null;
  const isReplay = reason === "REPLAY_DETECTED" || decision === "REPLAY_DETECTED";
  if (!isReplay) {
    const enrichment = enrichContext(event, rawInputId, occurredAt, accessToken);
    const edgeRuntime = globalThis as EdgeRuntimeGlobal;
    if (edgeRuntime.EdgeRuntime?.waitUntil) edgeRuntime.EdgeRuntime.waitUntil(enrichment);
    else await enrichment;
  }
  let media: AttachmentOutcome = { retryable: false, bytesUsed: 0 };
  if (!isReplay || capture.media_recovery_required === true) {
    media = await mirrorAttachment(event, rawInputId, accessToken, remainingBatchBytes);
  }
  return {
    raw_input_id: rawInputId,
    event_id: eventId,
    decision,
    reason_code: reason,
    retryable: media.retryable,
    media_bytes_used: media.bytesUsed,
    attachment_status: media.status ?? null,
    attachment_reason: media.reason ?? null,
  };
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return jsonResponse({ ok: false, error: "METHOD_NOT_ALLOWED" }, 405);
  const channelSecret = Deno.env.get(SECRET_ENV) ?? "";
  const accessToken = Deno.env.get(TOKEN_ENV) ?? "";
  if (!channelSecret) return jsonResponse({ ok: false, error: "LINE_CHANNEL_SECRET_NOT_CONFIGURED" }, 503);
  if (!supabaseAdmin) return jsonResponse({ ok: false, error: "SUPABASE_ADMIN_NOT_CONFIGURED" }, 503);

  const read = await readBoundedBody(req, MAX_REQUEST_BYTES);
  if (read.tooLarge) return jsonResponse({ ok: false, error: "PAYLOAD_TOO_LARGE" }, 413);
  const body = read.bytes;
  const signature = req.headers.get("x-line-signature");
  if (!(await verifyLineSignature(body, channelSecret, signature))) {
    console.warn("line_signature_rejected", { account: ACCOUNT_KEY });
    return jsonResponse({ ok: false, error: "INVALID_SIGNATURE" }, 401);
  }

  let payload: unknown;
  try {
    payload = JSON.parse(dec.decode(body));
  } catch {
    return jsonResponse({ ok: false, error: "INVALID_JSON" }, 400);
  }
  const payloadRecord = payload && typeof payload === "object" ? payload as ProviderRecord : {};
  const events = Array.isArray(payloadRecord.events) ? payloadRecord.events as LineEvent[] : [];
  if (events.length === 0) return jsonResponse({ ok: true, verified: true, events: 0 });
  if (events.length > MAX_EVENT_COUNT) return jsonResponse({ ok: false, error: "EVENT_COUNT_LIMIT_EXCEEDED" }, 413);

  const receivedAt = new Date();
  const results: ProviderRecord[] = [];
  const failures: { index: number; code: string; status: number }[] = [];
  let mediaBytesRemaining = MAX_BATCH_ATTACHMENT_BYTES;
  for (let index = 0; index < events.length; index++) {
    try {
      const result = await ingestEvent(events[index], body.byteLength, receivedAt, accessToken, mediaBytesRemaining);
      const mediaUsed = typeof result.media_bytes_used === "number" ? result.media_bytes_used : 0;
      mediaBytesRemaining = Math.max(0, mediaBytesRemaining - mediaUsed);
      if (result.retryable === true) failures.push({ index, code: String(result.attachment_reason ?? "ATTACHMENT_RETRY_REQUIRED"), status: 503 });
      results.push(result);
    } catch (err) {
      const code = err instanceof Error ? err.message : "INGEST_FAILED";
      if (err instanceof AttachmentRegistryError) mediaBytesRemaining = Math.max(0, mediaBytesRemaining - err.mediaBytesUsed);
      console.warn("line_webhook_ingest_failed", { account: ACCOUNT_KEY, error: code.split(":", 2)[0] });
      const status = code === "STABLE_PROVIDER_EVENT_ID_REQUIRED" ? 400
        : code === "INGRESS_LINE_EVENT_ID_PAYLOAD_CONFLICT" ? 409
        : 500;
      failures.push({ index, code: status === 409 ? "EVENT_PAYLOAD_CONFLICT" : status === 500 ? "INGEST_FAILED" : code, status });
    }
  }
  if (failures.length) {
    const status = failures.some(f => f.status >= 500) ? 503 : failures[0].status;
    return jsonResponse({ ok: false, captured: results.length, results, failures }, status);
  }
  return jsonResponse({ ok: true, captured: results.length, results });
});
