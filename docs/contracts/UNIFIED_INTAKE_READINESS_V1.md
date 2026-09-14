# MeYou Connect — Unified Intake Readiness V1

Status: `P0 / TEST / PARTIAL_READY / DATA_HUB_READBACK_BLOCKED`

Related: #14, #23, PR #22, MYC-DQ-000011  
Supabase TEST: `pgjmxdeafzogzsyawejs`  
Operational business Source of Truth: `MEYOU_CONNECT_MVP_DATA_HUB_V1` / `GOOGLE_SHEETS_DRIVE`

## 1. Boundary

This work extends the existing canonical flow only:

`Channel → Raw → Parse / Validate → Deduplicate → Route → Master Effect → Audit`

It does not create a new Raw→Master pipeline, does not direct-write protected business Master tables, does not change Source of Truth, does not activate paid AI, and does not perform Production cutover.

## 2. Live audit snapshot

Observed in TEST during the 2026-09-14 P0 audit:

- LINE Raw rows: `1110`
- Latest LINE Raw received: `2026-09-14T12:41:55.647124Z`
- Candidate promotion guard READY / verified Master Effect: `3`
- Candidate promotion guard NOT_READY: `86`
- Supabase consent rows: `0`
- Verified LINE identities after evidence-backed reconciliation: `1`
- `candidate_intake` latest heartbeat observed: `2026-09-14T14:25:00.201892Z`

Important: `86` means Candidate-shaped Raw records without verified operational Master-effect linkage. It is not evidence that 86 Candidates are missing from Google Data Hub.

## 3. Candidate reconciliation contract

Read model: `ops.candidate_reconciliation_workbench_v`

Allowed categories:

- `ALREADY_IN_MASTER_LINK_MISSING` — only after live Data Hub Candidate Master proves the Candidate already exists and the Raw/evidence linkage is absent.
- `NEW_CANDIDATE_NEEDS_PROMOTION` — only after live Data Hub Candidate Master proves no existing Candidate and canonical dedupe rules pass.
- `DUPLICATE` — deterministic Raw-level duplicate candidate fingerprint; never create another Candidate from this record.
- `CONTEXT_ONLY` — conversational/context record, not a standalone Candidate payload.
- `INVALID/NOISE` — non-Candidate contact/internal/noise pattern.
- `NEEDS_DQ` — unresolved or master-dependent state; no promotion until resolved.

Current conservative classification of the 86 NOT_READY Raw records:

| Category | Raw records | Meaning |
|---|---:|---|
| `DUPLICATE` | 42 | duplicate Raw fingerprints; do not promote independently |
| `CONTEXT_ONLY` | 1 | context-only false Candidate shape |
| `INVALID/NOISE` | 1 | non-Candidate/contact false shape |
| `NEEDS_DQ` | 42 | representative/uncertain rows requiring live Data Hub Master lookup |
| `ALREADY_IN_MASTER_LINK_MISSING` | 0 proven | cannot be asserted without Data Hub read-back |
| `NEW_CANDIDATE_NEEDS_PROMOTION` | 0 proven | cannot be asserted without Data Hub read-back |

No Candidate Master row was created by this work.

## 4. Master-effect reconciliation rule

For a Raw record to be linked to an existing Candidate Master Effect, all of the following must be proven:

1. canonical Candidate ID exists in the operational Data Hub Candidate Master,
2. Raw identity/dedupe evidence matches that Candidate,
3. source/message evidence identifies the originating Raw,
4. the linkage is recorded back as an audit/control effect,
5. no new Candidate Master row is created by bypassing the existing command/event flow.

Until the Google Data Hub read adapter/read-back is available, master-dependent reconciliation remains `NOT_READY`.

## 5. LINE identity mapping

Only identities supported by evidence may become `VERIFIED`.

Evidence-backed mapping completed:

- `LINE_OA:MYC_DATA_BOT`
- identity `U1738e96a0eff5456a4656a2435712447`
- display name observed: `สรรหางานมิ้นท์ PYK`
- linked entity: `Partner / MYC-P-0001`
- evidence: existing applied parser rule plus `193` consistent Raw attributions

All other observed LINE identities remain `UNVERIFIED`; display names alone are not proof of identity.

## 6. Context Resolver V1

Read model: `ops.line_context_resolution_v`

Scope is mandatory:

`source_account_ref + thread_id + sender/reply context + time`

Resolution order:

1. explicit `quotedMessageId` found in the same source account + thread → `RESOLVED_REPLY`, confidence 100;
2. no explicit reply: nearest non-context Raw from the same source account + thread + sender within 120 seconds → `RESOLVED_RECENT_SENDER_CONTEXT`, confidence 80;
3. otherwise → `NEEDS_DQ`, confidence 0.

Current real-Raw result:

- `RESOLVED_REPLY`: 27
- `RESOLVED_RECENT_SENDER_CONTEXT`: 15
- `NEEDS_DQ`: 1
- cross-thread/source-account anchor violations: 0

Examples proved in TEST include:

- `อันนี้นะ` immediately after an image → resolved to the prior same-sender image;
- `คนนี้...` with LINE quoted message → resolved by exact quoted message ID;
- `ใช่ค่ะ` without a safe anchor → `NEEDS_DQ`.

The resolver is read-only and cannot mutate Master data.

## 7. Unified worker readiness

Read model: `ops.unified_worker_readiness_v`

Registry/enabled status is never treated as RUNNING.

Readiness semantics:

- `READY`: fresh runtime heartbeat + real successful run evidence + no blocking dead-letter/dependency condition.
- `PARTIAL`: runtime evidence exists but domain coverage/dependency/data-completeness is incomplete.
- `NOT_STARTED`: registry/config only; no heartbeat or successful run evidence.
- `BLOCKED`: disabled, stale/unhealthy heartbeat, or explicit runtime blocker.

Current key matrix:

| Worker | Readiness | Evidence |
|---|---|---|
| `candidate_intake` | `PARTIAL` | fresh HEALTHY heartbeat + 3 successful runs, but Candidate completeness gap remains |
| `candidate_worker` | `NOT_STARTED` | no heartbeat/run evidence |
| `job_worker` | `NOT_STARTED` | no heartbeat/run evidence |
| `client_job_worker` | `NOT_STARTED` | no heartbeat/run evidence |
| `domain_router` | `NOT_STARTED` | no heartbeat/run evidence |
| `file_evidence_worker` | `NOT_STARTED` | no heartbeat/run evidence |
| `consent_worker` | `NOT_STARTED` | no heartbeat/run evidence |
| `followup_worker` | `NOT_STARTED` | no heartbeat/run evidence |
| `ar_worker` / finance workers | `NOT_STARTED` | no heartbeat/run evidence |
| `commission_worker` | `NOT_STARTED` | no heartbeat/run evidence |
| `retry_router` | `NOT_STARTED` | no heartbeat/run evidence |

## 8. File Intelligence Router V1

Function: `ops.file_intelligence_route_v1(mime_type, filename)`  
Evidence view: `ops.file_intelligence_compatibility_v`

This is deterministic MIME/file routing only. No paid semantic AI is activated.

The acceptance smoke verifies route recognition for all required types: image, PDF, DOCX, XLSX, CSV, TXT, audio, video.

Live LINE capture/storage evidence currently proves:

| File type | Capture | Storage | Parse | Semantic AI | Production-ready |
|---|---|---|---|---|---|
| image | `CAPTURE_SUPPORTED` (83 observed) | `STORAGE_SUPPORTED` (83 mirrored) | `UNSUPPORTED` / not proven | `SEMANTIC_AI_NOT_READY` | FALSE |
| PDF | `CAPTURE_SUPPORTED` (1 observed) | `STORAGE_SUPPORTED` (1 mirrored) | `UNSUPPORTED` / not proven | `SEMANTIC_AI_NOT_READY` | FALSE |
| DOCX | `UNSUPPORTED` / no live E2E evidence | `UNSUPPORTED` | `UNSUPPORTED` | `SEMANTIC_AI_NOT_READY` | FALSE |
| XLSX | `UNSUPPORTED` / no live E2E evidence | `UNSUPPORTED` | `UNSUPPORTED` | `SEMANTIC_AI_NOT_READY` | FALSE |
| CSV | `UNSUPPORTED` / no live E2E evidence | `UNSUPPORTED` | `UNSUPPORTED` | `SEMANTIC_AI_NOT_READY` | FALSE |
| TXT | `UNSUPPORTED` / no live E2E evidence | `UNSUPPORTED` | `UNSUPPORTED` | `SEMANTIC_AI_NOT_READY` | FALSE |
| audio | `UNSUPPORTED` / no live E2E evidence | `UNSUPPORTED` | `UNSUPPORTED` | `SEMANTIC_AI_NOT_READY` | FALSE |
| video | `CAPTURE_SUPPORTED` (2 observed) | `STORAGE_SUPPORTED` (2 mirrored) | `UNSUPPORTED` / not proven | `SEMANTIC_AI_NOT_READY` | FALSE |

A ZIP file is also observed and mirrored but is outside the required compatibility matrix.

`UNSUPPORTED` in this matrix means not proven by current live TEST evidence; it does not claim the provider can never support the type.

## 9. Consent lookup contract

Read model: `ops.consent_readiness_v`

Operational consent authority remains:

`MEYOU_CONNECT_MVP_DATA_HUB_V1 / 14_Consent_PDPA`

Current Supabase `privacy.consents` row count is `0`. An empty shadow/technical registry must never be interpreted as permission.

Until live Data Hub consent evidence is read and verified:

- `readiness = NOT_READY`
- `datahub_readback_verified = FALSE`
- `Auto Submit = FALSE`

Candidate/B2B automation must fail closed on consent.

## 10. B2B response event semantic map

Read model: `ops.b2b_response_event_map_v`

The Founder-provided response taxonomy maps into the existing Event Kernel as follows:

- `ACCEPTED` → `b2b.response.accepted`
- `REJECTED` → `b2b.response.rejected`
- `NEED_INFO` → `b2b.response.need_info`
- `APPOINTMENT` → `b2b.response.appointment`
- `SLOT_CLOSED` → `b2b.response.slot_closed`
- `REQUIREMENT_CHANGED` → `b2b.response.requirement_changed`
- `WAITING` → `b2b.response.waiting`

This mapping is contract-only. It does not emit an event or apply any Master effect. Future emission must use the existing `ops.events` / `register_event` path and existing permission/validation/effect gates.

The referenced Drive document body `MYC_CANONICAL_B2B_AUTOMATION_LOGIC_V1_20260914` was not available to this execution, so no additional semantics beyond the explicit canonical taxonomy were invented.

## 11. Data Hub synchronization state

Current technical Raw intake is live and current through `2026-09-14T12:41:55.647124Z`, while `candidate_intake` heartbeat is current through `2026-09-14T14:25:00.201892Z`.

However, live Google Data Hub read-back could not be executed in this run because the Google Drive connector was unavailable after connection access failed. Therefore:

- Candidate Master reconciliation is not closed;
- `14_Consent_PDPA` read-back is not closed;
- Data Hub freshness cannot be honestly marked PASS;
- the 42 representative Candidate-shaped rows remain `NEEDS_DQ`/master-lookup required;
- no incremental Master-sync repair was attempted without live authority read-back.

This is fail-safe behavior, not a Source-of-Truth change.

A separate technical inconsistency was observed and remains for DQ review: one `channel.raw.received` event (`MYC-RAW-000929`) has Event `source_system=LINE` while its Raw record has `source_system=CHATGPT` and content type `CANONICAL_ROUTE_MASTER`. It must not be silently rewritten without provenance review.

## 12. Test gates completed

- Real Raw context replay/read evaluation: PASS
- Duplicate replay / existing LINE classification idempotency: PASS; replay returned duplicate twice and effect count remained 1
- Thread/source-account isolation: PASS; 0 cross-thread/account anchors
- Reconciliation workbench: PASS as conservative read model; Master-dependent closure BLOCKED by Data Hub read-back
- DQ fallback: PASS; ambiguous context produces `NEEDS_DQ`
- Worker heartbeat evidence: PASS; readiness no longer equates registry to runtime
- File router for 8 required MIME families: PASS contract smoke
- Live capture/storage evidence: PARTIAL (image/PDF/video proven; DOCX/XLSX/CSV/TXT/audio not live-tested)
- Consent fail-closed: PASS (`Auto Submit = FALSE`)
- Data Hub read-back: BLOCKED / NOT_RUN due connector availability
- Security Advisor after DDL: PASS / 0 security lints

Performance Advisor reports only pre-existing informational unused-index findings; this P0 work adds no new indexes.

## 13. Engineering handoff for Issue #23

Safe to bind server-side now:

- `ops.line_context_resolution_v`
- `ops.unified_worker_readiness_v`
- `ops.file_intelligence_compatibility_v` through service-role server adapter
- `ops.consent_readiness_v`
- `ops.b2b_response_event_map_v`
- existing `ops.candidate_promotion_gap_v`
- `ops.candidate_reconciliation_workbench_v` for completeness warnings / operator review only

Do not expose these tables/views directly to the browser. Browser continues to use `/api/v1/read/**` from Official Read Contract V1.

Candidate completeness-dependent UI actions remain blocked until the server-side Google Data Hub adapter can perform live Candidate Master and consent read-back.

## 14. Next implementation

1. Restore/authorize the server-side Google Data Hub reader and perform live Candidate Master reconciliation for the 42 representative `NEEDS_DQ` fingerprints.
2. For proven existing Candidates only, reconcile missing Raw/message/evidence → operational Master-effect linkage; do not create a new Candidate.
3. For proven new Candidates only, send through the existing command/event/validation path; never direct-write Master.
4. Generalize the existing Candidate parser away from the current Next-Can-specific behavior only after canonical Job resolution and dedupe behavior are defined; do not replay all historic gaps beforehand.
5. Run real E2E capture tests for DOCX/XLSX/CSV/TXT/audio before changing those compatibility states.
6. Implement B2B event emission on the existing Event Kernel only after the full canonical B2B contract is readable and consent gate is READY.
