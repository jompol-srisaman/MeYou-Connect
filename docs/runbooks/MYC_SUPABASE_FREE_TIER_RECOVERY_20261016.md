# MYC P0 — Supabase Free database recovery (16 October 2026)

**Status:** RUNBOOK / NOT EXECUTED. Founder-approved goal: restore the existing MYC project without new paid API, losing business data, or changing canonical architecture.

**Project:** `pgjmxdeafzogzsyawejs`. **Owner:** MYC Founder + MYC Engineer. **Related issue:** #28.

## 1. Observed evidence and immediate constraint

Founder ran a read-only Postgres size query on the MYC project:

| Relation | Total |
| --- | ---: |
| `ops.shadow_import_rows` | **1,487.10 MB** |
| `ops.raw_inputs` | 13.09 MB |
| `cron.job_run_details` | 13.48 MB |
| `ops.ingress_request_log` | 5.13 MB |
| `ops.shadow_import_sessions` | 2.05 MB |

Supabase UI: Free quota exceeded, Database read-only, Disk ~95%, unhealthy. Original source: Founder-supplied screenshot and query. These are *not* a fresh database read from the MCP connection. Supabase connector currently cannot enumerate or query the MYC project even though Founder dashboard shows it. **No live recovery action has been performed.**

[Supabase official database/disk/read-only recovery instructions](https://supabase.com/docs/guides/platform/database-size).

### Proven data-flow facts from existing repo

- `docs/handoff/LOG.md` (29 Sep): `datahub-shadow-import` LIVE and scheduled every **5 minutes** for 6 Google Sheets entities. This could produce repeated full-snapshot staging sessions.
- Migration `20260829180010_part4_wave4f_shadow_migration_foundation.sql`: `shadow_import_rows` has `session_id`, `raw_record` and `normalized_record` JSONB and row-level validation; FK to `shadow_import_sessions`. Staging is unique *within* a session, not across sessions.
- Migration `20260829180223_part4_wave4f_reconciliation_engine.sql`: `ops.stage_shadow_row` upserts only for identical `session_id, source_sheet, source_row_number`; it **does not deduplicate snapshots across distinct session IDs**.
- `README.md`: Edge Function `datahub-shadow-import` live function source is not in repo; do not assume a GitHub change deploys the running function.
- Operational source of truth remains **Google Sheets/Drive**; `core.*` and `finance.*` business masters being empty is **intentional before cutover** (`business_master_apply_enabled=false`). Do not turn gates on to solve disk capacity.
- Probable root cause: repeated staging copies, **not yet proven until SQL audit**.

## 2. Read-only forensics — run these first (NO WRITES)

Run in the Supabase SQL Editor in the MYC project. Copy aggregate results to the issue, **not raw PII or credentials**.

```sql
-- A. Current size and access mode
SELECT current_setting('transaction_read_only') AS transaction_read_only,
       pg_size_pretty(pg_database_size(current_database())) AS database_size,
       pg_size_pretty(pg_total_relation_size('ops.shadow_import_rows')) AS shadow_rows_size;

-- B. Shadow sessions lifecycle and growth
SELECT status, count(*) AS sessions, min(created_at) AS oldest,
       max(created_at) AS newest
FROM ops.shadow_import_sessions
GROUP BY status ORDER BY sessions DESC;

SELECT session_id, source_system, source_file_name, status,
       snapshot_at, created_at
FROM ops.shadow_import_sessions
ORDER BY created_at DESC LIMIT 10;

-- C. Approximate table statistics (cheap; avoids a huge full-table scan)
SELECT relname, n_live_tup, n_dead_tup, last_autovacuum, last_autoanalyze
FROM pg_stat_user_tables
WHERE schemaname = 'ops'
  AND relname IN ('shadow_import_rows', 'shadow_import_sessions', 'raw_inputs');

-- D. Job definition: do not assume jobid or that it is the sole webhook
SELECT jobid, jobname, schedule, command, active
FROM cron.job
WHERE command ILIKE '%shadow%'
   OR jobname ILIKE '%shadow%'
   OR command ILIKE '%datahub-shadow-import%';

-- E. Are there unexpected FK dependents of staging rows?
SELECT conname, conrelid::regclass::text AS referencing_table
FROM pg_constraint
WHERE contype = 'f'
  AND confrelid = 'ops.shadow_import_rows'::regclass;
```

If the 1.5GB mainly consists of recent sessions or data not reproducible from Sheets, **stop** and investigate source completeness. Do not purge blindly.

## 3. Back up first (MANDATORY BEFORE DESTRUCTIVE STEPS)

1. Freeze any planned business cutover. Leave `migration_target_apply_enabled`, `business_master_apply_enabled`, `production_cutover_approved` OFF.
2. Export a complete Postgres backup with `pg_dump --format=custom --no-owner` to an access-controlled **off-project** folder or secured workstation. Credentials must be kept out of GitHub and chat. Verify `pg_restore --list` and backup size/checksum; preferably test restoration in an isolated environment.
3. Preserve a copy of the recent Shadow Import session metadata and reconciliation evidence. Confirm active/pending staging sessions and reconciliation runs. The old snapshots might contain a historical state not available in the current Sheet.
4. Verify the live Sheets/Drive operational authority, recent finance evidence and LINE Raw retention. Never delete `ops.raw_inputs`, `ops.events`, `ops.domain_commands`, `finance.*`, `core.*`, or Storage evidence as a disk emergency shortcut.
5. No backup means **NO PURGE**.

## 4. Stop accumulation BEFORE reclaiming space

Under an authorized admin session, once the **exact** 5-minute Shadow Import job is identified, temporarily disable/unschedule **that job alone**, while preserving its SQL command/schedule for later restoration. Do not disable LINE ingestion, business event processing, or unrelated cron jobs.

The database is currently read-only. Supabase documents a temporary override within SQL Editor using:

```sql
SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE;
```

Keep this in the **same SQL Editor session** used for authorized maintenance. Do not change a global safety gate, server configuration, RLS or privileges merely to free disk space.

**Only once job identity is verified**, an authorized operator can use:

```sql
-- Illustrative ONLY: replace with the inspected exact jobid
-- SELECT cron.unschedule(<verified_shadow_import_jobid>);
```

Record the job's original `jobname`, `schedule`, and `command` and verify that it no longer runs.

## 5. Space reclamation — CONDITIONAL/NOT PRE-APPROVED SQL

Do **not** execute until the backup, business-authority, dependency and staging-life-cycle checks above pass, and the Founder approves the exact dataset disposal.

**Important:** `DELETE` of 1.5GB may leave the table physically large. `VACUUM FULL` can require considerable extra disk and exclusive lock, making it a poor first response at 95% disk usage. `TRUNCATE` releases relation storage quickly but irreversibly removes all rows and requires an ACCESS EXCLUSIVE lock. Neither is appropriate without verified restorable backup.

If an authorized operator has positively proved every `ops.shadow_import_rows` snapshot is **recomputable temporary staging** and no referencing FK or in-progress migration depends on it, **one** supervised maintenance path is:

```sql
-- HUMAN-RUN ONLY AFTER VERIFIED BACKUP AND WRITER FREEZE.
-- SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE;
-- BEGIN;
-- TRUNCATE TABLE ops.shadow_import_rows;  -- NO CASCADE
-- COMMIT;
```

This deliberately leaves `ops.shadow_import_sessions` and reconciliation metadata untouched until independently reviewed (they may reference historical staged row counts). **Do not run this sample as a production migration.** It requires separate approval and human execution.

Then recheck database size, disk headroom, SQLSTATE read/write behavior, the scheduled job being stopped, and follow official Supabase recovery docs before enabling the webhook pipeline. Only if needed use official `SET default_transaction_read_only = 'off';` after reclaim and platform status inspection. A Free-plan organization Fair Use restriction based on billing-period *average* can persist until its daily average drops or the period resets, even if live DB size is now low.

## 6. Permanent fix to prevent next outage

**Do not simply restart the old 5-minute full-snapshot cron.** Require:

- Fetch and source-control deployed `datahub-shadow-import` function first; verify exact SHA/version and source of truth.
- Delta/hash-change staging by `entity_key + canonical source PK + content hash` (not a fresh full JSON row for every run); retain at most an approved count of successful snapshots, with safe archive/checkpoints.
- Session lifecycle cleanup after confirmed reconciliation, bounded/observable retention; no deletion of actual Raw LINE or evidence.
- Decrease schedule frequency or use change-triggered sync with backpressure. The interval must reflect real business needs and free-tier headroom.
- Separate operational business data, auditable raw events, and reconstructable shadow staging; privacy TTL for PII and carefully controlled external archives.
- Emit database size/snapshot-growth warning at 250MB, intervention at 350MB, and stop shadow staging at 400MB (proposed conservative thresholds, **not a current Supabase limit**). Verify alerts are not self-amplifying logs.
- Run E2E after restoration: LINE webhook intake → raw/unique message ID → datahub reconciliation → Sheet source-first sync → Candidate/Partner → finance (pending/collected/paid) without duplicate leads/payments. Check messages since `MYC-RAW-004685` and the missing LINE image media cases separately.
- Future LINE OA, more groups, Facebook Page: one canonical event envelope + per-channel adapters + idempotency keys and bounded retention. Avoid cross-project data fragmentation as a way to bypass storage caps. Real user volume may eventually exceed Free; monitor and decide based on measured growth, not speculative unlimited-free promises.

## 7. Completion evidence / gate

Recovery is **DONE only if**: (1) source backup verified; (2) live DB <500MB with room to grow; (3) no read-only errors; (4) actual permitted write/read-back passes; (5) importer rate/retention fixed; (6) 24h growth test stays bounded; (7) LINE backfill and named ✅/❌ roster audit complete; (8) Founder receives an evidence-linked report.

**Security:** Never put bank details, real candidate PII, LINE ID/contents, Supabase service-role credentials, database connection passwords, storage secrets, or backup blobs in GitHub.
