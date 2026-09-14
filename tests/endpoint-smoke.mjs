import assert from "node:assert/strict";

const base = process.env.MYC_TEST_BASE_URL ?? "http://127.0.0.1:3000";
const endpoints = [
  "/api/v1/read/inbox/line",
  "/api/v1/read/system/health",
  "/api/v1/read/jobs",
  "/api/v1/read/jobs/MYC-J-000005",
  "/api/v1/read/clients",
  "/api/v1/read/clients/MYC-B2B-0001",
  "/api/v1/read/partners",
  "/api/v1/read/partners/MYC-P-0001",
  "/api/v1/read/candidates",
  "/api/v1/read/candidates/MYC-C-000001",
  "/api/v1/read/dq",
  "/api/v1/read/founder/today",
];

for (const path of endpoints) {
  const response = await fetch(`${base}${path}`, { headers: { accept: "application/json" } });
  assert.equal(response.status, 200, `${path} expected HTTP 200, got ${response.status}`);
  assert.match(response.headers.get("cache-control") ?? "", /no-store/, `${path} must be no-store`);
  assert.equal(response.headers.get("x-myc-contract-version"), "v1");
  const body = await response.json();
  assert.equal(body.contract_version, "v1", `${path} contract_version`);
  assert.ok(["READY", "PARTIAL", "STALE", "NOT_READY", "BLOCKED"].includes(body.readiness), `${path} readiness`);
  assert.ok(typeof body.canonical_id === "string" && body.canonical_id.length > 0, `${path} canonical_id`);
  assert.ok(typeof body.source_authority === "string", `${path} source_authority`);
  assert.ok(body.freshness && typeof body.freshness.max_age_seconds === "number", `${path} freshness`);
  assert.ok(Array.isArray(body.warnings), `${path} warnings`);
  if (body.readiness === "NOT_READY") assert.notDeepEqual(body.data, [], `${path} must not fake [] for NOT_READY`);
}

console.log(`Official Read V1 endpoint smoke passed: ${endpoints.length} endpoints`);
