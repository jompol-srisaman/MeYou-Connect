# P0 Read Gate Closure + Live Reconciliation — 2026-09-15

Status: `PARTIAL`  
Related: #14, #23, PR #22, PR #26  
Supabase TEST: `pgjmxdeafzogzsyawejs`  
Operational business Source of Truth: `MEYOU_CONNECT_MVP_DATA_HUB_V1 / GOOGLE_SHEETS_DRIVE`

## Boundary

No new architecture was introduced. No second Raw→Master pipeline was created. No protected business Master table was direct-written. No Source of Truth was changed. No Production cutover or paid AI/API activation was performed.

## A. LINE Inbox server read gate

Official Operational Read Contract V1 requires browser reads through `/api/v1/read/**`; browser roles must not directly read `ops.line_inbox_v`.

Before migration:

- `service_role SELECT = FALSE`
- `anon SELECT = FALSE`
- `authenticated SELECT = FALSE`

Applied TEST migration:

- `20260915164139_p0_line_inbox_service_role_read_gate_v1`

After migration:

- `service_role SELECT = TRUE`
- `anon SELECT = FALSE`
- `authenticated SELECT = FALSE`

A second TEST migration `20260915165343_p0_line_inbox_service_role_runtime_smoke_v1` executed `SELECT count(*) FROM ops.line_inbox_v` under `SET LOCAL ROLE service_role` successfully and asserted browser-role denial. No underlying Raw-table privilege was broadened.

Rollback of the privilege change is one statement:

`REVOKE SELECT ON ops.line_inbox_v FROM service_role;`

## B. Candidate reconciliation snapshot

Latest TEST state observed:

- `VERIFIED_MASTER_EFFECT / READY = 3`
- `RAW_CANDIDATE_SHAPE_UNPROMOTED / NOT_READY = 130`

Conservative reconciliation workbench:

- `DUPLICATE = 65`
- `CONTEXT_ONLY = 3`
- `INVALID/NOISE = 1`
- `NEEDS_DQ = 61`
- `ALREADY_IN_MASTER_LINK_MISSING = 0 proven in this execution`
- `NEW_CANDIDATE_NEEDS_PROMOTION = 0 proven in this execution`

The 130 NOT_READY Raw records are not interpreted as 130 missing Candidates.

Live Google Data Hub Candidate Master reconciliation could not be completed in this execution. The Google Drive connector was actually retried and the connector runtime disabled the tool for this chat. The existing private PWA Data Hub adapter was also inspected: it is read-only and requires server-side Google credentials; the protected Vercel preview could not be used to obtain independent Data Hub read-back from this execution.

Therefore no Master-dependent reconciliation category was asserted and no Candidate Master record was created.

## C. Raw → Google Data Hub synchronization finding

Latest Supabase LINE Inbox:

- records: `1430`
- latest Raw: `MYC-RAW-001440`
- latest received: `2026-09-15T13:05:15.659626Z`

Repository, Supabase functions/tables, pg_cron jobs, and active LINE Edge Functions were inspected. No implemented automatic Supabase Raw → Google Data Hub `19_Raw_Input_Log` writer/scheduler lane was found in these connected assets.

The active LINE capture path is source-aware and idempotent inside Supabase: provider event ID and source account are mapped through `ops.channel_event_raw_map`, and Raw IDs are allocated through `config.allocate_business_id('Raw Input', 'LINE_CAPTURE', ...)`. It does not write Google Data Hub.

Because the operational Data Hub writer/read-back path was not located and direct Drive access was disabled in this execution, the required real 3-row proof:

`Supabase Raw → Google Data Hub row → rerun → no duplicate`

is `NOT_RUN / BLOCKED`. No second sync architecture was invented to manufacture a PASS.

Raw synchronization must never depend only on the numeric suffix of `MYC-RAW-*`; source account/provider identity and canonical Raw ID are required.

## D. Identity

Registry state:

- `VERIFIED = 1`
- `PARTIAL = 0`
- `UNVERIFIED = 8`

LINE Inbox rows by identity state:

- VERIFIED rows: `328`, 1 distinct sender
- UNVERIFIED rows: `1102`, 7 distinct senders

The verified mapping remains:

`LINE_OA:MYC_DATA_BOT / U1738e96a0eff5456a4656a2435712447 → Partner MYC-P-0001`

No other identity was promoted from display name alone.

## E. Consent

Technical `privacy.consents` rows remain `0`.

Canonical lookup contract remains:

- authority: `MEYOU_CONNECT_MVP_DATA_HUB_V1 / 14_Consent_PDPA`
- `datahub_readback_verified = FALSE`
- `Auto Submit = FALSE`
- `readiness = NOT_READY`

No consent was inferred or created from ordinary conversation.

## F. Worker readiness

Current runtime evidence:

- `PARTIAL = 1`: `candidate_intake`
- `NOT_STARTED = 25`
- `READY = 0`
- `BLOCKED = 0`

`candidate_intake` has a fresh HEALTHY heartbeat and 3 successful historical runs, but remains PARTIAL because Candidate completeness is not closed.

For PWA V0.1 Read Gate, the ongoing technical worker dependency is `candidate_intake`. Official read projections are read paths, not worker processes. The remaining registry-only workers should not be started merely to improve the readiness count. Finance, commission, placement, portal-action, notification, and later domain-effect workers can remain Phase-later until their write/action features are in scope.

## G. File compatibility

Live LINE capture/storage evidence remains:

- image: 83 captured / 83 mirrored
- PDF: 1 / 1
- video: 2 / 2
- ZIP: 1 / 1 outside the requested matrix
- DOCX/XLSX/CSV/TXT/audio: no live E2E evidence

The Edge Function code can receive generic LINE `file` and `audio` message classes, but code capability is not treated as live compatibility evidence. Semantic AI remains NOT_READY and no paid provider was activated.

## H. Provenance DQ — MYC-RAW-000929

Root cause is now proven.

1. Migration `20260914065128_sync_thai_inaba_routes_20260914_driver_snapshot` hardcoded `MYC-RAW-000929` as a `CHATGPT / CANONICAL_ROUTE_MASTER` Raw record instead of reserving the Raw ID through `config.allocate_business_id`.
2. The canonical Raw allocator therefore still considered 929 available.
3. At `2026-09-14T06:59:41.348394Z`, live LINE capture legitimately allocated `MYC-RAW-000929` to provider event `LINE:DATA_BOT:01M2FBDR2ZW6QSBJTPD9FM7DF9`.
4. `ops.channel_event_raw_map` and the associated completed `LINE / channel.raw.received` event point to the same Raw ID, while the Raw row itself remains CHATGPT.
5. This is a canonical Raw-ID provenance collision caused by the manual hardcoded Raw ID, not by the LINE idempotency allocator.

Applied migration:

- `20260915165210_p0_raw_000929_provenance_collision_dq_v1`

It created/opened:

- `MYC-DQ-000013`
- issue type `RAW_ID_PROVENANCE_COLLISION`
- severity `HIGH`
- status `OPEN`

No Raw/Event provenance was silently rewritten. Repair requires an explicit re-key/provenance preservation plan.

## I. Test gate

- service_role `line_inbox_v` actual runtime SELECT under role: PASS
- anon/authenticated privilege boundary: PASS
- real Candidate Raw replay: PASS
- duplicate replay/idempotency: PASS; repeated Candidate replay remained duplicate and one classification effect only
- latest real Raw (`MYC-RAW-001440`) replay: PASS; `UNSUPPORTED_CONTENT`, duplicate-safe, one classification effect
- thread/source-account isolation: PASS; 0 violations
- context DQ fallback: PASS; `MYC-RAW-000795 / ใช่ค่ะ` remains NEEDS_DQ with confidence 0
- Candidate Data Hub reconciliation: BLOCKED / NOT_RUN
- Data Hub Raw read-back / 3-row sync idempotency: BLOCKED / NOT_RUN
- consent fail-closed: PASS
- Security Advisor after DDL: PASS / 0 lints
- Performance Advisor: INFO-only pre-existing unused-index notices; no new index introduced by this round

## Engineering runtime handoff

PWA server-side reader may now bind `ops.line_inbox_v` using the approved Supabase service role. Browser roles remain denied.

The PWA live-read implementation on `feat/p0-official-read-bind` already contains a private Google Sheets reader and Supabase service-role reader. Runtime still requires server-side credentials; no credential change was performed in this round.

Candidate completeness-dependent actions must remain blocked while 130 Candidate-shaped Raw records are NOT_READY and 61 representative rows still require Data Hub Candidate Master reconciliation.

Auto Submit must remain FALSE until `14_Consent_PDPA` is live-read and verified.

Raw→Data Hub sync must be closed by locating/fixing the existing intended writer lane, not by adding a parallel pipeline. The first acceptance proof after that lane is available must use at least three real, source-aware Raw records, read them back from `19_Raw_Input_Log`, rerun the same sync batch, and prove no duplicate rows.

## Gate decision

`READ GATE DATA SIDE = PARTIAL`

Reason: the Supabase server-read privilege blocker is closed and technical replay/security gates pass, but the operational Data Hub Candidate/Consent read-back and Raw→Data Hub synchronization/read-back gates are not yet closed.
