# MYC recovery progress — 16 October 2026

Status: INCOMPLETE. This report supersedes stale live-status claims in the initial runbook, not the canonical business flow.

## Verified live evidence (07:17–07:25 UTC)

- Project pgjmxdeafzogzsyawejs, organization MeYou Connect, plan free; platform ACTIVE_HEALTHY does not establish database capacity recovery.
- Initial database 1,646,922,899 bytes (~1,570.6 MiB), default/transaction read-only on. Cron11 inactive; other six jobs active.
- Shadow rows exact count 786,782; table physical size 1,559,339,008 bytes (~1,487.1 MiB). Sessions 3,028 (3,027 VALIDATED, one OPEN). No inbound FK to staging rows; zero reconciliation runs.
- Historical payload changes exist: Candidate 362 distinct row hashes, Cashbook27, Client3, Commission17, Data_Quality71, Job28, Partner10, Placement15. Do not equate every historical row with safely disposable data.
- Backup artifacts table empty. Existing backup records are not independently recoverable PostgreSQL dumps. Safety copy of operational Sheets has31 tabs; this is not a PostgreSQL backup.
- No database credentials or PostgreSQL client available in this executor; direct database hostname resolution fails. No off-project pg_dump or restore test completed. No purge authorized or performed.
- At07:21 UTC, independently observed default read-only off while size still1,647,463,571 bytes. This change was not made by this recovery session. A temporary-table write/read probe passed at07:22 UTC. It proves session SQL write capability only; persistent external writes, reclaimed capacity, and stability remain unproved.

## Sync integrity incident

Initially204 Raw LINE rows had no sync ledger entries (10–15 October). At07:20 UTC, ledger changed to4,730 SYNCED, matching4,730 raw records, without a sync action from this recovery session. Independent Google Sheets inspection then proved the204 new rows landed in **L4556:AI4759**, not the canonical A:X columns. Ledger row references did not record that displacement. A4536 contains the last properly positioned ID; L4556 contains the next ID. A-row scans alone therefore still miss204 records. A relative readback of returned append range can incorrectly pass while the absolute columns are wrong.

Patch `raw-datahub-sync-v5` anchors append to A1:X1 and refuses any returned range not starting at A, or whose width/row count differs. Shifted historical copies must be preserved while canonical rows are repaired and ledger references verified. No clearing/moving/deleting originals is part of this patch.

## Shadow importer patch (NOT DEPLOYED)

- Hashes allowlisted source content plus entity scope/row positions, not invocation timestamp.
- Default is dry-run; actual imports require explicit dryRun=false.
- Unchanged snapshots skip all staging writes; unknown entities/missing headers/history read failures fail closed.
- Input budget1,000 rows /2MiB per snapshot; DB guard handshake prevents staging on an unpatched DB.
- SQL review draft preserves existing RPC signatures, owners/ACLs, empty search_path and safety gates. Serializes session admission, rejects duplicate content hashes, refuses legacy timestamp-only snapshots, caps20 hashed sessions, stops at400MiB database/50MiB shadow relation, limits rows and row bytes.
- No new tables, master entities, canonical-flow changes, deletion jobs, cron activation or business-master cutover.
- Proposed retention: after verified external archive and explicit deletion approval, keep at least latest2 successful snapshots and7days of change history; preserve unresolved OPEN/invalid/reconciliation evidence and every distinct historical version externally. When the cap is reached, stop with SHADOW_RETENTION_ARCHIVE_REQUIRED rather than delete unbacked rows.
- Capacity warning250MiB; hard stop400MiB. Warnings go to function logs; no proactive notification channel configured or tested. Draft SQL has NOT been applied or tested on restored PostgreSQL.

## Tests

`node --test tests/*.test.mjs`:18 tests passed in local Node24, including288 simulated five-minute unchanged invocations producing one snapshot; content changes; fail-closed guards; absolute append alignment. These are mocked transport tests, not a24-hour production soak, Deno typecheck, full SQL guard test, or live E2E pass.

## Business reconciliation

Latest downstream outcome source is MYC-RAW-004719 (15Oct08:12 UTC): four positive, five negative. Follow-up payment promise MYC-RAW-004720 is not collection evidence. Two outcome names require alias/identity review before changing master status. No business finance amounts, collection or paid status may be inferred solely from emojis.

## Remaining gates

1. Secure PostgreSQL dump from an environment with actual DB connection, independent durable copy, checksum, restore into isolated compatible PostgreSQL, verify schema/tables/counts/sequences/constraints and application-critical data. Storage file bytes require separate coverage.
2. Review a concrete reclaim scope against full verified backup; obtain explicit Founder deletion approval. Never CASCADE or assume all history is disposable.
3. Reclaim physical capacity, verify below Free cap with headroom, then persistent authorized SQL/API read-write tests and provider capacity state.
4. Test SQL guards on restored copy, deploy guard+importer with Cron11 off, prove concurrency/retention/capacity alerts; only then consider approved restart.
5. Finish actual Sheets readback, raw/LINE message/media gap audit, source-matched Candidate/Finance reconciliation, live E2E and24-hour growth evidence.

## Actions completed in this continuation (verified by07:34 UTC)

- Deployed `raw-datahub-sync` version9 (`raw-datahub-sync-v5`), verify_jwt=true; read back source equals tested patch. Bundle SHA256 `10ef7a35ada2fb5cc622f77249d357a366c8a357c8224f06ed03493594722184`.
- Saved a private off-project **repair checkpoint only** (87,907bytes, SHA256 `417ae7f7da4e90552a452c380c705500850684d9ed54a80495ffb27954e87b0f`), with204 shifted rows and original ledger state. Archive members were reread and their SHA256 verified. It is not a PostgreSQL backup and authorizes no purge.
- Copied all204 rows into the verified-empty canonical A5001:X5204 range in the existing raw sheet. Compared every one of4,896 cells after write. Original L4556:AI4759 copies remain intact; nothing was cleared/deleted.
- Updated only matching204 sync-ledger row references, with checksum+old-reference predicates and an exact204-row assertion in one transaction. Read back first/last references5001/5204 and repaired count204. Default read-only had reverted on: the first normal UPDATE failed25006 and made no change; a bounded explicit READ WRITE maintenance transaction succeeded. No global read-only setting was changed by this continuation.
- Live HTTP `health`:200, app versionv5, correct spreadsheet/header map. Live HTTP `replayRawIds`:200; first/outcome/latest tested IDs each occur exactly once at canonical rows5001/5184/5204; appended0, duplicateRows0. This tests readback/replay; no new fake LINE event or production append was generated.
- Compared ALL4,730 database Raw IDs against the canonical Sheet ID column: missing0, duplicates0. Sheet has4,738 canonical IDs, including8 historical Sheet-only records, all retained.
- Wrote and read back76 exact Candidate/Tracking cells for9 outcomes. Four exact positives are now `รอการเงิน` (waiting finance); three exact negatives retain no newly earned entitlement; two spelling mismatches are explicitly held for identity review. Existing Candidate lifecycle statuses, ownership, finance amounts and COLLECTED/PAID data were preserved. No unproved cash receipt or payout was recorded. See private Founder report for named evidence; no PII is committed here.
- Final07:33 UTC snapshot: default read-only **on**, database1,647,520,915bytes (~1,571.2MiB), Cron11false, shadow786,782, raw4,730, sync4,730, orphan raw-map0, backup_artifacts0. No physical reclaim occurred; P0 remains open.
- Last24-hour function logs include17 LINE group-webhook HTTP200 responses (latest15Oct12:53 UTC); that does not prove messages never failed before reaching the webhook. Historical raw/provider/media gap audit and new-event live E2E remain open.
- Security advisor currently reports2 anon SECURITY DEFINER warnings,9 authenticated function warnings,1 leaked-password-protection warning, and1 RLS-no-policy info. Do not reuse historic “0 lints” claims. No permission/RLS change was made as part of this capacity repair. In particular, review `public.list_candidates` and `public.list_cashbook` against the existing API security contract. Remediation: https://supabase.com/docs/guides/database/database-linter?lint=0028_anon_security_definer_function_executable .

Connection/backup continuation instructions: [PostgreSQL backup gate handoff](MYC_POSTGRES_BACKUP_GATE_HANDOFF_20261016.md). Do not claim the independent full DB backup, restore, physical recovery, production shadow fix, proactive alerts, end-to-end recovery, or24-hour soak complete.

Media readback: file_intake has165 MIRRORED records with size/checksum and5 SOURCE_NOT_MIRRORED records without checksum (two have size metadata). Those five file recoveries are not complete.
