# MYC approved recovery — execution evidence

Current status: **INCOMPLETE**. Approved reclaim and PostgreSQL logical recovery passed. Permanent controls and the 24-hour live observation have separate acceptance gates. Continue Issue28 / PR29; do not repeat the reclaim.

## Authority and exact scope

- Founder approval: [Issue28 comment6217872819](https://github.com/jompol-srisaman/MeYou-Connect/issues/28#issuecomment-6217872819), scope `MYC-RECLAIM-20261016-749964`.
- Permanent-control requirements: [PR29 comment6217877877](https://github.com/jompol-srisaman/MeYou-Connect/pull/29#issuecomment-6217877877).
- The approved two-phase SQL was executed on16October15:20:00–15:22:06 UTC after source fingerprint, snapshot-age, dependency, lock, gate and independent encrypted recovery checks passed. Both commits succeeded; no CASCADE.
- Shadow rows786,782 →36,818 retained;749,964 historical rows now archive-only. All3,028 original session metadata rows and all4 invalid rows retained. Exact retained content fingerprint `-2770658449854450349`; session metadata fingerprint `62814098099219885444` matched after reload.
- Latest dashboard rows/content, Raw4,749, sync ledger4,730 and intentionally empty Candidate/Finance masters matched immediately after reclaim. The clock-derived sync lag field was excluded from content comparison. No Raw, event, domain command, master, source Sheet, evidence object or Vault deletion was part of reclaim.

## Backup and independently recoverable encryption

- Full PostgreSQL17.6 snapshot16October08:42:41.246382UTC: dump133,444,414bytes, SHA256 `d5e01082b062538c265b4c2322419a02a60fb418a6f5604c6ab1f099f949247d`. Fresh isolated restore matched214tables,23schemas, exact row content, roles/catalog/ACL and5sequences; cron launcher disabled and no network/ports. See [full comparison](MYC_POSTGRES_RESTORE_RESULT_20261016.md).
- Complete49-member recovery ZIP encrypted locally with a random32-byte key using AES256GCM before upload. Ciphertext195,415,924bytes, SHA256 `9ba80fb16e3f277809a1f15368d70ac829346966ff03d6da0eee3c037829ea0f`. Three parts fit the existing connector upload limit.
- MYC business Drive owner-only folder holds ciphertext, part manifest and recovery instructions. Every part was downloaded and SHA256 checked; recombination, authentication, ZIP CRC and original/retained artifact hashes passed. The recovered dump is byte-identical to the restore-tested dump. Wrong-key and modified-ciphertext tests rejected the input.
- Founder delegated key management; no new password/passphrase was needed. The key was escrowed in a separate Founder personal account with owner-only permissions, downloaded independently, and successfully used to decrypt the business archive. The key location/material is deliberately absent from this report, GitHub and the business archive. Cloud escrow uses separate-account access control; do not describe the key itself as client-side encrypted. A private local copy and Windows DPAPI copy also exist.
- Original unencrypted workstation-copy flags remain truthful. Encrypted offsite copy is separately registered PASS as `MYC-PG-ENC-20261016T084239Z`, pointing to the original snapshot rather than claiming a new backup. Storage object bytes and external Vault-root-key decryption are **not** covered by the PostgreSQL restore test.

## Capacity and ordinary write recovery

- Immediately before reclaim: database1,647,651,987bytes; shadow1,559,339,008bytes.
- Immediately after: database149,367,955bytes; shadow61,054,976bytes. Measured database reduction1,498,284,032bytes (about1.40GiB).
-17October01:42–01:45UTC: provider default read-only **off**, database149,482,643bytes, shadow36,818rows. No global/database read-only override was installed. A new ordinary TLS Session Pooler5432 `psql` session asserted both default and transaction read-only off and committed the actual encrypted-backup control record; an independent SQL connector read the committed record and all3 encrypted artifacts back.
- Both temporary reader/reclaim roles are now NOLOGIN, NOBYPASSRLS, without `pg_read_all_data`; reclaim INSERT/TRUNCATE and session MAINTAIN privileges were revoked. Main postgres password was unchanged.
- Fresh canonical Sheets ID-only readback17October01:52UTC: all4,749 database Raw IDs found once, missing0/duplicate0. Ledger4,749 all SYNCED; pending/retry/DQ/in-flight/unstaged backlog0. Eight historical Sheet-only IDs and original shifted copies remain preserved.
- Core Candidate, Revenue, Commission and Journal masters remain0 by design. Their emptiness does not constitute source financial reconciliation or proof of collection/payment.

## Permanent control deployment

- Isolated17.6 tests passed delta baseline merge, unchanged-row preservation, retry/sealing, stale/in-flight/out-of-order rejection, bounded row/session bytes, role ACL and concurrency. Legacy OPEN session and4 historical invalid rows remain preserved and do not permanently block valid baselines.
- Actual physical V4 boundary tests stopped both Google and other optional Shadow admission/staging at88,244,224 shadow bytes and467,561,619 database bytes. The latter remained below the450MiB fixture ceiling. Cleanup on the disposable clone restored the exact retained fingerprint,36,818rows,3,028sessions and disabled gate. No capacity fixture ran on the live project.
- V4 SQL applied17October02:00UTC; `datahub-shadow-import` version4 deployed with JWT verification on. Bundle SHA256 `0b2954547ba0bd8bbf47bd09ee2ba1ad96c365a58d2212d670c9908ddaf9671a`; deployed source readback equals uploaded source. Deno2.9.6 typecheck passed.
- Actual authenticated HTTP dry-run returned200: all10 entity schemas valid,69 changed/new rows (43,181bytes); it wrote no Shadow rows. Controlled real import then returned200/69valid/0invalid/0skipped; the repeated HTTP import returned200 `UNCHANGED_SOURCE` with no additional rows/session. The Shadow gate was enabled only for this controlled write and disabled again immediately; Cron11 stayed inactive.
-17October02:04UTC readback:36,887total rows/3,029sessions, including exactly69rows in the new validated session. Original36,818protected rows retain fingerprint `-2770658449854450349`; original3,028session metadata retain fingerprint `62814098099219885444`. Invalid historical rows remain4, latest valid projection430, Candidate/Commission masters0, ordinary read-onlyoff, DB149,630,099bytes. The approved disposal was not repeated or widened.

## Capacity monitoring and actual owner delivery

- Capacity email queue migration applied at02:10:11UTC and observability migration at02:13:58UTC on17October. The existing Cron3 refresh function keeps its identity, owner, ACL and schedule; Cron11 is still inactive. SQL rollback integration covered capability/RLS boundaries, alert fingerprint aggregation, UNKNOWN-state handling, warning resolution, stale queue cancellation and bounded history. Physical guard tests above are separate evidence.
- A controlled capacity TEST message was sent through the existing connected Founder Gmail account to that same account. Independent INBOX search found receipt `1a1479f1993096a4`; only then was delivery `a4babdb1-4f75-46f6-8647-fb45c721c64f` acknowledged SENT at attempt1. The TEST alert was resolved after receipt. One verified Founder EMAIL route and the external delivery gate are active for this bounded capacity worker; this does not establish readiness of unrelated alert transports.
- Queue tests covered two-session SKIP LOCKED, stale acknowledgements, three-attempt bounds, receipt requirements and service-role ACL. Native Codex heartbeat `myc-recovery` processes only the capacity whitelist through the connected Gmail account. If the desktop/app or connection is unavailable, source collection/queueing continues but delivery waits; this is not an independent always-on email service.
- Actual capacity samples started17October02:13:59.664052UTC. At02:38UTC two samples existed, latest02:30UTC; database149,712,019bytes, shadow61,186,048bytes, read-onlyoff, capacity alerts0. The earliest24-hour boundary is18October02:14UTC /09:14Bangkok; actual coverage, gaps and growth still require review then.
- A private offline HTML dashboard renders current aggregate metrics, samples, gates, backlog and unresolved media, without source IDs or payloads. Internal capability-protected SQL health tests passed. The `api` schema is not exposed through PostgREST (external profile request406); a public frontend health API is not claimed. See [monitor operations](MYC_CAPACITY_MONITOR_OPERATIONS_20261017.md).

## Outstanding acceptance

Channel ingress changes remain an undeployed candidate pending terminal-state, concurrent routing and media retry review/tests. Live provider E2E, unresolved historical media/object-byte recovery, source-matched finance reconciliation and the24-hour bounded-growth observation remain open. Current file intake is165 MIRRORED /6 SOURCE_NOT_MIRRORED; those6 media recoveries are unresolved. Existing PostgreSQL backup includes their metadata, not their object bytes. No paid API/project, master cutover, cron restart, merge or incident closure is implied.

Private logs, exact SHA manifests, offsite/key recovery evidence, maintenance stdout/stderr and detailed row comparisons are ACL-restricted under the Founder workstation recovery directory outside Git. Publish only redacted aggregates and non-secret destination descriptions.
