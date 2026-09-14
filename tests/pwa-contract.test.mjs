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

test("offline policy forbids direct Master writes", async () => {
  const contract = await read("lib/platform/contracts.ts");
  assert.match(contract, /directMasterWrite:\s*false/);
  assert.match(contract, /cacheApiResponses:\s*false/);
});

test("future modules are feature-flagged off", async () => {
  const flags = await read("lib/platform/feature-flags.ts");
  for (const key of ["finance", "payroll", "accounting", "aiMatching", "partnerPortal", "candidatePortal"]) {
    assert.match(flags, new RegExp(`${key}:\\s*false`));
  }
});

test("Founder Home exposes required action lanes without fake metrics", async () => {
  const page = await read("app/page.tsx");
  for (const label of ["Need My Action", "Today / Follow-up", "Urgent / Warning", "AI / System Handled", "DATA READINESS"]) {
    assert.ok(page.includes(label), `missing ${label}`);
  }
  assert.ok(page.includes("NO FAKE DATA"));
});
