# MYC P0 — Read Gate Closure + Live Data Reconciliation — 2026-09-19

Dispatch: `MYC-DSP-20260916-DATA-FINAL-READGATE`  
Branch: `data/unified-intake-readiness`  
Supabase TEST: `pgjmxdeafzogzsyawejs`  
Operational business SoT: `MEYOU_CONNECT_MVP_DATA_HUB_V1`

## Final gate

**DATA READ GATE = PASS**

This PASS is for the read/data-runtime gate only. It does not enable protected business-Master apply, Production, paid AI, or Auto Submit.

Candidate completeness is intentionally surfaced as **STALE / UNPROMOTED_RAW_GAP** because verified new Candidate proposals still await the separately gated business Master effect. That condition blocks completeness-dependent actions but, per Official Operational Read Contract V1, does not block serving the authoritative Data Hub Candidate list with an explicit stale warning.

## Read boundary

`ops.line_inbox_v` current grants:
- service_role SELECT = TRUE
- anon SELECT = FALSE
- authenticated SELECT = FALSE

No underlying Raw-table browser grant was widened.

After `ops` was exposed through the Data API, Security Advisor detected four pre-existing SECURITY DEFINER parser/router functions executable by browser roles. Migration `20260919041459_p0_ops_exposed_schema_security_definer_execute_hardening_v1` revoked anon/authenticated/public EXECUTE and retained service_role. Security Advisor after hardening: **0 lints**.

## Raw → Google Data Hub acceptance

Canonical runtime: `raw-datahub-sync-v4` / Supabase Edge Function `raw-datahub-sync`, JWT protected.

Health proves:
- Supabase credential configured
- Google credential configured
- Google OAuth succeeds
- target spreadsheet = `1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc`
- target sheet = `19_Raw_Input_Log`
- target headers resolve successfully

The existing Data Hub schema has no dedicated `source_system/source_account_ref/thread_id` columns. The accepted runtime preserves these source-aware/idempotency fields in structured `Notes` JSON without changing the business sheet schema.

### Real Raw proof

Fresh continuity sample:
- `MYC-RAW-002432` → exactly one Data Hub row `19_Raw_Input_Log!2432:2432`
- `MYC-RAW-002433` → exactly one row `...!2433:2433`
- `MYC-RAW-002434` → exactly one row `...!2434:2434`

Replay result:
- appended = 0
- duplicateRows = 0
- target_occurrences = 1 for all three

Google Drive read-back of rows 2432:2434 independently confirmed each Raw ID and structured source/thread/message/stable-key/checksum evidence.

A new Raw arrived during the scheduled acceptance window:
- `MYC-RAW-002439`, received `2026-09-19T04:20:01.721126Z`

It was subsequently synced and independently read back at `19_Raw_Input_Log!2439:2439`.

Final Raw sync snapshot:
- Supabase Raw total = 2430
- ledger total = 2430
- SYNCED = 2430
- open backlog = 0
- Data Bot watermark = `MYC-RAW-002439`
- watermark read-back verified = `2026-09-19T04:21:26.978Z`

The runtime is now enabled in TEST and scheduled every 5 minutes as `meyou-connect-raw-datahub-sync`. A live cron run succeeded at 04:20Z and advanced the watermark through newly arriving Raw.

## Candidate authoritative reconciliation

Fresh authoritative read of `01_Candidate` returned **30 current Master rows**, through `MYC-C-000030`.

Dispatcher snapshot:
- guard READY 3 / NOT_READY 130
- DUPLICATE 65
- CONTEXT_ONLY 3
- INVALID/NOISE 1
- NEEDS_DQ 61

Fresh 2026-09-19 pre-reconciliation state had grown to:
- guard READY 3 / NOT_READY 211
- 106 duplicate-shaped rows (105 NOT_READY + 1 resolved)
- CONTEXT_ONLY 3
- INVALID/NOISE 1
- 58 already verified NEW proposals
- 43 NEEDS_DQ states (41 unresolved + 2 previously DQ-required)

Live Data Hub reconciliation then proved:
- 27 Raw records = `ALREADY_IN_MASTER_LINK_MISSING` and received verified operational-Master linkage to the existing Data Hub Candidate ID
- 25 additional Raw records = `NEW_CANDIDATE_NEEDS_PROMOTION`
- 2 additional records remain genuine DQ
- prior 58 NEW proposals remain proposal-ready
- no Candidate business Master row was directly inserted

Final state:
- Candidate Guard: READY 30 / NOT_READY 184
- `ALREADY_IN_MASTER_LINK_MISSING` evidence decisions = 27
- `NEW_CANDIDATE_NEEDS_PROMOTION / VERIFIED_PROPOSAL` = 83
- DUPLICATE = 93 (92 heuristic NOT_READY + 1 evidence-resolved)
- CONTEXT_ONLY = 3
- INVALID/NOISE = 1
- NEEDS_DQ = 4
- unresolved Master-lookup NEEDS_DQ = 0

Remaining Candidate DQ:
- `MYC-RAW-000885`: name match / phone conflict with `MYC-C-000009`
- `MYC-RAW-001223`: missing explicit Candidate name
- `MYC-RAW-001594`: DOB token conflicts with stated age
- `MYC-RAW-001907`: parsed name contains DOB token and needs name normalization

Controlled flow:
- reconciliation events = 83
- reconciliation effects = 83
- total `candidate.upsert_proposal` commands = 86 (includes the three earlier canonical commands)
- VALID = 86
- READY = 86
- APPLIED = 0
- `core.candidates` = 0
- `business_master_apply_enabled = FALSE`

The enqueue path was rerun under an acceptance migration and produced no additional event/effect/command count, proving idempotency.

## Consent

Direct authoritative read of `14_Consent_PDPA` succeeded.
- authoritative rows = 0
- Data Hub read-back verified = TRUE
- Consent read readiness = READY / authoritative source verified empty
- technical `privacy.consents` rows = 0
- **AUTO SUBMIT = FALSE**

An empty authoritative sheet is treated as a successful read with no consent evidence, not as permission.

## Identity / Context

Identity registry:
- VERIFIED = 1
- PARTIAL = 0
- UNVERIFIED = 10

Evidence-backed mapping retained:
`U1738e96a0eff5456a4656a2435712447 → Partner MYC-P-0001`

No identity was verified from display name alone.

Context resolver:
- RESOLVED_REPLY = 46
- RESOLVED_RECENT_SENDER_CONTEXT = 30
- NEEDS_DQ = 2
- cross-thread/source-account leakage violations = 0

## Worker runtime

Final readiness:
- READY = 1 — `raw_sync`
- PARTIAL = 1 — `candidate_intake`
- NOT_STARTED = 25
- BLOCKED = 0

`raw_sync` is READY from live Edge heartbeat + verified sync/read-back evidence + zero open backlog, not from registry state alone.

`candidate_intake` remains PARTIAL because Candidate completeness is intentionally not claimed while 83 verified proposals await the separate business Master apply gate.

The other 25 registry workers are not required to claim the PWA V0.1 read gate. Job/Client effect workers, follow-up, placement, finance/commission, file semantic processing, portal action workers and notification workers remain later-phase/action-path work and were not started merely to improve a readiness count.

## File compatibility

Live LINE evidence:
- image/jpeg: 108 captured and mirrored
- PDF: 3 captured and mirrored
- video/mp4: 2 captured and mirrored
- ZIP: 1 captured/mirrored outside the required matrix
- 2 generic `file` records remain SOURCE_NOT_MIRRORED

DOCX / XLSX / CSV / TXT / audio still have no live E2E evidence and remain not proven. No paid semantic AI was activated.

## Provenance DQ

`MYC-DQ-000013` remains OPEN / HIGH for `MYC-RAW-000929`.

Evidence remains:
- Raw source = CHATGPT
- Raw content type = CANONICAL_ROUTE_MASTER
- associated event source = LINE / `channel.raw.received`

Root cause remains the historical manual allocation collision. No silent rewrite or DQ closure was performed.

## Runtime / migration changes

Live Edge Function:
- slug: `raw-datahub-sync`
- deployed version: 8
- contract: `raw-datahub-sync-v4`
- JWT verification: enabled

Important migrations tracked in this closeout:
- `20260916063322_p0_raw_datahub_sync_batch_success_v1`
- `20260916063740_p0_raw_datahub_sync_release_inflight_v1`
- `20260916064000_p0_raw_datahub_sync_recover_cancelled_batch_v1`
- `20260916064422_p0_raw_datahub_sync_batch_success_v2`
- `20260916064432_p0_raw_datahub_sync_recover_v3_timeout_v1`
- `20260916064634_p0_raw_datahub_sync_requeue_version_only_notes_conflict_v1`
- `20260919040740_p0_live_datahub_candidate_reconciliation_and_consent_readback_v1`
- `20260919040944_p0_live_datahub_candidate_reconciliation_incremental_pass2_v1`
- `20260919041019_p0_live_datahub_candidate_reconciliation_incremental_pass3_v1`
- `20260919041127_p0_live_datahub_candidate_reconciliation_incremental_pass4_v1`
- `20260919041156_p0_candidate_reconciliation_idempotency_acceptance_v1`
- `20260919041340_p0_enable_raw_datahub_sync_runtime_schedule_v1`
- `20260919041459_p0_ops_exposed_schema_security_definer_execute_hardening_v1`
- `20260919042030_p0_raw_sync_worker_readiness_live_evidence_v1`

## Engineering handoff

Safe to bind under Official Operational Read Contract V1:
- LINE Inbox via server-side service_role
- Raw/Data Hub freshness and raw_sync runtime health
- authoritative Candidate list from `01_Candidate`, with `STALE / UNPROMOTED_RAW_GAP` warning while proposal backlog exists
- authoritative Consent read; empty source is READY-to-read but does not authorize submission
- Context resolver and DQ surfaces
- worker/system health

Still forbidden:
- browser direct Data Hub/Supabase technical reads
- direct Candidate Master writes
- enabling `business_master_apply_enabled`
- Auto Submit
- Production cutover
- paid AI activation

The remaining 83 Candidate proposals belong to the controlled business Master-effect/action gate, not to the data read-path acceptance.
