# MYC P0 — Data Read Gate Controlled Reconciliation — 2026-09-16

Status: `PARTIAL / GOOGLE_RUNTIME_CREDENTIAL_GATE`

Scope: Supabase TEST `pgjmxdeafzogzsyawejs`, PR #26, Issues #14/#23/#16. Google Data Hub remains the operational business Source of Truth.

## Live baseline observed before controlled reconciliation

- Raw count: 1,446
- Latest Raw: `MYC-RAW-001455`
- LINE Inbox: 1,445
- Candidate guard: 3 READY / 134 NOT_READY
- Reconciliation workbench: 67 DUPLICATE / 3 CONTEXT_ONLY / 1 INVALID-NOISE / 63 NEEDS_DQ
- Consent technical rows: 0; Auto Submit remains FALSE
- Identity registry: 1 VERIFIED / 8 UNVERIFIED
- Raw sync: 1,446 unstaged / 0 synced / 0 watermark

## Candidate reconciliation acceptance applied to control state

Evidence authority: Issue #16 comment `5691426260`, which accepted the then-current 61-row business reconciliation proposal after live Candidate Master review.

Accepted old population:

- 58 → `NEW_CANDIDATE_NEEDS_PROMOTION`
- `MYC-RAW-000930` → `DUPLICATE` of `MYC-RAW-000932`
- `MYC-RAW-000885` → `NEEDS_DQ` / name-match + phone conflict with `MYC-C-000009`
- `MYC-RAW-001223` → `NEEDS_DQ` / missing explicit candidate name

New records `MYC-RAW-001450` and `MYC-RAW-001453` were received after the accepted Master review and remain `NEEDS_DQ`. Their exact fingerprint duplicates remain ordinary DUPLICATE rows.

After evidence annotation, the current 134 NOT_READY rows are exposed as:

- DUPLICATE: 68
- CONTEXT_ONLY: 3
- INVALID/NOISE: 1
- NEW_CANDIDATE_NEEDS_PROMOTION: 58
- NEEDS_DQ: 4

No hidden accepted backlog remains under `LIVE_DATAHUB_MASTER_LOOKUP_REQUIRED` for the accepted 61-row population.

## Controlled candidate flow proof

Migration `20260916040002_p0_candidate_reconciliation_controlled_promotion_v1`:

- stores the accepted reconciliation decision/evidence on Raw metadata;
- makes the existing reconciliation workbench honor evidence-backed decisions;
- re-enters accepted candidates through `candidate.lead.received` in the existing Event Kernel;
- uses existing `candidate_intake` / `candidate.upsert_proposal` contract;
- does not infer a Job ID, current submission route, Partner ID, or Consent;
- keeps Auto Submit false.

Migration `20260916040112_p0_candidate_reconciliation_controlled_execution_batch_v1` executed the accepted backlog:

- 58 reconciliation events registered;
- 58 reconciliation enqueue effects registered;
- 58 distinct `candidate.upsert_proposal` commands VALID / READY;
- immediate rerun prepared 0 additional reconciliation commands;
- APPLIED count = 0;
- `core.candidates` count remained unchanged;
- `business_master_apply_enabled` remained FALSE.

Therefore the backlog is now prepared through the canonical Command/Event/Validation path without a protected Master bypass. Operational Google Master effect remains pending.

## Raw → Data Hub runtime

Existing `raw-datahub-sync` Edge Function remains ACTIVE with JWT verification enabled and uses the previously accepted source-aware/idempotent control plane:

Supabase Raw → per-source stage → claim → Data Hub `19_Raw_Input_Log` lookup → append only if absent → exact row read-back → checksum/content verification → ledger success → verified per-source watermark.

A live runtime health invocation through the Supabase Edge gateway returned:

- Supabase runtime credential: configured
- Google runtime credential: **not configured**
- target spreadsheet: `MEYOU_CONNECT_MVP_DATA_HUB_V1`
- target sheet: `19_Raw_Input_Log`

Because Google authorization is absent, the writer was not allowed to stage/claim rows or fabricate sync evidence. Ledger and watermark therefore remain empty.

## Gate decision

`DATA SIDE READ GATE = PARTIAL`

Passing the remaining gate requires an authorized Google server identity for the existing `raw-datahub-sync` runtime, followed by:

1. 3 real Raw → Data Hub writes;
2. exact read-back verification;
3. same-3 rerun proving 0 duplicate rows;
4. latest-Raw continuity proof;
5. verified Candidate Master re-read for the 4 remaining DQs and pre-effect drift check for the 58 READY proposals;
6. controlled Google Candidate Master effects only after authoritative dedupe/read-back, followed by the existing operational Master-effect reconciliation pattern.

No Production cutover, SoT change, paid AI, direct protected Master write, or Auto Submit is authorized by this document.
