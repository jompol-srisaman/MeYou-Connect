# MYC Shadow Import reclaim — exact Founder approval package

**PROPOSED ONLY. No source cleanup has run.** PostgreSQL backup + actual isolated restore [passed](MYC_POSTGRES_RESTORE_RESULT_20261016.md); approval is required by the Founder's explicit instruction before deleting any source data. This package changes live historical availability, so it is a Founder decision.

## Decision requested

Approve `MYC-RECLAIM-20261016-749964`: preserve the full historical archive externally; retain **36,818** selected Shadow rows in Supabase and remove **749,964** older rows from live staging. Keep **all3,028 session metadata rows**, including the OPEN session, and preserve all4 invalid rows. Allow a short shadow-only maintenance window (plan2–5 minutes; actual external timing must be checked), a bounded maintenance login and temporary freeze of `migration_shadow_write_enabled`. No master/cutover gate activation or Cron11 restart is included.

Historical staging outside the retained set becomes **archive-only**. Full original history remains in both verified `full.dump` copies, not in the retained CSV. The source tables, Google Sheets/Drive evidence, raw LINE rows, ledger, core and finance tables, Storage objects and unrelated Cron jobs are outside the disposal scope.

## Fixed retention scope and provenance

Snapshot16Oct08:42:41 UTC; fixed seven-day cutoff **09Oct08:42:39 UTC**. Keep the union of:

1. Every non-VALIDATED session, including the OPEN session.
2. Sessions at/after the cutoff.
3. Latest two VALIDATED snapshots per `(source_system, source_file_id, expected_entities)` by snapshot/creation/session ID descending.
4. Entire sessions containing invalid/staged/problem rows or nonempty validation issues.
5. Any reconciliation, delta, rehearsal or cutover-linked sessions. All related run/target/delta tables are currently empty; any new record makes this exact package abort and require re-preparation.

This yields106 kept sessions (105 with rows and1 empty OPEN). Every one of the533 distinct historical payload versions is in the full external archive. No claim is made that all533 remain in live staging. Session status/metadata remain historical facts even where old row payloads are archived; old-session reconciliation must first rehydrate the relevant archived rows in isolation.

| Entity | Before | Keep live | Archive-only |
|---|---:|---:|---:|
| Candidate |500,737|24,735|476,002|
| Cashbook |51,788|2,167|49,621|
| Client |9,069|303|8,766|
| Commission |30,100|1,628|28,472|
| Data_Quality |94,620|3,804|90,816|
| Job |51,425|1,751|49,674|
| Partner |27,773|1,010|26,763|
| Placement |21,270|1,420|19,850|
| **Total** |**786,782**|**36,818**|**749,964**|

Private retained CSV:58,406,116bytes, SHA256 `51a63e87f035b0f1dd5a7ea74ee2b0621d0a50a186bc3d7e455393cc5689c35a`. It is a roll-forward input containing only kept rows; it is **not** the discarded-history archive. The full archive's actual214-table restore already reproduced every historical row. A separate table-only extraction/restore from that archive tests full-shadow rollback; see private `reclaim/scoped-rollback-result.json`.

Expected logical row fingerprints, using the same UTC/float/JSON64-bit-MD5 sum method as backup comparison:

- Original786,782: `-3216402315079991706826`.
- Keep36,818: `-2770658449854450349`.
- Archive-only749,964: complementary sum `-3213631656630137256477`; all included in the restored original set. Artifact integrity uses SHA256 independently.

## Dependencies and live recheck

No inbound FK to `ops.shadow_import_rows`; outgoing session/entity-map relationships remain intact. Relevant dependent views: `dash.shadow_latest_rows_v`, `dash.shadow_latest_session_v`, `dash.sync_health_v`. Relevant functions include `ops.build_delta_batch`, `ops.count_rehearsal_fk_orphans`, `ops.evaluate_cutover_readiness`, `ops.load_baseline_into_rehearsal_target`, `ops.reconcile_rehearsal_target`, `ops.reconcile_shadow_session`, `ops.stage_shadow_row`, `ops.validate_shadow_session`. Absence of an FK is not a disposal justification; the historical archive and retained provenance supply that justification for this proposed staging scope only.

At **14:10:28 UTC /21:10 Bangkok**, source shadow count and full content fingerprint still match the08:42 snapshot exactly; sessions3,028, relation1,559,339,008bytes. Live Raw4,749 (17 newer than the backup), all preserved by this plan. DB1,647,651,987bytes, default read-only on, Cron11false, three cutover gatesfalse, current shadow-write gatetrue. Registration added3 verified artifacts, without changing business data.

Before execution, re-check under the maintenance locks: unchanged exact shadow count/fingerprint, session count, references, source endpoint, backup SHA/readback + restore evidence and source snapshot age <=24h. If scope or freshness differs, stop and refresh the package/evidence before deletion. Raw growth alone does not change this shadow-only set; never replay the entire snapshot over current production.

Both phases assert all-session metadata fingerprint `62814098099219885444`, not just session count. Phase A also recomputes the fixed retention union under lock and requires36,818 rows/exact retained content fingerprint. Same-count status/time/source/metadata changes therefore abort before TRUNCATE. The caller-set approval marker is only an accidental-execution tripwire; it is not authorization. Keep the actual Founder approval record separate and restrict the maintenance login.

The additional guards were tested in isolated transactions with rollback: the unchanged full source-snapshot set passes; a one-session metadata change with unchanged row count is rejected with `SESSION_METADATA_CHANGED_REPREPARE`; Phase B's final guard block passes against an empty disposable target. No test change persists in the verified full restore. Live source session fingerprint was independently re-read and matched at14:15:24 UTC.

## Physical method, timeouts and execution

Source physical relation1,559,339,008bytes (~1,487MiB); Dashboard reported a2GB disk at95% usage (database/WAL/system share it). Avoid holding an extra full relation on that disk. A normal DELETE would not return physical space.

The proposed method releases the old file **before** loading the small verified retained subset. Exact review scripts:

- [Phase A: locked assertions and TRUNCATE without CASCADE](sql/MYC_SHADOW_RECLAIM_PHASE_A_REVIEW.sql).
- [Phase B: COPY retained rows and assert content before COMMIT](sql/MYC_SHADOW_RECLAIM_PHASE_B_REVIEW.sql).

Sequence after explicit approval:

1. Re-read both external dump/manifest and retained CSV copies, endpoint and approval scope. Freeze only shadow writes; Cron11 remains off. Confirm no active shadow writer and no changed reconciliation/cutover reference. Do not change other jobs or cutover gates.
2. Use a short-lived maintenance login (local secret only; no main password reset). Give metadata read access and only `INSERT`/`TRUNCATE` needed on the shadow table. It must have no master-write privilege. Freeze-setting changes use the existing authorized SQL channel, not this login.
3. Run Phase A: bounded explicit READ WRITE transaction, locks on session metadata and staging table, lock_timeout5s/statement_timeout180s. Assert exact original set and gates, TRUNCATE **without CASCADE**, COMMIT. This commit creates a brief empty shadow/dashboard window.
4. Immediately run Phase B through the same verified Session Pooler endpoint: client-side COPY of the private retained CSV, explicit READ WRITE transaction with the same locks/timeouts. Assert36,818 rows, original stable IDs/content fingerprint and4 invalid rows before COMMIT. No other table is rewritten.
5. Compare latest-view content (exclude only clock-derived `lag_minutes`), all session metadata, raw/ledger, constraints and cutover gates. Measure actual relation/database/disk/WAL capacity. Expire/revoke maintenance access. Keep shadow writes and Cron11 off until guard/restart tests pass.

Physical estimates depend on actual COPY/index/WAL behavior. Private exact-method rehearsal records before/after size, elapsed time and WAL in `reclaim/rehearsal-result.json`; use that measured result rather than promising an exact1.487GB refund. Provider read-only removal is verified afterward; do not globally force writes merely to mask insufficient capacity.

**Exact-method isolated rehearsal PASS,14:12:28–14:13:38 UTC:** original relation1,342,234,624bytes (already less bloated than source); after Phase A40,960bytes; after Phase B61,038,592bytes (~58.2MiB); database138,235,027bytes (~131.8MiB). Phase A24.449s, Phase B9.747s; generated WAL66,133,536bytes (~63.1MiB). The source-size projection is **1,498,300,416bytes reclaimed (~1.50GB /1.40GiB)** and DB~149,351,571bytes (~142.4MiB), subject to actual production measurements and unrelated growth. Private CSV SHA was checked first; missing approval marker aborted safely; raw/ledger/all3,028 sessions and latest dashboard content matched before/after,4 invalid rows preserved. Only `sync_health_v.lag_minutes` was excluded from view comparison because it changes with the clock; source timestamps/entity/freshness matched. An earlier rehearsal rejected the unnormalized clock-derived value and is retained as a diagnostic attempt.

## Rollback and failure handling

- Before Phase A COMMIT: any assertion/lock/timeout failure rolls back with original rows intact.
- After Phase A COMMIT: SQL ROLLBACK cannot resurrect the truncated file. Keep the shadow gate frozen and rerun verified Phase B to restore the36,818 rows; checksum/empty-target assertions prevent an unintended mix. If a COPY transaction fails, it rolls back and the target remains empty for a clean retry. The original table definition, grants, indexes and session IDs remain.
- Full historical recovery is separately tested **on the disposable clone**: `pg_restore --data-only --table=shadow_import_rows` from the verified full dump into a private SQL file, then one transaction importing that table's data into an empty same-schema target. Assert786,782 rows and original fingerprint. Never restore all database tables over newer live Raw data.
- That table-only rollback passed: extracted SQL1,194,678,099bytes, SHA256 `724161e818d1872493498a034f3d691fe1d317979488c6988ae643daa580e43b`; actual table restore181.534s,786,782 rows/full original fingerprint matched. The final fresh full-database verification container remains pristine; only the older disposable clone was used for reclaim/rollback rehearsals.
- The primary production failure path is bounded retained-row roll-forward. Full historical rehydration remains available locally; restoring the entire bloated history to the same2GB live disk could recreate the capacity incident and requires a fresh disk/WAL feasibility check. This approval does not authorize paid upgrades or a new architecture.

## Guard and recovery work after approval

The current draft50MiB shadow stop is **below** the retained relation footprint (~58MiB), so it will intentionally reject imports after reclaim. Do not deploy it and claim imports recovered. Resolve the cap using the measured retained baseline and Free-tier headroom, then test admission/staging below the cap and fail-closed at cap, duplicate snapshots, concurrent starts, row/payload budgets, the20-hashed-session retention stop and alert delivery. Do not silently discard extra protected history to fit a threshold.

After those restored-data tests, deploy the approved guard/importer version through the existing architecture, verify actual external writes and LINE/media/finance behavior, perform live E2E and24-hour bounded-growth observation. Cron11 remains inactive until the original restart conditions pass and activation is authorized. Five unmirrored files, external document/object bytes and source-matched finance evidence remain separate open recovery work.
