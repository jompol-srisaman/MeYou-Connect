# MYC recovery and resilience implementation plan

> **For agentic workers:** Use superpowers:executing-plans for the primary operator and bounded Luna6 reviews/tests. Steps use checkboxes. Source mutations remain with one primary operator.

**Goal:** Recover the approved staging capacity safely, restore normal writes and prevent recurring duplicate growth while preserving MYC authority, privacy and financial controls.

**Architecture:** Continue PR29 and existing Supabase ops/config/dash intake, workers, alerts and file/evidence contracts. Sheets remains SOT for designated business fields; Drive holds restricted evidence and client-side-encrypted cold archives. No new project, paid API, master cutover or change of business IDs.

**Tech stack:** Existing PostgreSQL17.6/Supabase, Docker Desktop, TypeScript Edge Functions, Node built-in tests/crypto, Python stdlib, MYC Google Drive connector.

**Spec:** [Founder approval and mandatory requirements](https://github.com/jompol-srisaman/MeYou-Connect/issues/28#issuecomment-6217872819), [PR instructions](https://github.com/jompol-srisaman/MeYou-Connect/pull/29#issuecomment-6217877877), [exact reclaim package](../../runbooks/MYC_SHADOW_RECLAIM_APPROVAL_20261016.md). The user instructed execution without repeating deletion approval inside this exact scope. Stop on scope mismatch/security/backup failure.

## Global constraints

- Scope `MYC-RECLAIM-20261016-749964`:786,782 ->36,818 Shadow rows;749,964 archive-only; all3,028 sessions and4 invalid rows preserved. No CASCADE.
- Do not delete/update Raw/events/domain commands, operational business masters, Sheets source, evidence/Storage, Vault or unrelated Cron jobs during reclaim.
- Keep Cron11 inactive and the three master/cutover gatesfalse until original restart gates pass and activation is authorized.
- Source snapshot age <=24h, original/retained/session fingerprints and dependencies must still match under locks. Any mismatch aborts and is a Founder escalation, not permission to widen deletion.
- Offsite copy must be encrypted before upload, owner-restricted, downloaded/hash/decrypt checked and independently recoverable. Keep encryption secrets out of chat/GitHub/process arguments; do not rely only on workstation-bound DPAPI for offsite recovery.
- Default dry-run; fail closed on unknown schema, disabled gates, payload budget, duplicate/incomplete snapshot, stale baseline and capacity stops. Shadow stops must not turn off LINE capture.
- No unverified business entitlement, partner attribution, finance state, consent or duplicate Candidate merge. Preserve source-first and EXPECTED->EARNED->INVOICED->COLLECTED semantics.

## Review focus

- Same-count session metadata changes alter retention: Phase A must assert metadata fingerprint and recomputed keep-set before TRUNCATE.
- Lost workstation/key: verify independently recoverable separate-account key escrow before deletion; Founder delegated random-key management without a new passphrase. Test wrong-key/tamper rejection.
- Partial Phase B/network failure: keep writers frozen; empty-target/fingerprint guards; verified retained roll-forward; never overwrite newer Raw with a full old snapshot.
- Account-scoped provider retries and payload collisions: same event is idempotent; changed content/account scope never silently aliases an existing business effect.
- Clock-derived health values/physical bloat: compare stable timestamps/content, measure actual disk/WAL and real capacity boundaries; test actual bytes rather than code constants alone.
- A queued/HELD alert is not delivered; verify the configured owner/channel receives an actionable alert without exposing PII.

## Task 1 — independent encrypted recovery kit

**Files:** Private `MYC-Recovery-Private/encrypted-offsite/` and `encryption-keys/` only; redacted public evidence in `docs/runbooks/MYC_RECOVERY_EXECUTION_20261016.md`.

**Interface:** Complete verified `full.dump`, original manifest SHA, retained CSV and restore evidence -> encrypted split archive, part/whole SHA, owner-only Drive file IDs, download/decrypt/member verification, protected recovery-key escrow.

- [x] Re-read/hash both original packages; archive49 members with no credentials/key included.
- [x] Encrypt AES256GCM with random32-byte key/12-byte nonce; reject wrong key/tamper; local decrypt hash match.
- [x] Upload three64MiB-or-smaller ciphertext parts to owner-only MYC folder (connector100MB/file bound); download, reconstruct, authenticate, CRC/hash every artifact.
- [x] Founder delegated key management instead of entering a new passphrase. Verified32-byte recovery-key escrow in a separate Founder-only account/folder from MYC archive; downloaded key matches, no key printed. Recovery no longer depends on workstation DPAPI. Do not place the key in the business archive folder or publish its location/contents in GitHub.
- [x] Record encrypted offsite evidence in existing recovery controls; keep original unencrypted-copy flags truthful.

## Task 2 — exact approved live reclaim and read/write recovery

**Files:** Existing `docs/runbooks/sql/MYC_SHADOW_RECLAIM_PHASE_{A,B}_REVIEW.sql`; private orchestration/logs; public redacted execution report.

**Interface:** Verified offsite kit + exact Founder approval + live invariants -> scoped temporary maintenance session, source36,818 retained rows/unchanged sessions/latest views, measured freed capacity and normal new-session writes.

- [x] Existing full restore, exact-method reclaim, full-shadow rollback and retention-scope negative tests PASS.
- [x] Verify current endpoint/age/counts/fingerprints/references/gates/writers and prepare both-phase input before any Phase A commit.
- [x] Freeze only Shadow writes. Provision a bounded least-privilege maintenance login for metadata reads and staging INSERT/TRUNCATE; store secret privately, pre-test connection/privileges without deleting anything.
- [x] Execute the exact approved Phase A then immediate Phase B on the same authenticated session; capture command exit/commit evidence. Abort before A on mismatch; use scoped retained roll-forward on post-A failure.
- [x] Compare retained CSV/content, all session metadata, latest dashboards, Raw/ledger and Candidate/Finance aggregates. Measure relation/database/disk/WAL.
- [x] Prove database below500MB with margin and normal persistent read/write on fresh external/application sessions; do not count explicit READ WRITE override as recovery. Revoke temporary credentials.

## Task 3 — bounded Shadow import and capacity protection

**Files:** Existing `supabase/functions/datahub-shadow-import/index.ts`, `docs/runbooks/sql/MYC_SHADOW_IMPORT_V3_GUARDS_DRAFT.sql`; formal migration created through supported CLI when deployment is ready; `tests/shadow-import-recovery.test.mjs`, `tests/shadow-guard.integration.mjs` plus physical-boundary fixtures on disposable clone only.

**Interfaces:** Preserve existing open/stage RPC identities/owner/ACL/search_path. Use normalized per-row scoped content fingerprints and current validated source baseline; latest views must retain untouched records. A deleted upstream row becomes explicit reconciliation/tombstone review, never automatic master/evidence deletion. Concurrent/stale baselines must fail closed.

- [x] Capture real failing tests for missing guards/old50MiB cap, then install/test revised75MiB cap on the disposable restored clone. Keep DB stop400MiB/warn250MiB. Derive headroom from measured61,038,592byte retained baseline.
- [x] Test unchanged input zero writes, one-row delta, retries, duplicate keys, scoped source IDs, reordered/missing/unknown headers, source row deletion review and out-of-order/concurrent baselines.
- [x] Test real SQL admission/staging, row32KiB/session1000rows/2MiB limits,20-hashed-session archive-required stop, disabled gates, role/RLS boundaries and unchanged master/finance effects.
- [x] Exercise physical cap boundaries on disposable clone and reset only that fixture. Serialize cross-session capacity decisions; prevent unbounded snapshot/log accumulation; no new source purges without separately approved exact archival scope.
- [x] Add compact guard-health/growth/backlog metrics through existing observability contracts, deduplicated actionable incidents and verified owner delivery; prevent alert storms/PII leakage.
- [x] Deploy only tested artifacts, verify actual external importer write/readback and unchanged replay, leave Cron11 off pending all original gates/soak.

## Task 4 — channel/file/authority contracts within existing architecture

**Files:** Existing intake/worker/evidence migration contracts and current deployed LINE adapter source (must be retrieved/reviewed before claiming coverage); focused shared adapter/tests and storage matrix documentation where needed. No speculative production Facebook deployment.

**Interface:** Signature-verified channel/account/upstream-event envelope with tenant/privacy/consent-purpose metadata -> existing idempotent Raw/Event/lease/retry/DLQ contracts -> gated source-first business commands. File Registry -> Evidence -> restricted object pointer + SHA256. Unknown attribution/identity/consent goes to review, not a new master/financial effect.

- [ ] Audit existing envelope uniqueness, conflict/retry/DLQ behavior, source-first partner/finance contracts, consent RLS and file reference integrity against live adapter source and restored tests.
- [ ] Implement scoped anti-replay/conflict protections using existing contracts. If the required change would touch explicitly protected live rows/authority outside approved scope, stop for a specific Founder scope decision before deploying it.
- [ ] Test OA/group/Facebook same-event retries and cross-account ID collisions, mutated duplicates, out-of-order/timeouts, transient/persistent worker failure, Candidate/commission non-duplication and consent segregation on isolated DB. Real provider tests require verified assets/credentials and must not be represented by mocks.
- [ ] Document Supabase/Sheets/Drive authority matrix, separate finance/evidence/consent retention, measured structured/media growth per1k/10k messages, warn/stop/expansion thresholds and reversible future migration options. Free is bounded; do not add paid services.

## Task 5 — real verification and24-hour soak

- [ ] Run repository tests + PostgreSQL integration + actual HTTP/readback checks; keep mocked/local/provider evidence separate.
- [ ] Verify alert delivery, source-to-archive reconciliation, rollback and normal operational read/write; track six unresolved media mirrors and unexported object bytes explicitly.
- [x] Start bounded24h observation with real size/delta/backlog/read-write/guard/alert evidence via existing tools; record unavailable periods, no fake elapsed-time PASS.
- [ ] Finish all acceptance gates, update Issue28/PR29 and AGENTS/handoff and evidence report, keep PR draft/incident open until required gates actually pass. Do not restart Cron11 prematurely.
