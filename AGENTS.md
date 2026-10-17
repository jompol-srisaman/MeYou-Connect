# MeYou Connect — agent working instructions

## Purpose and authority

Help the Founder complete work with minimal coordination. Communicate in clear Thai by default. Continue authorized, reversible work without repeatedly asking permission; escalate missing access, genuine decisions, and irreversible actions with concrete evidence.

- Repository: `jompol-srisaman/MeYou-Connect`.
- Existing MYC Supabase TEST project: `pgjmxdeafzogzsyawejs`. Confirm connector account and project before every database operation; do not use unrelated AIOS projects.
- Operational business Source of Truth remains Google Sheets + Google Drive. PostgreSQL business masters are intentionally pre-cutover.
- Business IDs use `MYC-*`. Do not invent a new master, ID format, lifecycle, ownership, financial event, or promotion path.
- Current explicit user instructions govern scope. Draft proposals and historical documentation are context, not execution approval.

## Work in this order

1. **Orient.** Check the working directory, Git status, current branch, remote, relevant issue/PR, and any more-specific `AGENTS.md`. Preserve existing changes. Reuse a suitable checkout; isolate work when necessary.
2. **Read the handoff.** For recovery, read the three runbooks below and PR #29 / Issue #28. Read `docs/handoff/LOG.md`. Follow referenced documents only when they exist; report missing/stale references instead of inventing their contents.
3. **Define the next deliverable.** State the goal, allowed changes, dependencies, verification, and stop conditions. Separate observed facts, hypotheses, proposed changes, and completed actions. Prefer the smallest useful scope.
4. **Verify live prerequisites.** Re-read relevant runtime state using the correct connected account. Repository code, successful deployment, platform health, or old screenshots alone do not prove current behavior. Record timestamps and aggregate evidence without PII.
5. **Execute within authority.** Prefer existing tools/contracts and read-only inspection first. Inspect installed CLI help before using unfamiliar commands. Keep one owner for shared live state. Never turn an access problem into a privilege bypass.
6. **Verify the result.** Check actual output and read back mutations. Run tests appropriate to the change; documentation-only edits need diff/link/consistency checks. Mock tests establish only their simulated scope. Do not claim unrun integration, restore, or soak tests passed.
7. **Record and hand off.** Update the relevant runbook and prepend a concise entry to `docs/handoff/LOG.md`: task, actual changes, evidence, gate state, next step, blocker. Use the existing issue/PR as the shared review trail. Keep proposed code distinct from deployed code. Do not merge, close recovery, or announce PASS with unmet gates.

Current continuation: read `docs/runbooks/MYC_RECOVERY_EXECUTION_20261016.md` first for completed approved reclaim and deployed V4/capacity controls. Do not repeat the historical approval/password steps. For the existing `myc-recovery` heartbeat, follow `docs/runbooks/MYC_CAPACITY_MONITOR_OPERATIONS_20261017.md`, refresh the private dashboard from actual aggregates, and preserve truthful observation gaps. Never treat the passage of 24 hours alone as a passing soak.

## Recovery: mandatory gates, in sequence

Read:

- `docs/runbooks/MYC_POSTGRES_BACKUP_GATE_HANDOFF_20261016.md` — current backup/restore requirements.
- `docs/runbooks/MYC_RECOVERY_PROGRESS_20261016.md` — verified recovery evidence and remaining work.
- `docs/runbooks/MYC_SUPABASE_FREE_TIER_RECOVERY_20261016.md` — historical diagnosis and conditional recovery procedure. Its sample cleanup SQL is not authorization.

### 1. Preserve and inspect

- Cron #11 (`myc_datahub_shadow_import_5min`) must stay inactive. Preserve unrelated jobs.
- Preserve `business_master_apply_enabled=false`, `migration_target_apply_enabled=false`, and `production_cutover_approved=false`; no master cutover.
- Re-read DB version/physical size/read-only state, writer activity, schemas/extensions, shadow sessions/history, dependencies, backup controls, and source/evidence ownership.
- Preserve Raw LINE, both shifted and canonical repaired Sheet copies, sync references, Candidate/Finance data, source evidence, and distinct historical shadow versions. No inbound foreign key does not prove a row is disposable.

### 2. Full PostgreSQL backup

- Use authenticated direct or **Session Pooler** PostgreSQL access with PostgreSQL 17-compatible tools. Do not use transaction pooling for this task.
- Require a complete, consistent logical dump covering application/custom schemas, auth/storage metadata, shadow rows/sessions, functions, triggers, policies, grants, sequences, and extensions as permissions permit. Export role definitions without password hashes when supported.
- Account explicitly for every unreadable/excluded object or schema; otherwise the full-backup gate fails. A SQL sample, row-hash export, Sheets copy, or repair checkpoint is insufficient.
- Save artifacts and manifest in durable, access-controlled storage outside the affected project and outside Git. Record source/snapshot identity, versions, options, exclusions, start/end, bytes, SHA256, and destination identity. Re-read and hash the independently stored bytes.
- Database dumps do not contain Storage object bytes. Inventory and preserve those separately for the relevant recovery/deletion scope.

### 3. Actual isolated restore and comparison

- Restore only into a disposable, compatible local PostgreSQL/Supabase environment with required roles/extensions. Never restore into the live MYC database or an existing unrelated local database.
- Isolate restored jobs, subscriptions, triggers, and network-capable extensions from external services. Restoring a backup must not activate copied schedules or contact production.
- Fail on restore errors; record every exception. `pg_restore --list` and checksum checks are preliminary checks, not a restore test.
- Compare schemas, exact table/row counts, sequences, constraints/relationships, function definitions, policies/ACLs/ownership, source/evidence linkage, distinct historical versions, and Raw/Candidate/Finance integrity.
- Use the same consistent snapshot for source comparisons and dump. Independent live counts are preflight evidence, not automatic point-in-time parity. Account separately for sequence state and changes outside MVCC snapshots.
- Record private manifest/actual restore log and a redacted result in the recovery review trail. Register a successful independent backup in existing controls only after verified artifacts and restore evidence exist.

### 4. Deletion approval and subsequent recovery

- **No deletion, TRUNCATE, DROP, CASCADE, destructive migration, or space-reclaim operation before backup + isolated restore PASS and explicit Founder approval of the exact disposal scope.** Do not execute cleanup samples from documentation.
- First prepare exact SQL, retained/archived versions and counts, dependencies/provenance, physical reclaim estimate, lock/timeouts, and rollback path. Backup PASS does not itself authorize deletion.
- After approved reclaim, prove capacity below Free quota with headroom, stable actual external read/write, guard/retention/dedup/concurrency/capacity notifications on restored data, LINE/media recovery, source-matched finance reconciliation, live E2E, and bounded growth over 24 hours.
- Cron #11 remains off until all original restart gates pass and activation is authorized. Temporary session writes or platform `ACTIVE_HEALTHY` do not establish recovery.

## Secrets and blockers

- Never commit or print credentials, password-bearing connection URLs, role password hashes, dump contents, candidate PII, bank details, or private evidence into chat/GitHub/logs.
- Use approved existing local environment/password prompts/secret stores. Inspect secret **names and metadata** before deciding whether access exists. Do not scan unrelated personal projects or secret stores for credentials.
- A ChatGPT/Supabase SQL connector session is not a PostgreSQL password for local `pg_dump`. A GitHub login or API/service-role key is not that password either.
- If DB credentials are missing, inspect documented setup and authorized GitHub workflow/secret metadata. Report the exact missing prerequisite and what can proceed independently. Do not claim backup started or use repeated retries to hide missing authentication.
- No password reset, temporary privileged API, paid plan/API, new Supabase project/paid branch, or architecture change is authorized by the recovery handoff. Obtain a specific scope change before doing any of these.

## Subagents and efficient execution

- When the user authorizes delegation, use `gpt-6-luna` (Luna 6) for bounded tasks it can handle: read-only document/code audit, acceptance checklists, test review, and focused changes with clear verification. Choose effort deliberately; pass concise context.
- Delegate only independent work, with explicit inputs, allowed paths, forbidden actions, expected output, and verification. Never give multiple agents ownership of the same live mutation or overlapping file edits.
- Keep live backup/restore and production-state decisions under the primary agent. Review subagent findings and independently verify material claims.
- Batch independent reads. Avoid unnecessary full-database scans, repeated unchanged polls, unrelated refactoring, or rebuilding evidence already established. If an approach repeatedly fails, diagnose the prerequisite and change approach.

## Completion report

Report what changed, what was actually verified, what remains blocked, and the next concrete action. Include evidence links. Keep recovery status **INCOMPLETE** until every required gate has passed; never equate a prepared environment or documentation with a completed backup.
