import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

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

test("Official Read V1 contract matches PR #22 semantics", async () => {
  const contract = await read("lib/platform/contracts.ts");
  for (const state of ["READY", "PARTIAL", "STALE", "NOT_READY", "BLOCKED"]) assert.ok(contract.includes(`"${state}"`));
  for (const authority of ["GOOGLE_SHEETS_DRIVE", "SUPABASE_TECHNICAL", "COMPOSITE_GOVERNED"]) assert.ok(contract.includes(`"${authority}"`));
  for (const field of ["canonical_id", "source_ref", "updated_at", "freshness", "readiness", "reason_code", "warnings"]) assert.ok(contract.includes(field));
});

test("offline policy forbids direct Master writes", async () => {
  const contract = await read("lib/platform/contracts.ts");
  assert.match(contract, /directMasterWrite:\s*false/);
  assert.match(contract, /cacheApiResponses:\s*false/);
  assert.match(contract, /DIRECT_MASTER_WRITE_ALLOWED = false/);
});

test("future modules are feature-flagged off", async () => {
  const flags = await read("lib/platform/feature-flags.ts");
  for (const key of ["finance", "payroll", "accounting", "aiMatching", "partnerPortal", "candidatePortal"]) assert.match(flags, new RegExp(`${key}:\\s*false`));
});

test("Founder Home binds only the governed server endpoint", async () => {
  const page = await read("app/page.tsx");
  assert.ok(page.includes('/api/v1/read/founder/today'));
  assert.ok(page.includes('COMPOSITE_GOVERNED'));
});

test("Candidate guard forces STALE with UNPROMOTED_RAW_GAP", async () => {
  const provider = await read("lib/data/official-read.ts");
  assert.match(provider, /readiness = "STALE"/);
  assert.match(provider, /reasonCode = "UNPROMOTED_RAW_GAP"/);
  assert.match(provider, /candidate_promotion_gap_v/);
});

test("header mapping is alias-based and fail-closed", async () => {
  const aliases = await read("lib/data/header-aliases.ts");
  assert.ok(aliases.includes("DATA_HUB_HEADER_ALIASES"));
  assert.ok(aliases.includes("MissingRequiredHeaderError"));
  assert.ok(aliases.includes("ชื่อ-นามสกุล"));
  assert.ok(aliases.includes("บริษัท/สถานที่ทำงาน"));
  assert.ok(!aliases.includes("row[0]"));
});

test("sensitive Candidate and Inbox fields are redacted from browser payloads", async () => {
  const provider = await read("lib/data/official-read.ts");
  assert.ok(provider.includes("SENSITIVE_FIELDS_REDACTED"));
  assert.ok(provider.includes("sensitive_content_redacted: true"));
  const ui = await read("components/live-read-panel.tsx");
  assert.ok(!ui.includes("sender_ref"));
  assert.ok(!ui.includes("raw_summary"));
});

test("Android PWA manifest and mobile breakpoints remain intact", async () => {
  const manifest = await read("app/manifest.ts");
  const core = await read("app/globals.css");
  const pwa = await read("app/pwa.css");
  assert.match(manifest, /sizes:\s*"192x192"/);
  assert.match(manifest, /sizes:\s*"512x512"/);
  assert.match(manifest, /display:\s*"standalone"/);
  assert.match(`${core}\n${pwa}`, /@media \(max-width:\s*980px\)/);
  assert.match(`${core}\n${pwa}`, /@media \(max-width:\s*680px\)/);
  assert.match(pwa, /grid-template-columns:\s*repeat\(5,/);
});
