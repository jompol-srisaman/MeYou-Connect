# MYC real LINE and source reconciliation —17October2026

Status: **INCOMPLETE** overall. This evidence extends the [execution log](MYC_RECOVERY_EXECUTION_20261016.md), not the approved disposal scope. Codex owns PR29; Web Chat owns the separate read-only audit in Issue30. No business status, financial amount, consent, master/cutover gate or historical object was changed by these checks.

## Founder-originated real messages

Founder confirmed sending the non-PII text `MYC RECOVERY TEST 20261017` to Official OA, Data Bot and an internal group. Actual backend reads found:

| Channel | Bangkok received time | Test Raw reference | Parent state | Classification effects | Independent Sheet row |
|---|---|---|---|---:|---:|
| Official OA |14:14:15|MYC-RAW-004772|COMPLETED|1|4484|
| Data Bot private chat |14:14:28|MYC-RAW-004773|COMPLETED|1|4485|
| Internal group via Data Bot |14:15:02|MYC-RAW-004774|COMPLETED|1|4486|

All3have exactly one scoped fingerprinted event map. All3ledger entries becameSYNCED; independent read of `19_Raw_Input_Log!A4484:A4486` and `H4484:H4486`, after confirming theHheader, matched the3IDs and exact test text. Each test has0Candidate proposal effects and0Finance commands, as expected for a diagnostic message. A LINE client Read badge was not used as a backend delivery gate. Text lives inRaw/Sheets; object Storage holds media bytes.

These events exercised the real provider→HMAC-checkedV10handler→capture→classification→scheduled Raw SyncV10→Sheet/readback path. They are not synthetic DB injections. Earlier natural post-deploy Data Bot evidence separately showed6new captures,2deferred Candidate proposal effects and0Finance commands. None of this certifies master application or financial recognition.

## Retry and concurrency boundaries

Two independently dispatched source SQL requests reconstructed only these3already captured diagnostic envelopes inside PostgreSQL. Both used `BEGIN TRANSACTION READ ONLY` and verified the reconstructed immutable SHA256against each existing event fingerprint before calling the deployed capture function. Each returnedREPLAY_DETECTED3/3, sameRaw3/3 and0media-work requests. Post-check still showed3Raw records/3single maps/3classification effects, with0Candidate/Finance effects. No private provider identity or payload left the server in the result.

This is real deployed SQL replay verification, not a replay of the provider-signed HTTP body or proof that the two server transactions overlapped. The isolated PostgreSQL harness separately forced a real two-session capture-versus-candidate-worker race, verified no deadlock and one classification, and restored exact synthetic fixture/heartbeat/ACL state. Actual provider redelivery after a transientmedia failure and recovery of the missing historical bytes remain OPEN.

## Media causes and narrowly scoped fix

The6SOURCE_NOT_MIRRORED records classify as4DATABASE_READ_ONLY and2INVALID_STORAGE_KEY. The2key errors contain non-ASCII original filenames. All6have0matching registered objects in `raw-inbox-private`, and none maps to a usable original through the inspected Data Hub File Registry. This does not prove bytes are permanently lost; original provider/private copies have not been acquired.

Both adapters now generate new upload basenames fromASCII SHA256plus an allowlisted MIME extension, preserving the original filename in the existing registry field. Raw/provider path scope, private bucket, checksum, `upsert:false`, size caps and completed-mirror replay behavior remain unchanged. No old key/object/registry row is rewritten. A regression first failed against a mock Storage rejecting non-ASCII keys, then passed for both adapters; focused23/23tests and strictDeno checks passed, with independent review. The full Node unit/contract suite subsequently passed66/66.

Deployed LINEv11 source readback matches the reviewed files. Official bundleSHA256 `aebd0b39ef8d270b736b170b0e868b36c3dc30ef2e692a1167fb25c4903fe071`; Data Bot `6dc599b5ffa88dfefb92ac9fe093f29ea5eaae7cabd54e5ed0ee8db270ae8a25`. Both retain JWTfalse/providerHMAC and actual unsigned probes returned401 at07:35UTC. Raw Sync remainsv10; no new migration was needed. The real3message test above precededv11; the new filename case is not represented as provider E2E.

A separate existing object was downloaded through the authorized Dashboard, copied into the restricted local recovery directory and SHA256checked against its checksum-derived source name:136,253bytes matched. The loose download copy was removed only after private-copy verification. This is1existing-object byte copy, not165object backups or recovery of any missing6. No temporary privileged export API or runtime credential extraction was used. A private6item recovery list is available locally; do not publish filenames or payloads here.

## Source-first Finance, Partner and Consent checks

Current Data Hub metadata was read through the MYC business Drive account. ID columns were checked to each tab's current grid boundary; bounded record reads covered every occupied ID row. Aggregate results:

| Check | Observed result | Boundary |
|---|---|---|
| Partner |10IDs,0duplicates|No personal contact fields read for this check.|
| Revenue |4IDs|Collected-labelled source rows have a payment reference; a reference is not independent bank proof.|
| Commission |26IDs,0duplicates; allPartner references resolve;0paid-labelled rows missing payment reference|No payout or state transition performed.|
| Cashbook/Evidence |30Cashbook records; all referenced IDs resolve within47registered Evidence rows;2compound references parse correctly;0missing referenced IDs|Reference integrity only; no monetary balance or bank reconciliation claimed.|
| Original proof pointers |20Evidence rows contain Drive URLs;27have text-only references and no resolved File Registry bridge in the inspected data|Original bytes/ownership/transaction details not fully verified. WebIssue30 may resolve pointers and independent proof in its lane.|
| Consent |0source IDs throughrow5000;0rows in `privacy.current_consents_v`|Blank records do not establish consent or permission; no consent created or inferred.|
| Raw/Sheet parity |4,762DBRaw IDs independently found exactly once in canonical SheetAcolumn; missing0/duplicate0;8historical Sheet-only IDs preserved|Snapshot before3Founder tests. Those3were then independently checked above; unrelated live growth must be accounted separately.|

Source financial decisions already approved/closed are not reopened or overwritten by this audit. Finance/Partner reference integrity passed its stated checks; end-to-end original-document financial recognition and positive consent evidence remain HOLD. No collection/payment was inferred from chat, emoji or an empty PostgreSQL master.

## Monitoring and next gate

07:40UTC /14:40Bangkok: DB149,900,435bytes, readonlyoff;Raw=ledger=SYNCED4,765/backlogs0;Shadow36,887rows/61,186,048bytes.19real capacity samples, latest07:30UTC; existing guard/alert/controlled receipt tests remain separately recorded. Capacityemailclaim returned empty; no repeat TEST email was sent. Earliest24h boundary remains18October09:14Bangkok, subject to actual coverage/freshness/growth. Cron11, Shadowwrite and business/cutover gates remainfalse.

Original6media bytes/authorized provider replay, complete original-source reconciliation and the24hour gate remain outstanding. Keep Issue28open/PR29draft; do not repeat reclaim or label the whole recoveryPASS.
