# MYC full PostgreSQL backup and isolated restore — 16 October 2026

**PostgreSQL logical backup/restore gate: PASS. Overall recovery: INCOMPLETE. Source cleanup is NOT approved or executed. Cron11 remains inactive.** Continue from Issue28 / draft PR29, not from the older missing-password preflight.

## Verified artifact and scope

- Project `pgjmxdeafzogzsyawejs`, database `postgres`, source PostgreSQL17.6 / Supabase17.6.1.166. Client `pg_dump`, `pg_restore`, `pg_dumpall`:17.6, supplied by the existing Docker Desktop and official matching Supabase image. No pgAdmin or paid service installed.
- Official image digest: `sha256:d5424e9f4d0c21d63991c3f3dd77881f23f722c3a212452a61bc91924b79e8c8` (amd64). Source is aarch64; logical restore verified cross-platform with matching extensions.
- Authenticated TLS **Session Pooler port5432**, backup login `myc_backup_20261016_0840`; main postgres password unchanged. The reader has `pg_read_all_data`, BYPASSRLS, readonly defaults, connection/time limits; all214 tables and all sequences were readable, with no schema/table exclusions, foreign tables0, large objects0. User subsequently supplied its reset password through the local private file; no credential was copied to chat/GitHub. The reader's bounded lease was extended to16Oct17:45 UTC to finish verification.
- Started08:42:39 UTC; exported snapshot at **08:42:41.246382 UTC /15:42:41 Bangkok**, `1154663:1154663:`. Dump completed08:50:07 UTC. The same held snapshot supplied the dump, source catalog and all table fingerprints. Later live Raw additions are outside this point-in-time snapshot and are preserved in production.
- `pg_dump --format=custom --large-objects --snapshot=... --lock-wait-timeout=5s --verbose`: exit0. Role export `pg_dumpall --roles-only --no-role-passwords`: exit0. Role password hashes deliberately excluded.
- `full.dump`: **133,444,414 bytes**; SHA256 `d5e01082b062538c265b4c2322419a02a60fb418a6f5604c6ab1f099f949247d`.
- Private run directory: `C:\Users\HP\MYC-Recovery-Private\backup-20261016T084239Z`; independently copied/read/hashed package: `C:\Users\HP\MYC-Recovery-Private\independent-copy\backup-20261016T084239Z`.
- Manifest SHA256 `73b3e049901e32ee3589d9495a8eb1fe47cbfd4a62c55391183bf1eec28df19b`;21 files re-read,136,960,421 artifact bytes. Copies are outside the source project on this workstation, protected by Windows account/SYSTEM ACL. They are **not encrypted, immutable, or on a second physical device**. Credentials are separate; CLIXML is DPAPI protected. Never commit these private artifacts.

## Actual fresh restore and comparison

Fresh target `myc-restore-verified-20261016`,13:44:14–13:47:37 UTC. Full one-pass SQL restore exited0; comparison/package verification completed14:05:05 UTC. Network mode `none`, no published ports or TCP listeners, cron launcher off; copied schedules executed0 times. Other local/AIOS databases were untouched.

| Comparison | Result |
|---|---|
| All214 table row counts and content fingerprints | exact match;0 mismatches |
| Schemas / relations / columns |23 /934 /4,269; exact logical match |
| Constraints / indexes / triggers |931 /622 /17; exact match |
| Functions / views / RLS policies |395 /87 /187; exact definitions and metadata |
| Extensions / default privilege entries |7 /27; exact match |
| Roles, memberships, grantors |74 normalized export statements; exact match |
| Sequence values and is_called |5 /5 match archive SEQUENCE SET |
| Enums / domains / type ACLs / event triggers |13 /2 /644 /6; match |
| Publication / DB owner, locale, encoding and ACL |match; replication never activated |

Content comparison uses exact counts and order-independent numeric sums of64-bit MD5 row-JSON fingerprints, with UTC/float formatting fixed. This is a strong practical parity check, not a collision-proof cryptographic proof of individual rows; artifact integrity uses SHA256. ACL entry ordering is normalized without dropping privileges/grantors;15 physical `auth` column-number gaps caused by old dropped columns compact during logical restore, with surviving logical order/content identical. Sequences are checked against archive entries because sequence state is outside MVCC.

Source/restore acceptance:

- Raw LINE4,732; null/duplicate IDs0. Sync ledger4,730, all SYNCED, orphan ledger0; two newer Raw rows had no ledger at snapshot and remain preserved.
- Shadow786,782 rows; sessions3,028 (3,027 VALIDATED/1 OPEN); orphan sessions0, null row hashes0, duplicate source PK within session0. All distinct historical versions retained in the full archive: Candidate362, Cashbook27, Client3, Commission17, Data_Quality71, Job28, Partner10, Placement15 (533 total).
- Candidate/Placement/Cashbook/Commission shadow content and every canonical/core/finance table match. Empty core/finance masters are intentional pre-cutover; no financial event/status, collection/payment or ownership was invented. This comparison does not establish business finance reconciliation.
- Storage5 buckets/165 object metadata rows restored; file intake170 (165 MIRRORED/5 SOURCE_NOT_MIRRORED) matches. **Storage object bytes were not exported or restored.** No Storage deletion is proposed.
- Vault3 ciphertext rows restored. External root key and secret decryption were not inspected/tested.

## Reproducibility and exceptions

Private manifest includes dump/options, source catalog, all source table fingerprints, final comparison, sequence and supplementary checks, restore stdout/stderr, source ACL supplement and reproduction scripts. Failed preliminary attempts remain private, separate from the successful fresh target.

The compatible target must be initialized with source bootstrap role `supabase_admin` (OID10); skip only its duplicate CREATE ROLE during role import. Retain built-in public schema. Create extensions as the original source owners with a temporary local-only superuser elevation, then revert postgres to NOSUPERUSER. Stream reconstructed SQL as binary to preserve function line endings. Restore all sections, ACLs and comments in one pass, then source-exact explicit ACL/database metadata supplements. A three-section restore alone missed section-independent ACL/comment entries and was rejected. All final differences were resolved on the isolated target, never by changing source objects.

Only the publication warning about replica `wal_level` remains: the publication catalog matches, but logical replication is intentionally disabled in this network-isolated test.

## Existing recovery controls

Registered only after the private artifact/restore evidence passed, in one bounded READ WRITE metadata transaction (no global read-only override):

- Backup ref `MYC-PG-BK-20261016T084239Z`, UUID `739a8c21-213d-46dd-a4eb-fdaaea1963a3`, policy `TEST_DATABASE_CRITICAL`, independent copy=true, result/verification PASS;3 registered artifacts (dump, roles, manifest referencing21 verified files). Encrypted=false, immutable=false.
- Restore ref `MYC-PG-RT-20261016T084239Z`, UUID `d36b903c-31f4-408d-a7c3-aca109e58f1c`, result/reconciliation PASS, all table counts/IDs and Candidate/Placement DB content verified.
- Generic `restore_readiness_v` deliberately remains `PARTIAL_OR_NOT_VERIFIED`: financial evidence, canonical document bytes and broader business DR samples were not asserted. Other object-storage/Google/LINE policies and overall recovery are not marked complete.
- First registration attempt used an unsupported storage-class label; its entire transaction rolled back. Corrected to the existing `INDEPENDENT` enum without schema change, then read back both records.

Next: review [the exact reclaim approval package](MYC_SHADOW_RECLAIM_APPROVAL_20261016.md). Full backup PASS authorizes no deletion by itself. Read-only recovery, guard deployment, real LINE/media/finance E2E,24-hour growth and Cron restart gates remain pending.
