# Part 5 Wave 5C — Observability / Alert Routing / Incident Aggregation

Status: **CLOSED / PASS (TEST FOUNDATION)**  
Production Readiness: **NOT_READY**  
Date: 2026-08-30 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Implemented from:

- `MEYOU_CONNECT_SECURITY_RELIABILITY_OBSERVABILITY_BLUEPRINT_V1.md`
- `MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1.xlsx`
- `MEYOU_CONNECT_INCIDENT_RESPONSE_RUNBOOK_V1.md`
- Part 3 operational alert candidates / worker / scheduler / DLQ signals
- Part 5A Security Production-Gate control plane
- Part 5B ingress security events

Operational Source of Truth remains Google Sheets + Google Drive.

## Implemented

### Alert normalization and aggregation

New objects:

- `ops.alert_rule_catalog`
- `ops.alert_routes`
- `ops.alert_instances`
- `ops.alert_occurrences`
- `ops.alert_delivery_queue`

Canonical Security Control Matrix alert rules `ALT-001..ALT-012` are represented in the alert rule catalog.

`ops.ingest_alert_signal(...)` provides:

- stable fingerprint deduplication
- occurrence aggregation
- affected-count aggregation
- severity escalation without silent downgrade
- owner-role routing
- incident creation for critical SEV0/SEV1 rules
- delivery queue preparation while respecting the external-delivery safety gate

Repeated observations of one condition remain one active Alert rather than creating a notification storm.

### Incident model

New objects:

- `ops.incidents`
- `ops.incident_timeline`

`ops.transition_incident(...)` enforces controlled lifecycle:

`OPEN → ACKNOWLEDGED / CONTAINED → RECOVERING → RESOLVED → CLOSED`

SEV0 acknowledgement target is 15 minutes.
SEV1 acknowledgement target is 30 minutes.

Incident closure is rejected unless the record contains:

- evidence reference
- root cause
- corrective action
- Risk Register reference

This follows the Part 5 Incident Runbook principle to contain first, preserve evidence, recover/reconcile and close only after corrective actions are captured.

Alert/incident audit children use restrictive foreign keys. Deleting a parent does not cascade-delete occurrences or incident timeline evidence.

### Internal signal refresh

`ops.refresh_observability_signals('TEST')` normalizes:

- existing `ops.alert_candidates_v` operational signals
- open SEV0/SEV1 `ops.security_events`

Active internal cron:

- job: `meyou-connect-observability-refresh`
- cadence: every 5 minutes
- environment: TEST

This is internal database monitoring only.

### External alert delivery remains disabled

`security_external_alert_delivery_enabled = false`

Alert route/delivery records may be prepared, but delivery remains `HELD` unless both:

1. the route is verified, and
2. the external delivery safety gate is explicitly enabled.

Part 5C did not fabricate a real Founder/owner destination or send any external notification.

Therefore Production Gate `PG-013 — Critical alerts route to real owner` remains **NOT_READY**.

### Read-only observability API

Role-scoped API functions:

- `api.observability_alerts(...)`
- `api.observability_incidents(...)`
- `api.observability_route_readiness()`
- `api.observability_foundation_status()`

They reuse Part 5A `security_read` / `security_audit_read` capabilities.

No authenticated alert/incident write or incident-close RPC is exposed.
Direct access to Part 5C operation tables is denied to `anon` and `authenticated`.

## Acceptance smoke — PASS

Transactional smoke validated:

1. repeated same fingerprint aggregates into one Alert
2. occurrence count increments correctly
3. `SEV2 → SEV1` escalation occurs without duplicate Alert
4. critical escalation creates exactly one Incident
5. repeated SEV1 signal does not create duplicate Incident
6. SEV1 acknowledgment due target is approximately 30 minutes
7. SEV0 acknowledgment due target is approximately 15 minutes
8. verified TEST route still remains `HELD` while external delivery is disabled
9. incident lifecycle transitions are controlled
10. incident cannot close without closure evidence / root cause / corrective action / Risk reference
11. successful incident closure resolves the linked Alert
12. Founder-role API read is allowed
13. Content Studio observability read is denied
14. direct authenticated table access is denied
15. `anon` API access is denied
16. synthetic Auth users, Alerts, Incidents and occurrences are fully rolled back

Synthetic residue after smoke:

- Auth users: 0
- Alert rows: 0
- Incident rows: 0
- Occurrence rows: 0

## Security / performance

- Supabase Security Advisor: **PASS / 0 lint**
- Part 5C missing-FK-index findings were corrected
- remaining Performance notices are only `unused_index` INFO in the low/no-traffic TEST environment

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Safety state

- `security_observability_foundation_ready = true`
- `part5c_foundation_closed = true`
- `security_external_alert_delivery_enabled = false`
- `production_cutover_approved = false`
- Google Sheets + Google Drive remain the operational Source of Truth

## Production Gate boundary

Part 5C proves internal Alert/Incident normalization and routing logic in TEST.
It does **not** prove that alerts reach a real human owner.

`PG-013` must remain NOT_READY until a named privileged owner and actual alert channel are configured and an end-to-end route test is captured as evidence.

## Migration history

Part 5C migrations:

- `20260830044437` — observability alert foundation
- `20260830044540` — alert / incident engine
- `20260830044608` — RLS + read API
- `20260830044709` — observability / incident smoke
- `20260830044753` — activate internal observability
- `20260830044826` — FK index hardening

Supabase total after Part 5C: **84 migrations**.

## Boundary after 5C

Next safe implementation track: **Part 5D — Backup / Restore Readiness + Recovery Evidence + Backup Freshness Monitoring**, TEST-first. Production cutover remains blocked.
