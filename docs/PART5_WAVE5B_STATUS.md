# Part 5 Wave 5B — Webhook/API Protection + Replay/Abuse Controls

Status: **CLOSED / PASS (TEST FOUNDATION)**  
Production Readiness: **NOT_READY**  
Date: 2026-08-30 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Implemented from:

- `MEYOU_CONNECT_SECURITY_RELIABILITY_OBSERVABILITY_BLUEPRINT_V1.md`
- `MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1.xlsx`
- Part 3 material-event ingestion / idempotency kernel
- Part 5A Security Production-Gate control plane

Operational Source of Truth remains Google Sheets + Google Drive.

## Implemented

### Endpoint security policy

New objects:

- `ops.ingress_endpoint_policies`
- `ops.ingress_request_log`
- `ops.ingress_replay_keys`
- `ops.ingress_rate_windows`
- `ops.ingress_security_summary_v`

TEST policy definitions exist for:

- Facebook signed webhook
- LINE signed webhook
- public Candidate form
- Founder/internal service ingress

All endpoint policies are disabled after acceptance.

### Request guard engine

`ops.evaluate_ingress_request(...)` enforces:

- endpoint enabled / environment gate
- payload size
- allowed content type
- required signature verification result
- request timestamp
- stale replay window
- future timestamp skew
- sensitive-data policy
- replay key reservation
- fixed-window endpoint rate limit
- client-key requirement
- security metadata secret-field rejection
- structured ALLOW / DENY / QUARANTINE decision logging

The database stores hashed replay/client identifiers only. It does not store raw provider signatures, bearer tokens or raw IP addresses.

### Cryptographic trust boundary

Provider-specific HMAC/signature verification remains in the trusted ingress adapter using credentials from an approved secret store.

The database receives only the verification result (`signature_present` / `signature_verified`) and independently enforces the endpoint policy and replay/abuse controls.

No provider secret is persisted in PostgreSQL by Part 5B.

### Secure Part 3 ingress

`ops.secure_ingest_material_event(...)` connects the guard directly to the existing Part 3 path:

`Ingress Request → Security Guard → Raw Input → Event → Routing`

If the guard does not return `ALLOW`, Raw Input/Event creation does not occur.

Additional source-policy enforcement prevents an envelope for one source/channel from being submitted through a different endpoint policy.

### Idempotent retry vs replay

- same `request_id` may safely repeat as an idempotent network retry
- Part 3 still keeps one logical Event
- different `request_id` reusing the same replay key is rejected as `REPLAY_DETECTED`

### Read-only security API

- `api.security_ingress_policies()`
- `api.security_ingress_summary()`
- `api.security_ingress_rejections(...)`

Founder / Secretary / Data Audit access follows the Part 5A security capabilities.

No authenticated ingress-write or endpoint-admin RPC is exposed.

### RLS / execution boundary

- all Part 5B operation tables use RLS
- direct `anon` / `authenticated` table access is denied
- guard / secure-ingest functions are service-role only
- unexpected direct client execution on new privileged functions = 0

## Acceptance — PASS

Transactional smoke covered:

1. disabled endpoint fails closed
2. valid signed Facebook-style request reaches exactly one Part 3 Raw Input/Event
3. retry of the same request remains idempotent
4. same replay key under a new request is rejected before ingestion
5. invalid signature is rejected
6. stale timestamp is rejected
7. excessive future timestamp is rejected
8. oversized payload is rejected
9. unsupported content type is rejected
10. disallowed sensitive request is quarantined
11. secret-like security metadata is rejected
12. source/channel spoofing is rejected before Raw Input creation
13. fixed-window rate limit rejects the request above the configured threshold
14. Founder/Data Audit can use intended security read APIs
15. Content Studio and anon are denied
16. direct security-table access is denied

Synthetic Auth users, Raw Inputs, Events, request logs, replay keys and rate windows were rolled back completely.

Post-test synthetic residue: **0**.

## Security gate change

Canonical TEST evidence `webhook_signature_replay` was recorded for `PG-006`.

Latest Security Gate snapshot:

### TEST

- PASS: **9**
- FAIL: **0**
- NOT_READY: **6**
- Overall: **NOT_READY**

`PG-006 Webhook signature/replay tests pass` is now **PASS** in TEST.

Remaining TEST NOT_READY items are Production-readiness evidence such as secret scan/review, credential separation, fresh backup/restore evidence, real alert routing and final Production approval.

### PROD

- PASS: **3**
- FAIL: **0**
- NOT_READY: **12**
- Overall: **NOT_READY**

No TEST webhook result was promoted to Production evidence.

## Safety state

- `part5b_foundation_closed = true`
- `security_webhook_test_acceptance_passed = true`
- `security_webhook_enforcement_ready = true`
- `security_test_ingress_enabled = false`
- `external_channel_webhooks_enabled = false`
- `security_production_gate_enabled = false`
- `migration_target_apply_enabled = false`
- `migration_cutover_enabled = false`
- `production_cutover_approved = false`
- operational Source of Truth remains Google Sheets + Google Drive

`security_webhook_enforcement_ready = true` means the enforcement contract is implemented and accepted in TEST. It does **not** enable a live external endpoint.

## Security / Performance

- Supabase Security Advisor: **PASS / 0 lint**
- no new missing-FK-index blocker
- Performance notices are unused-index INFO in the low/no-traffic TEST environment

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Migration history

Part 5B migrations:

- `20260830033728` ingress security foundation
- `20260830033811` request guard engine
- `20260830033904` secure Part 3 material ingress
- `20260830033931` role-scoped read API
- `20260830034017` transactional endpoint security smoke
- `20260830034203` final evidence / gate snapshot
- `20260830034316` canonical PG-006 evidence-key alignment

Supabase migration total after Part 5B: **78 migrations**.

## Boundary after 5B

Part 5B proves the server-side endpoint enforcement and replay/abuse boundary in TEST. It does not create or enable a public Production webhook endpoint and does not store provider secrets.

Next safe implementation track: **Part 5C — Observability / Alert Routing + Incident Signal Aggregation**, TEST-first with external alert delivery still disabled until a real owner/channel acceptance test exists.
