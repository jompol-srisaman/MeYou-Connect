# MYC permanent protection acceptance — 17 October 2026

Status: **INCOMPLETE**. V4 delta/capacity controls and monitoring are deployed; channel candidates are not deployed. Updated02:38UTC /09:38Bangkok, existing MYC TEST project `pgjmxdeafzogzsyawejs`. See [execution evidence](MYC_RECOVERY_EXECUTION_20261016.md). Do not repeat reclaim.

| Gate | Actual evidence and state |
|---|---|
| Full PostgreSQL recovery | PASS: full17.6 dump,214tables/23schemas/catalog/roles/ACL/5sequences and same-snapshot content match in real isolated restore. Encrypted offsite downloaded/decrypted/authenticated/hash-verified with separate-account key. Storage object bytes/Vault-root-key decryption excluded. |
| Approved reclaim | PASS:749,964archive-only; original36,818rows/all3,028sessions retain fingerprints. DB1,647,651,987→149,367,955bytes; noCASCADE/business/source deletion. Completed once. |
| Ordinary external writes | PASS point-in-time: fresh TLS pooler session with default/transaction readonlyoff committed real controls; independent connector read record+3artifacts. Temporary roles NOLOGIN/deprivileged. No global override. |
| Delta-only import | PASS tested scope: deployed V4 SQL/Edgev4. Real HTTP dry-run69delta, real69valid/0invalid, repeatUNCHANGED_SOURCE/zero extra rows/session. Scoped baseline, source-deletion review, stale/inflight/out-of-order, sealing, limits/ACL/concurrency tested. Cron11off. |
| Physical capacity stops | PASS isolated physical fixtures:88,244,224shadow and467,561,619DB bytes blocked Google/non-Google admission/staging, exact cleanup. Live limits75MiBshadow/400MiBDB, warning250MiB. No quota fixture on live. |
| Health and access | PASS internal capability SQL and private offline aggregate dashboard. Founder allowed, anon/content denied in clone. `api` schema external PostgREST request406: public frontend API not claimed. |
| Alert lifecycle | PASS clone tests + live collector: existing Cron3 identity/owner/ACL/schedule preserved, stable fingerprints/6h throttle/serialization, UNKNOWN no false recovery, audited warning resolution/stale queue cancellation. SEV1 incidents never auto-close. |
| Actual owner delivery | PASS controlled Founder Gmail self-test; independently found INBOX receipt1a1479f1993096a4. Queuea4babdb1-4f75-46f6-8647-fb45c721c64f SENT attempt1 only after receipt. VerifiedFounderEMAIL route/gate active for bounded worker; unrelated transports unproven. |
| Delivery retry | PASS clone actual two-session SKIPLOCKED, stale ACK rejection, three-attempt cap, receipt requirements and service ACL. Native desktop heartbeat required for future sending; offline delays, at-least-once behavior and stable-tag retry checks documented. |
| Bounded history | PASS rollback test; live capture at most one/15min, hard2016cap then archive-required alert/stop, no prior row deletion. Capture never asserts business DR readiness. |
|24-hour observation | IN PROGRESS from2026-10-17T02:13:59.664052Z;02:38read two samples/latest02:30, DB142.78MiB/shadow58.35MiB/no active capacity alert. Earliest18Oct09:14Bangkok; inspect actual gaps/freshness/growth. Gates off means not automatic-import load soak. |
| Raw/Sheets | PASS point-in-time:4,749DBRaw IDs canonicalSheet exactly once, missing0/duplicate0; all4,749ledgerSYNCED/backlogs0. Eight Sheet-only IDs/shifted originals preserved. |
| Channel retry/idempotency | HOLD DEPLOYMENT: candidate code retrieved from current deployed adapters, isolated full-pipeline tests cover Candidate proposal idempotency/zeroFinance or master effects. Independent terminal/concurrency/media retry review fixes still in progress; actual signed provider E2E pending. |
| Media/object bytes | OPEN:171intake,165MIRRORED/checksum metadata,6SOURCE_NOT_MIRRORED. Actual object bytes not independently exported. Metadata is not object-byte backup; no hidden export API enabled. |
| Finance/consent/source authority | OPEN source reconciliation: masters intentionallyempty/pre-cutover; historical four outcomes awaitingcollection/three negatives/two identity holds. No invented COLLECTED/PAID, partner, consent or duplicate business effect. |
| Capacity model | PASS actual isolated schema-only fixture:1,000Raw/Event/ledger pairs add5,316,608bytes,10,000add51,019,776bytes. Separate metadata media projection; excludes provider/WAL/worker/media load. |
| Cron/cutover | PASS last read: Cron11false, Shadowgatefalse, business_master_apply_enabled/migration_target_apply_enabled/production_cutover_approvedfalse; existing Cron3active. Re-read before deployment. |

Formal deployed migrations: `20261017020029_myc_shadow_import_v4_delta_guards.sql`, `20261017021011_myc_capacity_email_queue.sql`, `20261017021358_myc_capacity_guard_observability.sql`. Their review SQL remains available; filenames do not mean deployed artifacts are still drafts. LINE candidate has no source migration/deployment yet.

Use [monitor operations](MYC_CAPACITY_MONITOR_OPERATIONS_20261017.md) for fresh private dashboard and receipt procedure, and [storage matrix](MYC_STORAGE_AUTHORITY_CAPACITY_20261017.md) for measured model limits. Cron3 collects while desktop is off; Gmail bridge cannot send then. Capacity health does not resolve unrelated incidents or media gaps.

Keep PR29 draft, Issue28 open and Cron11 off until original restart gates pass. Mocks/SQL fixtures do not establish provider E2E, historical media recovery, finance reconciliation, Facebook assets or24-hour operation. No paid service/project, architecture change or new destructive scope implied.
