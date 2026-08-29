# Part 4 Wave 4G — Delta Migration / Write-Freeze Rehearsal + Cutover Readiness

Status: **CLOSED / PASS**  
Date: 2026-08-30 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Part 4G follows the canonical migration contract from:

- `MEYOU_CONNECT_MIGRATION_PLAYBOOK_V1.md`
- `MEYOU_CONNECT_FOUNDER_MASTER_V1.md`
- `00_MEYOU_CONNECT_CONTROL_INDEX_V3_UNIFIED.md`
- live `MEYOU_CONNECT_MVP_DATA_HUB_V1 / 98_System_Config`
- Part 4F Shadow Migration / Reconciliation Harness

The migration rule remains: **one writable Master at a time**. Google Sheets + Google Drive remain the operational Source of Truth until a separately approved Production cutover.

## TEST-only cutover rehearsal control plane

Implemented:

- `ops.cutover_rehearsals`
- `ops.rehearsal_target_rows` — isolated scratch target, not Core/Finance/Docs Master
- `ops.delta_batches`
- `ops.delta_rows`
- `ops.rehearsal_reconciliation_runs`
- `ops.rehearsal_reconciliation_results`
- `ops.migration_fk_rules`
- `ops.cutover_check_catalog`
- `ops.cutover_check_results`
- `ops.cutover_readiness_v`

Rehearsal gates are all default OFF:

- `migration_rehearsal_enabled = false`
- `migration_freeze_rehearsal_enabled = false`
- `migration_delta_capture_enabled = false`
- `migration_target_apply_enabled = false`
- `migration_cutover_enabled = false`
- `production_cutover_approved = false`

There is no writer-switch function and no Part 4G function that applies rehearsal rows into the real Master tables.

## Delta rehearsal

Part 4G can compare an approved baseline shadow snapshot with a final shadow snapshot and classify rows as:

- `INSERT`
- `UPDATE`
- `SOURCE_REMOVED`
- `UNCHANGED`
- `INVALID_SOURCE`
- `UNSUPPORTED`

A `SOURCE_REMOVED` row is rehearsed as an **archive candidate**, not a hard delete.

The scratch apply path refuses to run if real target-apply, cutover, or Production-approval gates are enabled.

## Write-freeze rehearsal

The system records a freeze checkpoint, source revision, and final backup reference.

Important boundary: `begin_write_freeze_rehearsal(...)` is a rehearsal checkpoint only. It explicitly reports `actual_source_lock_performed = false`; it does not lock the live Google Sheet.

## Cutover readiness contract

Fourteen critical checks are represented.

AUTO checks include:

- one writable Master guard
- write-freeze rehearsal completed
- final backup reference recorded
- latest delta reconciled
- source validation clean
- duplicate source IDs = 0
- mapped FK orphan = 0
- POSTED journal batches balanced

Evidence/manual checks include:

- source removals reviewed when present
- file checksum mismatch = 0
- finance totals reconcile
- consent history intact
- RLS allow/deny tests pass
- Part 3 idempotency tests pass

A rehearsal may reach only `READY_TEST`. This status is not Production approval and does not enable cutover.

## Read-only API

Existing capability `migration_reconcile_read` controls:

- `api.migration_cutover_readiness(...)`
- `api.migration_delta_plan(...)`
- `api.migration_cutover_checks(...)`

No authenticated migration write/cutover API is exposed.

## Cutover rehearsal smoke — PASS

The transactional rehearsal tested two passes:

1. An invalid business ID produced `REVIEW_REQUIRED` / `NOT_READY`.
2. After source correction, archive review, and required evidence attestations, the rehearsal reached `READY_TEST`.

Delta composition in the successful rehearsal:

- 2 INSERT
- 1 UPDATE
- 1 SOURCE_REMOVED
- 1 UNCHANGED
- 0 invalid after correction

The removed source row became one archived scratch row.

Real Core Master rows written by the rehearsal: **0**.

A test defect was also caught and fixed: using transaction-stable `now()` to choose the latest reconciliation could select the wrong run. The engine now resolves the latest reconciliation from the latest `delta_batch.batch_version`.

## Canonical business ID namespace realignment

During Part 4G closeout, the current Founder Master, Control Index V3.6, and live `98_System_Config` were re-read.

Current authority explicitly preserves **`MYC-*` stable business IDs**.

Examples:

- Candidate `MYC-C-000001`
- Job `MYC-J-000001`
- Client `MYC-B2B-0001`
- Partner `MYC-P-0001`
- Placement `MYC-PL-000001`

The live Data Hub also currently contains Partner records `MYC-P-0001` and `MYC-P-0002` and sets the next Partner ID to `MYC-P-0003`.

The earlier `WC-*` PostgreSQL implementation was therefore identified as stale implementation state. Before realignment, the system verified that all relevant PostgreSQL Business Master / Docs / Finance / Privacy / Raw Input / DQ tables contained **zero persisted business rows**, so no real entity ID needed to be rewritten.

Migration 058 safely realigned:

- all ID allocators defined in live `98_System_Config`
- Core ID constraints
- Docs ID constraints
- Consent ID constraint
- Accounting IDs: Journal / AR / AP / Bank / Tax
- Raw Input / DQ ID constraints
- migration mapping ID regexes

Machine-readable guard:

`canonical_business_id_namespace = MYC`

Migration 059 verifies:

- canonical `MYC-P-*` is accepted
- stale `WC-P-*` is rejected by DB constraint
- stale `WC-P-*` is classified `ID_PATTERN_MISMATCH` by shadow validation
- allocator counters are not consumed
- test residue = 0

Historical Part 4E/4F status files record the implementation state at those times. They must not be used as current ID authority; current Founder Master + Control Index + live `98_System_Config` govern the namespace.

## Security / Performance

After hardening:

- Supabase Security Advisor: **PASS / 0 lint**
- missing FK indexes introduced by 4G were fixed
- explicit deny RLS policies exist for new 4G operation tables
- remaining Performance notices are only `unused_index` INFO in the low/no-traffic TEST environment

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Final state after Part 4G

Supabase migration count: **59**.

Operational state remains:

- `canonical_business_id_namespace = MYC`
- `current_operational_source = GOOGLE_SHEETS_DRIVE`
- `migration_shadow_write_enabled = false`
- `migration_rehearsal_enabled = false`
- `migration_freeze_rehearsal_enabled = false`
- `migration_delta_capture_enabled = false`
- `migration_target_apply_enabled = false`
- `migration_cutover_enabled = false`
- `production_cutover_approved = false`

Production cutover has **not started**.

## Part 4G migrations

- `050` cutover rehearsal foundation
- `051` delta rehearsal engine
- `052` rehearsal reconciliation/readiness foundation
- `053` readiness engine
- `054` read-only API
- `055` latest reconciliation selection fix
- `056` cutover rehearsal smoke
- `057` RLS/FK-index hardening
- `058` canonical MYC ID realignment
- `059` canonical MYC ID smoke

## Boundary after 4G

The migration mechanics can now be rehearsed and objectively gated in TEST, but the system still cannot switch the live writer or perform a Production cutover.

Next safe implementation track: **Part 4H — Part 4 Closeout / Production Readiness Evidence Package**, then continue security/reliability Production-gate implementation before any live cutover.
