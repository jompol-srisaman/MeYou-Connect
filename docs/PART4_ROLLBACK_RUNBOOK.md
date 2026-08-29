# Part 4 — Rollback Runbook

Status: TEST / PRE-PRODUCTION RUNBOOK

This runbook follows the canonical rule: **one writable Master at a time**. Google Sheets + Google Drive remain the operational Source of Truth until an explicitly approved cutover.

## Trigger rollback when

- critical reconciliation fails
- duplicate business IDs are detected
- FK orphan appears
- file checksum mismatch appears
- finance totals do not reconcile
- journal batches are unbalanced
- consent history is incomplete
- RLS allow/deny acceptance fails
- Part 3 idempotency/retry tests fail
- a material writer-switch defect appears after cutover

## Before any future cutover

1. Record a fresh Part 2 backup reference.
2. Record source revision/snapshot references.
3. Announce and acknowledge the short write freeze.
4. Preserve final delta and reconciliation reports.
5. Confirm rollback owner and communication path.
6. Confirm Sheets writer can be restored.

## Rollback sequence

1. **Stop PostgreSQL application writes** and external write adapters.
2. **Do not delete failed-cutover rows or logs.** Preserve event, trace, evidence and reconciliation history.
3. Keep `migration_cutover_enabled=false` until a new approved attempt.
4. Restore the Google Sheets/Drive writer endpoint as the sole writable Master.
5. Compare any PostgreSQL-only accepted effects against the final source snapshot.
6. Reconcile business IDs, finance, evidence/file mappings, consent and event effects.
7. Put unresolved differences into Data Quality review; do not silently overwrite the source.
8. Fix the cutover defect in TEST and rerun acceptance.
9. Require a new Founder/Architect approval before attempting cutover again.

## Financial rollback rule

Never infer money movement from database state alone. Preserve bank/payment evidence and reconcile before altering Revenue/Commission state.

`COLLECTED` must remain evidence-backed. A rollback must not manufacture, reverse or duplicate real payment evidence.

## File rollback rule

Do not destroy source Drive objects after a failed migration. File identity remains provider-neutral through File Registry metadata. If an object copy is suspect, mark/reconcile it rather than claiming a verified mirror.

## Event/idempotency rule

Do not replay blindly. Preserve `event_id`, `idempotency_key`, `trace_id`, event effects and DLQ/replay controls so rollback does not create duplicate Candidate, Revenue, Evidence or notification effects.

## Evidence to retain

- backup reference
- source revisions
- cutover/freeze timestamps
- delta report
- reconciliation report
- RLS test result
- Part 3 test result
- file checksum report
- finance reconciliation
- incident notes
- approved rollback decision

## Current state

Part 4H does not execute this rollback against Production because no Production cutover has occurred.
