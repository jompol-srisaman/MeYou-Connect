import "jsr:@supabase/functions-js/edge-runtime.d.ts";

// datahub-shadow-import v2 (READ-ONLY toward Google Sheets; writes ONLY ops.shadow_import_* via RPC)
// Modes: health | headers | import {entities?, dryRun?}
// Privacy: only allowlisted fields are staged. Cashbook: NO account numbers, NO slip refs, NO free-text notes, NO source file link.
const PROJECT_REF = "pgjmxdeafzogzsyawejs";
const DATA_HUB_ID = Deno.env.get("MYC_DATA_HUB_SPREADSHEET_ID") ?? "1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? `https://${PROJECT_REF}.supabase.co`;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const VERSION = "datahub-shadow-import-v2";
const SCOPE = "https://www.googleapis.com/auth/spreadsheets.readonly";
const CREATED_BY = "claude:datahub-shadow-import";

type Ent = { sheet: string; pk: string; fields: Record<string, string[]>; dates?: string[] };
const ENT: Record<string, Ent> = {
  Candidate: { sheet: "01_Candidate", pk: "candidate_id", dates: ["ready_date"], fields: {
    candidate_id: ["Candidate ID"], nickname: ["ชื่อเล่น"], origin_province: ["จังหวัดต้นทาง"], education: ["การศึกษา"], primary_experience: ["ประสบการณ์หลัก"],
    preferred_job: ["งานที่สนใจ"], expected_income: ["รายได้ที่คาดหวัง"], shift_preference: ["กะที่รับได้"], relocation_ready: ["พร้อมย้าย?"], ready_date: ["วันที่พร้อมเริ่ม"],
    has_vehicle: ["มีรถ?"], dorm_needed: ["ต้องการหอ?"], dorm_budget: ["งบหอ/เดือน"], documents_ready: ["เอกสารพร้อม?"], medical_ready: ["ตรวจสุขภาพพร้อม?"],
    source_type: ["Source"], partner_id: ["Partner ID"], status: ["Status"], next_action: ["Next Action"], created_at: ["Created At"] } },
  Client: { sheet: "03_Client", pk: "client_id", fields: {
    client_id: ["Client ID"], client_type: ["ประเภท Client"], company_name: ["ชื่อบริษัท/Partner"], province: ["จังหวัด"], area: ["พื้นที่"], crm_status: ["CRM Status"],
    payment_term: ["Payment Term"], billing_cycle: ["Billing Cycle"], verification_status: ["Verification Status"] } },
  Partner: { sheet: "04_Partner", pk: "partner_id", dates: ["started_at"], fields: {
    partner_id: ["Partner ID"], partner_name: ["ชื่อ Partner"], partner_type: ["ประเภท Partner"], province: ["จังหวัด"], parent_partner_id: ["ผู้แนะนำ Partner ID"],
    status: ["Status"], started_at: ["วันที่เริ่ม"] } },
  Job: { sheet: "02_งาน_Job", pk: "job_id", dates: ["start_date", "last_confirmed_at"], fields: {
    job_id: ["Job ID"], client_id: ["Client ID"], workplace_name: ["บริษัท/สถานที่ทำงาน"], province: ["จังหวัด"], area: ["พื้นที่/อำเภอ"], position_name: ["ตำแหน่ง"],
    headcount: ["จำนวนรับ"], wage: ["ค่าแรง/เงินเดือน"], shift: ["กะ"], start_date: ["วันที่เริ่มงาน"], milestone_deal: ["Milestone Deal"], payment_term: ["Payment Term"],
    status: ["Status"], last_confirmed_at: ["Last Confirmed"], client_confirmed: ["Client Confirmed?"] } },
  Placement: { sheet: "05_Placement", pk: "placement_id", dates: ["submitted_at", "appointment_at", "applied_at", "start_date"], fields: {
    placement_id: ["Placement ID"], candidate_id: ["Candidate ID"], job_id: ["Job ID"], status: ["Status"], submitted_at: ["Submitted Date"], appointment_at: ["Appointment Date"],
    applied_at: ["Applied Date"], start_date: ["Start Date"], dropout_reason: ["Dropout Reason"] } },
  FollowUp: { sheet: "07_FollowUp", pk: "followup_id", dates: ["followup_date", "next_followup", "updated_at"], fields: {
    followup_id: ["FollowUp ID"], placement_id: ["Placement ID"], followup_date: ["วันที่ Follow-up"], milestone: ["Milestone"], outcome: ["ผลลัพธ์"], case_opened: ["เปิดเคส?"],
    owner: ["Owner"], next_followup: ["Next Follow-up"], updated_at: ["Updated At"] } },
  Revenue: { sheet: "08_Revenue", pk: "revenue_id", dates: ["transaction_date", "invoice_date", "due_date", "collection_date"], fields: {
    revenue_id: ["Revenue ID"], transaction_date: ["วันที่รายการ"], client_id: ["Client ID"], placement_id: ["Placement ID"], revenue_type: ["ประเภท Revenue"], milestone: ["Milestone"],
    gross: ["Gross"], wht: ["WHT"], status: ["Status"], invoice_no: ["Invoice No."], invoice_date: ["Invoice Date"], due_date: ["Due Date"], collection_date: ["Collection Date"],
    net_received: ["Net Received"] } },
  Commission: { sheet: "10_Commission", pk: "commission_id", dates: ["earned_date", "payable_date", "paid_date"], fields: {
    commission_id: ["Commission ID"], partner_id: ["Partner ID"], placement_id: ["Placement ID"], milestone: ["Milestone"], commission_amount: ["Commission Amount"], state: ["State"],
    earned_date: ["Earned Date"], payable_date: ["Payable Date"], paid_date: ["Paid Date"], override_from_partner_id: ["Override From Partner ID"], override_40: ["Override 40?"] } },
  Data_Quality: { sheet: "21_Data_Quality_Queue", pk: "dq_issue_id", dates: ["detected_at", "resolved_at"], fields: {
    dq_issue_id: ["DQ Issue ID"], detected_at: ["Detected At"], entity_type: ["Entity Type"], entity_id: ["Entity ID"], field_name: ["Field / Column"], issue_type: ["Issue Type"],
    raw_input_id: ["Raw Input ID"], severity: ["Severity"], required_action: ["Required Action"], status: ["Status"], resolved_at: ["Resolved At"] } },
  Cashbook: { sheet: "22_Finance_Cashbook", pk: "bank_txn_id", dates: ["txn_at"], fields: {
    bank_txn_id: ["Ledger Ref"], txn_at: ["วันเวลาไทย"], txn_type: ["ประเภทรายการ"], direction: ["ทิศทางเงิน MYC"],
    ttb_in: ["TTB รับ (บาท)"], ttb_out: ["TTB จ่าย (บาท)"], ttb_traced_cumulative: ["TTB funds traced cumulative (บาท)*"],
    related_to: ["เกี่ยวข้องกับ"], evidence_id: ["Evidence ID"], business_status: ["Business status"] }
    // Deliberately EXCLUDED (Founder-approved 2026-09-28): บัญชีต้นทาง/ปลายทาง, เลขอ้างอิงจากสลิป, Source file, หมายเหตุ (free text)
  },
};

function b64url(bytes: Uint8Array | string) {
  const raw = typeof bytes === "string" ? new TextEncoder().encode(bytes) : bytes;
  let bin = ""; for (const b of raw) bin += String.fromCharCode(b);
  return btoa(bin).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function pemToPkcs8(pem: string) {
  const body = pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s+/g, "");
  const bin = atob(body); const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}
function googleCredentials() {
  const raw = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_JSON");
  if (raw) { const p = JSON.parse(raw) as { client_email?: string; private_key?: string }; if (p.client_email && p.private_key) return { clientEmail: p.client_email, privateKey: p.private_key }; }
  const clientEmail = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_EMAIL");
  const privateKey = Deno.env.get("GOOGLE_SERVICE_ACCOUNT_PRIVATE_KEY")?.replace(/\\n/g, "\n");
  if (clientEmail && privateKey) return { clientEmail, privateKey };
  return null;
}
async function googleAccessToken() {
  const c = googleCredentials(); if (!c) throw new Error("GOOGLE_DATA_HUB_AUTH_NOT_CONFIGURED");
  const now = Math.floor(Date.now() / 1000);
  const h = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const p = b64url(JSON.stringify({ iss: c.clientEmail, scope: SCOPE, aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }));
  const u = `${h}.${p}`;
  const key = await crypto.subtle.importKey("pkcs8", pemToPkcs8(c.privateKey), { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"]);
  const sig = new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(u)));
  const r = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${u}.${b64url(sig)}` }) });
  if (!r.ok) throw new Error(`GOOGLE_AUTH_FAILED:${r.status}`);
  const out = await r.json() as { access_token?: string };
  if (!out.access_token) throw new Error("GOOGLE_AUTH_FAILED:NO_TOKEN");
  return out.access_token;
}
async function gget(token: string, url: string) {
  const r = await fetch(url, { headers: { authorization: `Bearer ${token}` } });
  if (!r.ok) throw new Error(`GOOGLE_READ_FAILED:${r.status}:${(await r.text()).slice(0, 200)}`);
  return await r.json();
}
const sbHeaders = () => ({ apikey: SERVICE_KEY, authorization: `Bearer ${SERVICE_KEY}`, "content-type": "application/json", "content-profile": "ops", "accept-profile": "ops" });
async function rpc<T>(name: string, body: Record<string, unknown>): Promise<T> {
  const r = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${name}`, { method: "POST", headers: sbHeaders(), body: JSON.stringify(body) });
  if (!r.ok) throw new Error(`SUPABASE_RPC_FAILED:${name}:${r.status}:${(await r.text()).slice(0, 300)}`);
  return await r.json() as T;
}
async function verifyToken(token: string): Promise<boolean> {
  if (!SERVICE_KEY || !token) return false;
  try { return (await rpc<boolean>("verify_shadow_import_token", { p_token: token })) === true; } catch { return false; }
}
const norm = (v: unknown) => String(v ?? "").trim().replace(/\s+/g, " ").toLowerCase();
function serialToIso(n: number) {
  const iso = new Date(Math.round((n - 25569) * 86400 * 1000)).toISOString();
  return Number.isInteger(n) ? iso.slice(0, 10) : iso.slice(0, 19);
}
function cellValue(v: unknown, isDate: boolean) {
  if (v === undefined || v === null || v === "") return null;
  if (isDate && typeof v === "number") return serialToIso(v);
  return typeof v === "string" ? v.trim() : v;
}
const json = (b: unknown, status = 200) => Response.json(b, { status, headers: { "cache-control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("Method Not Allowed", { status: 405, headers: { Allow: "POST" } });
  if (!(await verifyToken(req.headers.get("x-myc-invoke-token") ?? ""))) return json({ ok: false, error: "FORBIDDEN" }, 403);
  let body: { mode?: string; sheets?: string[]; entities?: string[]; dryRun?: boolean } = {};
  try { body = await req.json(); } catch { /* default */ }
  try {
    const token = await googleAccessToken();
    const meta = await gget(token, `https://sheets.googleapis.com/v4/spreadsheets/${DATA_HUB_ID}?fields=properties.title,sheets.properties(title,gridProperties)`) as { properties?: { title?: string }; sheets?: { properties: { title: string; gridProperties?: { rowCount?: number; columnCount?: number } } }[] };
    const tabs = (meta.sheets ?? []).map((s) => s.properties.title);
    const q = (t: string, a1: string) => encodeURIComponent(`'${t.replace(/'/g, "''")}'!${a1}`);

    if (body.mode === "health" || !body.mode) {
      return json({ ok: true, version: VERSION, spreadsheet: meta.properties?.title, tabs: (meta.sheets ?? []).map((s) => ({ title: s.properties.title, gridRows: s.properties.gridProperties?.rowCount, gridCols: s.properties.gridProperties?.columnCount })) });
    }
    if (body.mode === "headers") {
      const wanted = (body.sheets && body.sheets.length ? body.sheets : tabs).filter((t) => tabs.includes(t));
      const out: Record<string, unknown> = {};
      for (const t of wanted) {
        const head = await gget(token, `https://sheets.googleapis.com/v4/spreadsheets/${DATA_HUB_ID}/values/${q(t, "1:1")}?valueRenderOption=FORMATTED_VALUE`) as { values?: unknown[][] };
        const colA = await gget(token, `https://sheets.googleapis.com/v4/spreadsheets/${DATA_HUB_ID}/values/${q(t, "A:A")}?majorDimension=COLUMNS&valueRenderOption=FORMATTED_VALUE`) as { values?: unknown[][] };
        const a = (colA.values?.[0] ?? []) as unknown[];
        out[t] = { headerRow: head.values?.[0] ?? [], nonEmptyRowsInColA: a.filter((x) => String(x ?? "").trim() !== "").length };
      }
      return json({ ok: true, version: VERSION, headers: out });
    }
    if (body.mode === "import") {
      const keys = (body.entities && body.entities.length ? body.entities : Object.keys(ENT)).filter((k) => ENT[k]);
      const dryRun = body.dryRun === true;
      const snapshotAt = new Date().toISOString();
      const plan: Record<string, { sheet: string; rows: number; skippedEmpty: number; missingHeaders: string[] }> = {};
      const staged: { entity: string; row: number; pk: string | null; rec: Record<string, unknown> }[] = [];
      for (const k of keys) {
        const e = ENT[k];
        if (!tabs.includes(e.sheet)) { plan[k] = { sheet: e.sheet, rows: 0, skippedEmpty: 0, missingHeaders: ["__SHEET_NOT_FOUND__"] }; continue; }
        const vals = ((await gget(token, `https://sheets.googleapis.com/v4/spreadsheets/${DATA_HUB_ID}/values/${q(e.sheet, "A1:ZZ")}?valueRenderOption=UNFORMATTED_VALUE`)) as { values?: unknown[][] }).values ?? [];
        const head = (vals[0] ?? []).map(norm);
        const colOf: Record<string, number> = {}; const missing: string[] = [];
        for (const [f, aliases] of Object.entries(e.fields)) {
          const idx = aliases.map((a) => head.indexOf(norm(a))).find((i) => i >= 0);
          if (idx === undefined) missing.push(f); else colOf[f] = idx;
        }
        let n = 0, empty = 0;
        for (let i = 1; i < vals.length; i++) {
          const row = vals[i] ?? [];
          const rec: Record<string, unknown> = {}; let any = false;
          for (const f of Object.keys(e.fields)) {
            const v = f in colOf ? cellValue(row[colOf[f]], (e.dates ?? []).includes(f)) : null;
            if (v !== null) any = true; rec[f] = v;
          }
          if (!any) { empty++; continue; }
          const pk = rec[e.pk] === null ? null : String(rec[e.pk]);
          staged.push({ entity: k, row: i + 1, pk, rec }); n++;
        }
        plan[k] = { sheet: e.sheet, rows: n, skippedEmpty: empty, missingHeaders: missing };
      }
      if (dryRun) return json({ ok: true, version: VERSION, dryRun: true, plan });

      const sessionId = await rpc<string>("open_shadow_import_session", {
        p_source_system: "GOOGLE_SHEETS", p_source_file_id: DATA_HUB_ID, p_source_file_name: meta.properties?.title ?? "DATA_HUB",
        p_source_revision: snapshotAt, p_snapshot_at: snapshotAt, p_source_of_truth: true, p_expected_entities: keys,
        p_metadata: { function: VERSION, mode: "read_only_sheets_to_shadow", allowlisted_fields_only: true }, p_created_by: CREATED_BY,
      });
      const CH = 10;
      for (let i = 0; i < staged.length; i += CH) {
        await Promise.all(staged.slice(i, i + CH).map((s) => rpc("stage_shadow_row", {
          p_session_id: sessionId, p_entity_key: s.entity, p_source_row_number: s.row, p_source_pk: s.pk, p_raw_record: s.rec, p_normalized_record: s.rec,
        })));
      }
      const validation = await rpc<Record<string, unknown>>("validate_shadow_session", { p_session_id: sessionId });
      const bad = await fetch(`${SUPABASE_URL}/rest/v1/shadow_import_rows?session_id=eq.${sessionId}&validation_status=neq.VALID&select=entity_key,source_row_number,source_pk,validation_status,validation_issues&limit=100`, { headers: sbHeaders() });
      const notValid = bad.ok ? await bad.json() : [{ error: `READ_${bad.status}` }];
      return json({ ok: true, version: VERSION, sessionId, plan, validation, notValid });
    }
    return json({ ok: false, error: "UNKNOWN_MODE" }, 400);
  } catch (e) {
    return json({ ok: false, version: VERSION, error: String(e).slice(0, 400) }, 503);
  }
});
