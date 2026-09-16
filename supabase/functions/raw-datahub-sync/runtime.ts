import "jsr:@supabase/functions-js/edge-runtime.d.ts";

type Json = Record<string, unknown>;
type RawSyncRow = {
  stable_external_key: string;
  raw_input_id: string;
  source_system: string;
  source_account_ref: string;
  source_received_at: string;
  payload_checksum: string;
  attempt_count: number;
  channel: string | null;
  sender_type: string | null;
  sender_ref: string | null;
  content_type: string | null;
  original_ref: string | null;
  raw_summary: string | null;
  classification: string | null;
  entity_type: string | null;
  entity_id: string | null;
  processing_status: string | null;
  thread_id: string | null;
  message_id: string | null;
  consent_signal: string | null;
};

type SourceBacklog = {
  source_system: string;
  source_account_ref: string;
  unstaged_count: number;
};

const PROJECT_REF = "pgjmxdeafzogzsyawejs";
const DATA_HUB_ID = Deno.env.get("MYC_DATA_HUB_SPREADSHEET_ID") ?? "1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc";
const TARGET_SHEET = "19_Raw_Input_Log";
const VERSION = "raw-datahub-sync-v1";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? `https://${PROJECT_REF}.supabase.co`;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const normalizeHeader = (value: unknown) => String(value ?? "").trim().replace(/\s+/g, " ").toLocaleLowerCase("th-TH");

const HEADER_ALIASES: Record<string, string[]> = {
  raw_input_id: ["Raw Input ID", "Raw ID", "raw_input_id", "รหัส Raw", "รหัสข้อมูลดิบ"],
  received_at: ["Received At", "received_at", "รับเมื่อ", "วันที่รับข้อมูล", "เวลาได้รับ"],
  source_system: ["Source System", "source_system", "ระบบต้นทาง", "แหล่งระบบ"],
  source_account_ref: ["Source Account Ref", "source_account_ref", "บัญชีต้นทาง", "Source Account"],
  channel: ["Channel", "channel", "ช่องทาง"],
  sender_type: ["Sender Type", "sender_type", "ประเภทผู้ส่ง"],
  sender_ref: ["Sender Ref", "sender_ref", "ผู้ส่ง Ref", "รหัสผู้ส่ง"],
  content_type: ["Content Type", "content_type", "ประเภทเนื้อหา"],
  original_ref: ["Original Ref", "original_ref", "อ้างอิงต้นฉบับ"],
  raw_summary: ["Raw Summary", "raw_summary", "สรุป Raw", "ข้อความดิบ", "สรุปข้อมูลดิบ"],
  classification: ["Classification", "classification", "การจำแนก"],
  entity_type: ["Entity Type", "entity_type", "ประเภท Entity"],
  entity_id: ["Entity ID", "entity_id", "รหัส Entity"],
  processing_status: ["Processing Status", "processing_status", "สถานะประมวลผล"],
  thread_id: ["Thread ID", "thread_id", "รหัส Thread", "เธรด"],
  message_id: ["Message ID", "message_id", "รหัสข้อความ"],
  consent_signal: ["Consent Signal", "consent_signal", "สัญญาณ Consent"],
  stable_external_key: ["Stable External Key", "stable_external_key", "Idempotency Key"],
  payload_checksum: ["Payload Checksum", "payload_checksum", "Checksum"],
};

const REQUIRED_TARGET_FIELDS = ["raw_input_id", "received_at", "source_system", "source_account_ref", "thread_id"];

function b64url(bytes: Uint8Array | string) {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let binary = "";
  for (const b of raw) binary += String.fromCharCode(b);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}

function pemToPkcs8(pem: string) {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s+/g, "");
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

function googleCredentials() {
  const explicitToken = Deno.env.get("GOOGLE_SHEETS_ACCESS_TOKEN");
  if (explicitToken) return { explicitToken };

  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (raw) {
    try {
      const parsed = JSON.parse(raw) as { client_email?: string; private_key?: string };
      if (parsed.client_email && parsed.private_key) return { clientEmail: parsed.client_email, privateKey: parsed.private_key };
    } catch {
      throw new Error("GOOGLE_DATA_HUB_AUTH_INVALID");
    }
  }

  const clientEmail = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL");
  const privateKey = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  if (clientEmail && privateKey) return { clientEmail, privateKey };
  return null;
}

async function googleAccessToken() {
  const credentials = googleCredentials();
  if (!credentials) throw new Error("GOOGLE_DATA_HUB_AUTH_NOT_CONFIGURED");
  if ("explicitToken" in credentials && credentials.explicitToken) return credentials.explicitToken;

  const now = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = b64url(JSON.stringify({
    iss: credentials.clientEmail,
    scope: "https://www.googleapis.com/auth/spreadsheets",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToPkcs8(credentials.privateKey!),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned)));
  const assertion = `${unsigned}.${b64url(signature)}`;

  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion }),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 300);
    throw new Error(`GOOGLE_DATA_HUB_AUTH_FAILED:${response.status}:${detail}`);
  }
  const body = await response.json() as { access_token?: string };
  if (!body.access_token) throw new Error("GOOGLE_DATA_HUB_AUTH_FAILED:NO_ACCESS_TOKEN");
  return body.access_token;
}

async function supabaseRpc<T>(name: string, body: Json): Promise<T> {
  if (!SERVICE_KEY) throw new Error("SUPABASE_SERVICE_ROLE_KEY_NOT_CONFIGURED");
  const response = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: SERVICE_KEY,
      authorization: `Bearer ${SERVICE_KEY}`,
      "content-type": "application/json",
      "content-profile": "ops",
      "accept-profile": "ops",
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`SUPABASE_RPC_FAILED:${name}:${response.status}:${detail}`);
  }
  return await response.json() as T;
}

async function supabaseGet<T>(resource: string, query: string): Promise<T> {
  if (!SERVICE_KEY) throw new Error("SUPABASE_SERVICE_ROLE_KEY_NOT_CONFIGURED");
  const response = await fetch(`${SUPABASE_URL}/rest/v1/${resource}?${query}`, {
    headers: {
      apikey: SERVICE_KEY,
      authorization: `Bearer ${SERVICE_KEY}`,
      "accept-profile": "ops",
      accept: "application/json",
    },
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`SUPABASE_READ_FAILED:${resource}:${response.status}:${detail}`);
  }
  return await response.json() as T;
}

async function sheetValues(token: string, a1: string) {
  const endpoint = `https://sheets.googleapis.com/v4/spreadsheets/${DATA_HUB_ID}/values/${encodeURIComponent(a1)}?majorDimension=ROWS&valueRenderOption=UNFORMATTED_VALUE`;
  const response = await fetch(endpoint, { headers: { authorization: `Bearer ${token}` } });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`GOOGLE_DATA_HUB_READ_FAILED:${response.status}:${detail}`);
  }
  const body = await response.json() as { values?: unknown[][] };
  return body.values ?? [];
}

async function appendSheetRow(token: string, values: unknown[]) {
  const range = `${TARGET_SHEET}!A:ZZ`;
  const endpoint = `https://sheets.googleapis.com/v4/spreadsheets/${DATA_HUB_ID}/values/${encodeURIComponent(range)}:append?valueInputOption=RAW&insertDataOption=INSERT_ROWS&includeValuesInResponse=true`;
  const response = await fetch(endpoint, {
    method: "POST",
    headers: { authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ majorDimension: "ROWS", values: [values] }),
  });
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`GOOGLE_DATA_HUB_APPEND_FAILED:${response.status}:${detail}`);
  }
  const body = await response.json() as { updates?: { updatedRange?: string } };
  const updatedRange = body.updates?.updatedRange;
  if (!updatedRange) throw new Error("GOOGLE_DATA_HUB_APPEND_FAILED:NO_UPDATED_RANGE");
  return updatedRange;
}

function resolveHeaders(headers: unknown[]) {
  const normalized = new Map(headers.map((header, index) => [normalizeHeader(header), index]));
  const map: Record<string, number> = {};
  for (const [field, aliases] of Object.entries(HEADER_ALIASES)) {
    const position = aliases.map((alias) => normalized.get(normalizeHeader(alias))).find((value) => value !== undefined);
    if (position !== undefined) map[field] = position;
  }
  const missing = REQUIRED_TARGET_FIELDS.filter((field) => map[field] === undefined);
  if (missing.length) throw new Error(`DATA_HUB_HEADER_MISMATCH:${missing.join(",")}`);
  return map;
}

function canonicalPayload(row: RawSyncRow) {
  return {
    raw_input_id: row.raw_input_id,
    received_at: row.source_received_at,
    source_system: row.source_system,
    source_account_ref: row.source_account_ref,
    channel: row.channel ?? "",
    sender_type: row.sender_type ?? "",
    sender_ref: row.sender_ref ?? "",
    content_type: row.content_type ?? "",
    original_ref: row.original_ref ?? "",
    raw_summary: row.raw_summary ?? "",
    classification: row.classification ?? "",
    entity_type: row.entity_type ?? "",
    entity_id: row.entity_id ?? "",
    processing_status: row.processing_status ?? "",
    thread_id: row.thread_id ?? "",
    message_id: row.message_id ?? "",
    consent_signal: row.consent_signal ?? "",
    stable_external_key: row.stable_external_key,
    payload_checksum: row.payload_checksum,
  } as Record<string, unknown>;
}

function buildTargetRow(headers: unknown[], map: Record<string, number>, payload: Record<string, unknown>) {
  const values = Array(headers.length).fill("");
  for (const [field, position] of Object.entries(map)) {
    if (field in payload) values[position] = payload[field] ?? "";
  }
  return values;
}

function rowMatches(row: unknown[], map: Record<string, number>, payload: Record<string, unknown>) {
  for (const [field, position] of Object.entries(map)) {
    if (!(field in payload)) continue;
    const expected = String(payload[field] ?? "").trim();
    const actual = String(row[position] ?? "").trim();
    if (expected !== actual) return { ok: false, field };
  }
  return { ok: true } as const;
}

function rowNumberFromRange(a1: string) {
  const match = a1.match(/!\$?[A-Z]+\$?(\d+)(?::\$?[A-Z]+\$?\d+)?$/i);
  return match?.[1] ? Number(match[1]) : null;
}

async function heartbeat(status: "HEALTHY" | "DEGRADED", metadata: Json) {
  try {
    await supabaseRpc("record_worker_heartbeat", {
      p_worker_key: "raw_sync",
      p_worker_instance: "supabase_edge:raw-datahub-sync",
      p_environment: "test",
      p_status: status,
      p_version: VERSION,
      p_metadata: metadata,
      p_seen_at: new Date().toISOString(),
    });
  } catch (error) {
    console.error("heartbeat_failed", String(error));
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405, headers: { Allow: "POST" } });

  let requestBody: { mode?: string; batchSize?: number } = {};
  try { requestBody = await req.json(); } catch { /* default run */ }
  const batchSize = Math.min(Math.max(Number(requestBody.batchSize ?? 100), 1), 500);
  const configured = { google: Boolean(googleCredentials()), supabase: Boolean(SERVICE_KEY), dataHubId: DATA_HUB_ID, targetSheet: TARGET_SHEET };

  if (requestBody.mode === "health") {
    return Response.json({ ok: configured.google && configured.supabase, version: VERSION, configured }, { headers: { "cache-control": "no-store" } });
  }

  const startedAt = new Date().toISOString();
  const summary = { staged: 0, claimed: 0, appended: 0, duplicateVerified: 0, synced: 0, retry: 0, dq: 0, failures: [] as string[] };

  try {
    const token = await googleAccessToken();
    const targetRows = await sheetValues(token, `${TARGET_SHEET}!A1:ZZ`);
    if (!targetRows.length) throw new Error("DATA_HUB_HEADER_MISMATCH:EMPTY_SHEET");
    const headers = targetRows[0];
    const headerMap = resolveHeaders(headers);
    const rawIdColumn = headerMap.raw_input_id;
    const existingByRawId = new Map<string, { row: unknown[]; rowNumber: number }>();
    for (let i = 1; i < targetRows.length; i++) {
      const rawId = String(targetRows[i]?.[rawIdColumn] ?? "").trim();
      if (rawId && !existingByRawId.has(rawId)) existingByRawId.set(rawId, { row: targetRows[i], rowNumber: i + 1 });
    }

    const sources = await supabaseGet<SourceBacklog[]>("raw_datahub_sync_source_backlog_v", "select=source_system,source_account_ref,unstaged_count&order=source_system.asc,source_account_ref.asc");
    for (const source of sources) {
      if (Number(source.unstaged_count ?? 0) <= 0) continue;
      const staged = await supabaseRpc<unknown[]>("raw_datahub_sync_stage_batch", {
        p_source_system: source.source_system,
        p_source_account_ref: source.source_account_ref === "__UNSCOPED__" ? "" : source.source_account_ref,
        p_batch_size: Math.min(batchSize, Number(source.unstaged_count)),
      });
      summary.staged += Array.isArray(staged) ? staged.length : 0;
    }

    const claimed = await supabaseRpc<RawSyncRow[]>("raw_datahub_sync_claim_pending", { p_limit: batchSize, p_now: new Date().toISOString() });
    summary.claimed = claimed.length;

    for (const row of claimed) {
      const payload = canonicalPayload(row);
      try {
        const existing = existingByRawId.get(row.raw_input_id);
        if (existing) {
          const comparison = rowMatches(existing.row, headerMap, payload);
          if (!comparison.ok) {
            await supabaseRpc("raw_datahub_sync_mark_failure", {
              p_raw_input_id: row.raw_input_id,
              p_error_class: "TARGET_CONFLICT",
              p_error_message: `Existing Data Hub Raw row differs at ${comparison.field}`,
              p_terminal: true,
              p_now: new Date().toISOString(),
            });
            summary.dq++;
            summary.failures.push(`${row.raw_input_id}:TARGET_CONFLICT:${comparison.field}`);
            continue;
          }
          await supabaseRpc("raw_datahub_sync_mark_success", {
            p_raw_input_id: row.raw_input_id,
            p_payload_checksum: row.payload_checksum,
            p_target_row_ref: `${TARGET_SHEET}!${existing.rowNumber}:${existing.rowNumber}`,
            p_now: new Date().toISOString(),
          });
          summary.duplicateVerified++;
          summary.synced++;
          continue;
        }

        const targetRow = buildTargetRow(headers, headerMap, payload);
        const updatedRange = await appendSheetRow(token, targetRow);
        const readback = await sheetValues(token, updatedRange);
        if (!readback.length) throw new Error("READBACK_EMPTY");
        const comparison = rowMatches(readback[0], headerMap, payload);
        if (!comparison.ok) throw new Error(`READBACK_MISMATCH:${comparison.field}`);

        const rowNumber = rowNumberFromRange(updatedRange);
        existingByRawId.set(row.raw_input_id, { row: readback[0], rowNumber: rowNumber ?? targetRows.length + 1 + summary.appended });
        await supabaseRpc("raw_datahub_sync_mark_success", {
          p_raw_input_id: row.raw_input_id,
          p_payload_checksum: row.payload_checksum,
          p_target_row_ref: updatedRange,
          p_now: new Date().toISOString(),
        });
        summary.appended++;
        summary.synced++;
      } catch (rowError) {
        const message = String(rowError);
        const result = await supabaseRpc<{ sync_status?: string }>("raw_datahub_sync_mark_failure", {
          p_raw_input_id: row.raw_input_id,
          p_error_class: message.split(":")[0].slice(0, 120),
          p_error_message: message.slice(0, 1000),
          p_terminal: message.includes("TARGET_CONFLICT"),
          p_now: new Date().toISOString(),
        });
        if (result?.sync_status === "DQ") summary.dq++; else summary.retry++;
        summary.failures.push(`${row.raw_input_id}:${message.slice(0, 180)}`);
      }
    }

    await heartbeat(summary.failures.length ? "DEGRADED" : "HEALTHY", { ...summary, startedAt, finishedAt: new Date().toISOString() });
    return Response.json({ ok: summary.failures.length === 0, version: VERSION, configured, summary }, { status: summary.failures.length ? 207 : 200, headers: { "cache-control": "no-store" } });
  } catch (error) {
    const message = String(error);
    summary.failures.push(message.slice(0, 300));
    await heartbeat("DEGRADED", { ...summary, startedAt, finishedAt: new Date().toISOString(), fatal: message.slice(0, 500) });
    return Response.json({ ok: false, version: VERSION, configured, error: message, summary }, { status: 503, headers: { "cache-control": "no-store" } });
  }
});
