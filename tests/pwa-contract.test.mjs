import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");
const readBytes = (path) => readFile(new URL(`../${path}`, import.meta.url));

function pngSize(buffer) {
  assert.equal(buffer.toString("ascii", 1, 4), "PNG");
  return [buffer.readUInt32BE(16), buffer.readUInt32BE(20)];
}

test("service worker never caches /api/**", async () => {
  const sw = await read("public/sw.js");
  assert.match(sw, /pathname\.startsWith\("\/api\/"\)/);
  assert.match(sw, /NEVER cached/);
});

test("approved MYC brand tokens are centralized", async () => {
  const css = await read("app/globals.css");
  assert.match(css, /--myc-navy:\s*#0f2d62/i);
  assert.match(css, /--myc-teal:\s*#16c7c1/i);
  assert.match(css, /--myc-sky:\s*#4da8ff/i);
});

test("Official Read V1 internal contract still matches PR #22 semantics", async () => {
  const contract = await read("lib/platform/contracts.ts");
  for (const state of ["READY", "PARTIAL", "STALE", "NOT_READY", "BLOCKED"]) assert.ok(contract.includes(`"${state}"`));
  for (const authority of ["GOOGLE_SHEETS_DRIVE", "SUPABASE_TECHNICAL", "COMPOSITE_GOVERNED"]) assert.ok(contract.includes(`"${authority}"`));
  for (const field of ["canonical_id", "source_ref", "updated_at", "freshness", "readiness", "reason_code", "warnings"]) assert.ok(contract.includes(field));
});

test("Founder-facing primary screens are Thai-first and hide developer contract wording", async () => {
  const home = await read("app/page.tsx");
  const modulePage = await read("app/[section]/page.tsx");
  const shell = await read("components/app-shell.tsx");
  const combined = `${home}\n${modulePage}\n${shell}`;
  for (const banned of [
    "OFFICIAL READ V1",
    "Official Read Contract",
    "server-side governed",
    "Canonical source",
    "Supabase TEST shadow",
    "ops.candidate_promotion_gap_v",
  ]) assert.ok(!combined.includes(banned), `Founder UI exposes technical wording: ${banned}`);
  assert.ok(home.includes("ข้อมูลล่าสุด"));
  assert.ok(modulePage.includes("แหล่งข้อมูล"));
});

test("shared readiness and loading empty error UI are explicit", async () => {
  const states = await read("components/data-state.tsx");
  const panel = await read("components/live-read-panel.tsx");
  for (const label of ["พร้อมใช้งาน", "ใช้งานได้บางส่วน", "ข้อมูลอาจไม่ครบ/ไม่ล่าสุด", "ยังไม่พร้อม", "ต้องแก้เงื่อนไขก่อน"]) {
    assert.ok(states.includes(label), `missing readiness label ${label}`);
  }
  for (const variant of ["loading", "empty", "error"]) assert.ok(states.includes(`"${variant}"`));
  assert.ok(states.includes("ลองใหม่"), "shared error UI must offer retry action");
  assert.ok(panel.includes("<DataState"));
});

test("readiness visuals are distinct and match product semantics", async () => {
  const css = await read("app/globals.css");
  assert.match(css, /\.readiness-ready\s*\{[^}]*var\(--success-soft\)/s);
  assert.match(css, /\.readiness-partial\s*\{[^}]*var\(--sky-soft\)/s);
  assert.match(css, /\.readiness-stale\s*\{[^}]*var\(--warn-soft\)/s);
  assert.match(css, /\.readiness-not_ready[^}]*var\(--neutral-soft\)/s);
  assert.match(css, /\.readiness-blocked\s*\{[^}]*var\(--danger-soft\)/s);
});

test("offline policy forbids direct Master writes", async () => {
  const contract = await read("lib/platform/contracts.ts");
  assert.match(contract, /directMasterWrite:\s*false/);
  assert.match(contract, /cacheApiResponses:\s*false/);
  assert.match(contract, /DIRECT_MASTER_WRITE_ALLOWED = false/);
});

test("future modules remain feature-flagged off", async () => {
  const flags = await read("lib/platform/feature-flags.ts");
  for (const key of ["finance", "payroll", "accounting", "aiMatching", "partnerPortal", "candidatePortal"]) assert.match(flags, new RegExp(`${key}:\\s*false`));
});

test("Founder Home binds only the governed server endpoint", async () => {
  const page = await read("app/page.tsx");
  assert.ok(page.includes('/api/v1/read/founder/today'));
  assert.ok(!page.includes("sheets.googleapis.com"));
  assert.ok(!page.includes("supabase.co"));
});

test("Candidate inventory guard forces STALE with UNPROMOTED_RAW_GAP without degrading every record", async () => {
  const provider = await read("lib/data/official-read.ts");
  assert.ok(provider.includes('readiness: gap.unverifiedCount > 0 ? "STALE" : "READY"'));
  assert.ok(provider.includes('"UNPROMOTED_RAW_GAP"'));
  assert.match(provider, /candidate_promotion_gap_v/);
  assert.ok(provider.includes("per_candidate_record_readiness"));
});

test("header mapping is alias-based and fail-closed", async () => {
  const aliases = await read("lib/data/header-aliases.ts");
  assert.ok(aliases.includes("DATA_HUB_HEADER_ALIASES"));
  assert.ok(aliases.includes("MissingRequiredHeaderError"));
  assert.ok(aliases.includes("ชื่อ-นามสกุล"));
  assert.ok(aliases.includes("บริษัท/สถานที่ทำงาน"));
  assert.ok(!aliases.includes("row[0]"));
});

test("sensitive Candidate and Inbox fields stay redacted from browser payloads", async () => {
  const provider = await read("lib/data/official-read.ts");
  assert.ok(provider.includes("SENSITIVE_FIELDS_REDACTED"));
  assert.ok(provider.includes("sensitive_content_redacted: true"));
  const ui = await read("components/live-read-panel.tsx");
  assert.ok(!ui.includes("sender_ref"));
  assert.ok(!ui.includes("raw_summary"));
});

test("mobile UX enforces readable labels and 44px plus tap targets", async () => {
  const core = await read("app/globals.css");
  const pwa = await read("app/pwa.css");
  const combined = `${core}\n${pwa}`;
  assert.match(combined, /@media \(max-width:\s*980px\)/);
  assert.match(combined, /@media \(max-width:\s*680px\)/);
  assert.match(pwa, /\.secondary-button\s*\{[\s\S]*?min-height:\s*44px/);
  assert.match(pwa, /\.pwa-update-banner button\s*\{[\s\S]*?min-height:\s*44px/);
  assert.match(pwa, /\.mobile-bottom-item\s*\{[\s\S]*?min-height:\s*48px[\s\S]*?font-size:\s*12px/);
});

test("PWA manifest, install help, and Apple metadata use approved PNG icons", async () => {
  const manifest = await read("app/manifest.ts");
  const layout = await read("app/layout.tsx");
  const more = await read("app/more/page.tsx");
  assert.ok(manifest.includes('/myc-icon-192.png'));
  assert.ok(manifest.includes('/myc-icon-512.png'));
  assert.match(manifest, /sizes:\s*"192x192"/);
  assert.match(manifest, /sizes:\s*"512x512"/);
  assert.match(manifest, /type:\s*"image\/png"/);
  assert.ok(layout.includes('/apple-touch-icon.png'));
  assert.match(layout, /sizes:\s*"180x180"/);
  assert.match(manifest, /display:\s*"standalone"/);
  assert.ok(more.includes("ติดตั้งบน Android"));
  assert.ok(more.includes("เพิ่มลงในหน้าจอหลัก"));
});

test("approved install icon files have exact dimensions", async () => {
  assert.deepEqual(pngSize(await readBytes("public/myc-icon-192.png")), [192, 192]);
  assert.deepEqual(pngSize(await readBytes("public/myc-icon-512.png")), [512, 512]);
  assert.deepEqual(pngSize(await readBytes("public/apple-touch-icon.png")), [180, 180]);
});


test("Candidate per-record readiness is separate from inventory completeness and lifecycle actions fail closed", async () => {
  const contract = await read("lib/platform/contracts.ts");
  const provider = await read("lib/data/official-read.ts");
  assert.ok(contract.includes("candidate_inventory_completeness"));
  assert.ok(provider.includes("per_candidate_record_readiness"));
  assert.ok(provider.includes("LIFECYCLE_EVIDENCE_REVIEW_REQUIRED"));
  assert.ok(provider.includes('lifecycle_evidence_state: lifecycleNeedsEvidenceReview ? "REVIEW"'));
  assert.ok(provider.includes("lifecycle_action_unlock_allowed: false"));
  assert.ok(provider.includes('readiness: gap.unverifiedCount > 0 ? "STALE" : "READY"'));
  assert.ok(provider.includes('const perRecordReadiness: Readiness = lifecycleNeedsEvidenceReview ? "PARTIAL" : "READY"'));
});

test("Preview read-gate acceptance runner is live-HTTP only, Preview-only, and emits sanitized summaries", async () => {
  const runner = await read("app/read-gate-acceptance/page.tsx");
  assert.ok(runner.includes('process.env.VERCEL_ENV !== "preview"'));
  assert.ok(runner.includes("fetch(origin + path"));
  assert.ok(runner.includes('cache: "no-store"'));
  assert.ok(runner.includes('redirect: "manual"'));
  assert.ok(runner.includes("pii_secret_leak_detected"));
  assert.ok(runner.includes("lifecycle_action_unlock_true_count"));
  assert.ok(!runner.includes("SUPABASE_SERVICE_ROLE_KEY"));
  assert.ok(!runner.includes("GOOGLE_SERVICE_ACCOUNT_JSON"));
});
