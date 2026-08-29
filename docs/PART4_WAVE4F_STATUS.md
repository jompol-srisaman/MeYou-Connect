# Part 4 Wave 4F — Migration / Reconciliation Harness

Status: **CLOSED / PASS**
Date: 2026-08-30 (Asia/Bangkok)
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Part 4F was built from the current Data Hub migration contract rather than inventing a separate migration model:

- `MEYOU_CONNECT_MVP_DATA_HUB_V1`
- `97_Migration_Map`
- `98_System_Config`
- current Core / Docs / Privacy / Finance PostgreSQL schemas

Operational Source of Truth remains Google Sheets + Google Drive.

## Implemented

### Shadow migration control

- `migration_shadow_write_enabled = false`
- `migration_target_apply_enabled = false`
- `migration_cutover_enabled = false`

Part 4F contains **no function that applies staged rows into Master tables**.

### Mapping catalog

`ops.migration_entity_map` tracks:

- source sheet
- target schema/table
- source and target primary keys
- Source of Truth
- migration priority
- sensitivity
- canonical ID regex where defined
- compare fields
- target readiness

Mapped entities include Candidate, Job, Client, Partner, Placement, Dorm, FollowUp, Revenue, Expense, Commission, Transport, Evidence, Consent, Content, Activity, AI Automation, Risk, Raw Input, File Registry and Data Quality.

Entities whose target tables do not yet exist are explicitly `target_ready = false` instead of being silently redirected.

### Shadow staging

- `ops.shadow_import_sessions`
- `ops.shadow_import_rows`
- source row number + source PK preserved
- original row JSON and normalized JSON separated
- row change-detection hash
- staging is idempotent by session + source sheet + row number

### Validation

`ops.validate_shadow_session(...)` detects:

- missing source PK
- canonical ID pattern mismatch
- normalized PK mismatch
- duplicate source PK
- target not ready

Invalid source rows are not normalized into a guessed business ID.

### Reconciliation

- `ops.reconciliation_runs`
- `ops.reconciliation_results`
- `ops.reconciliation_summary_v`
- `ops.reconcile_shadow_session(...)`

Supported result types:

1. `MATCH`
2. `SOURCE_ONLY`
3. `TARGET_ONLY`
4. `FIELD_MISMATCH`
5. `INVALID_SOURCE`
6. `UNSUPPORTED`

Field mismatches retain source and target values in structured JSON for review.

### Read-only migration API

Capability: `migration_reconcile_read`

Granted to:

- Founder
- Secretary
- Data Audit

Read-only RPCs:

- `api.migration_reconciliation_summary(...)`
- `api.migration_reconciliation_issues(...)`

No authenticated migration-write or cutover RPC is exposed.

## Acceptance — PASS

Transactional smoke test validated all six reconciliation outcomes in one run:

- 1 MATCH
- 1 SOURCE_ONLY
- 1 TARGET_ONLY
- 1 FIELD_MISMATCH
- 1 INVALID_SOURCE
- 1 UNSUPPORTED

Additional checks:

- shadow gate blocks staging while OFF
- staging the same source row again does not duplicate it
- ID pattern mismatch is surfaced explicitly
- field-level mismatch is captured
- reconciliation does not mutate target Master rows
- target-apply gate remains OFF
- cutover gate remains OFF
- smoke transaction rolls back completely

Two implementation defects were found by the smoke test and fixed before closeout:

1. row hash function resolution under empty search path
2. PL/pgSQL record alias collision in reconciliation loop

## Post-test state

- Shadow Sessions: 0
- Shadow Rows: 0
- Reconciliation Runs: 0
- Reconciliation Results: 0
- `migration_shadow_write_enabled = false`
- `migration_target_apply_enabled = false`
- `migration_cutover_enabled = false`

## Live Data Hub read-only finding

A read-only check of the current Data Hub identified one real migration blocker in `04_Partner`:

- existing rows use `MYC-P-0001` and `MYC-P-0002`
- current `98_System_Config` defines canonical Partner IDs as `WC-P-*`
- PostgreSQL Partner mapping also requires `^WC-P-[0-9]{4}$`

Part 4F intentionally **did not auto-convert or rewrite these IDs**. They must be resolved through Source-of-Truth / DQ review before a real migration.

No live Partner name, phone number, or other PII was persisted into GitHub migration history during this review.

## Security / Performance validation

- Supabase Security Advisor: **PASS / 0 lint**
- explicit deny RLS policies exist on all new migration/reconciliation tables
- Performance Advisor has no new missing-FK-index blocker; remaining notices are unused-index INFO in the low/no-traffic TEST environment

## Migration history

Part 4F migrations:

- `040` shadow migration foundation
- `041` Core mapping
- `042` Finance mapping
- `043` Docs/Ops mapping
- `044` remaining/unsupported mapping
- `045` reconciliation engine
- `046` row-hash fix
- `047` reconcile alias fix
- `048` reconciliation smoke
- `049` explicit RLS deny

Supabase total after Part 4F: **49 migrations**.

## Boundary after 4F

The system can now stage and compare source snapshots safely, but it still cannot apply migration rows or switch the operational writer.

Next safe implementation track: **Part 4G — Delta Migration / Write-Freeze Rehearsal + Cutover Readiness Gates in TEST**, without enabling Production cutover.
