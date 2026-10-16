# MYC PostgreSQL backup gate — continuation on a connected workstation

This task is authorized recovery of existing project `pgjmxdeafzogzsyawejs`; no new project, paid API, paid upgrade, password reset, deletion, cron reactivation, or architecture change is authorized by this handoff.

## The one required Founder action

Open Codex Desktop in `jompol-srisaman/MeYou-Connect` on a machine able to connect to the existing PostgreSQL **Session Pooler**, then give that session this file. Supply any needed database connection only through a local secret/environment/password prompt. Never paste DB passwords, service-role keys, connection URLs containing passwords, or dump contents into chat/GitHub. The cloud session cannot export PostgreSQL using its SQL-only connector, has no PostgreSQL credentials, and cannot resolve the direct DB host.

## Current completed actions to preserve

- Cron11 inactive. Do not restart it.
- `raw-datahub-sync` deployed version9, application version `raw-datahub-sync-v5`, verify_jwt=true, bundle SHA256 `10ef7a35ada2fb5cc622f77249d357a366c8a357c8224f06ed03493594722184`.
- 204 misaligned raw rows preserved at L4556:AI4759; correct copies verified at A5001:X5204 in the existing raw tab. Ledger targets independently verified for all204. Do not delete either set during backup.
- All4,730 DB Raw IDs found exactly once in the canonical Sheets ID column, missing0/duplicate0. Eight historical Sheet-only IDs also exist; preserve them.
- Candidate/Tracking notes reviewed for9 outcomes:4 positive waiting collection,3 exact-name negatives,2 identity spelling holds. No finance amount, COLLECTED/PAID, commission payout, owner attribution or Candidate status lifecycle was invented.
- `business_master_apply_enabled=false`; preserve it. Core business master emptiness is intentional pre-cutover.
- Draft branch/PR29 contains18 passing mocked transport tests, proposed hash/budget/retention guard, and raw-sync regression fix. Shadow guard SQL and importer are NOT deployed.
- DB capacity remains ~1.57GiB and default read-only has reverted on; temporary session writes do not prove recovery.

## Perform backup and actual isolated restoration

1. Fetch the latest PR29 branch and read `MYC_RECOVERY_PROGRESS_20261016.md`. Re-read live DB sizes, Cron11 state, writers, schemas, source ownership, dependency and historical-version evidence.
2. Use actual PostgreSQL17-compatible `pg_dump`/Supabase CLI in the authenticated local environment. Inspect installed CLI `--help` first. Use direct/session connection, not transaction pooler. Do not reset credentials or create a temporary privileged public API to work around missing access.
3. Make a private, complete, consistent logical dump, including every business/ops/config/core/finance/custom schema, auth/storage metadata, shadow rows and sessions, functions/triggers/policies/grants/sequences/extensions as permissions allow. Export role definitions without password hashes separately when supported. Any excluded/unreadable schema must fail the full-backup gate until explicitly accounted for. A SQL sample or unique-hash export is insufficient.
4. Place the dump and manifest in durable, access-controlled storage outside the affected project. Keep personal data out of GitHub. Record start/end/source snapshot, versions, exclusions, sizes, hashes and destination identity. PostgreSQL backup does not include Storage object bytes; inventory and preserve those separately if they are in scope for deletion/recovery.
5. SHA256 the saved bytes and re-read the independently stored copy. `pg_restore --list` is a preliminary check, not a restore test.
6. Restore into a disposable compatible local Supabase/PostgreSQL environment with required roles/extensions. Never restore into production or create a paid Supabase branch/project. Fail on restore errors and record every exception; do not hide errors with unchecked flags.
7. Compare source/restore schemas, table/row counts, sequences, constraints, relationships, function definitions, source/evidence linkage, shadow distinct historical versions, Raw/Candidate/Finance integrity, and access controls. A changing source requires a consistent snapshot/count method; independently executed live counts are not automatically the same point in time as pg_dump.
8. Write a private manifest plus actual restore-test log and a redacted result to PR29/Issue28. Only verified artifacts may be recorded as a successful independent backup in existing backup controls.

## Stop for deletion approval with a concrete review package

After backup/restore PASS, produce the exact SQL, retained/archived versions and counts, dependency results, estimated physical reclaim, lock/timeouts and rollback path. Request Founder approval for that precise scope before executing destructive cleanup. No CASCADE. Do not equate absence of inbound FKs with proof that provenance/history can be discarded.

After approved reclaim, prove physical size below Free quota with headroom, stable read/write through the real external path, retention/dedup/concurrency/capacity notifications on restored test data, LINE/media backfill, source-matched finance reconciliation, live E2E and24-hour bounded growth. Cron11 stays off until those gates pass.
