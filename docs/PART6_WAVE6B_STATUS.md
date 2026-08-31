# Part 6 Wave 6B — Historical Funnel / Appointment / Retention / Attribution Normalization

Status: **CLOSED / PASS (TEST FOUNDATION)**  
Core Analytics Acceptance: **11 / 12 PASS**  
Remaining Acceptance: **AN-011 — performance/materialization measured-need test**  
Official PostgreSQL Analytics: **NOT_READY**  
Date: 2026-08-31 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Implemented from:

- `MEYOU_CONNECT_ANALYTICS_DATA_MART_DASHBOARD_BLUEPRINT_V1.md`
- `MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1`
- `MEYOU_CONNECT_KPI_REPORTING_STANDARD_V2.md`

Canonical rules preserved:

- Current state is not historical stage history.
- Show / No-show rates require standardized occurred-appointment outcomes.
- Ambiguous or unverified appointment outcomes block official rates.
- Retention facts use D7 / D30 / D90 / D120 standardized milestone outcomes.
- Partner KPIs credit only approved, traceable attribution.
- Current `candidate.partner_id` alone is not sufficient analytics attribution.
- Accounting monthly reporting is derived from POSTED journal data.
- Monthly finance reporting is labeled PROVISIONAL or CLOSED from close-check state.
- Drill-through exposes business/provenance IDs only, not PII.
- PostgreSQL remains TEST/shadow and official analytics publish stays disabled.

## Implemented

### Normalized facts

- `analytics.appointment_outcome_fact`
- `analytics.partner_attribution_fact`
- existing `analytics.stage_transition_fact` reused and given idempotent recorder
- existing `analytics.placement_milestone_fact` reused with follow-up normalizer

Appointment outcome vocabulary:

- SHOW
- NO_SHOW
- CANCELLED
- RESCHEDULED
- UNKNOWN
- NEEDS_REVIEW

Partner attribution states:

- APPROVED
- REJECTED
- NEEDS_REVIEW

Approved attribution requires traceable Raw Input or Evidence plus reviewer identity/time.

### Idempotent server-only writers

- `analytics.record_stage_transition(...)`
- `analytics.record_appointment_outcome(...)`
- `analytics.record_partner_attribution(...)`
- `analytics.normalize_followup_milestone(...)`

These functions are service-role only. No browser-facing analytics write API was added.

### Semantic views

- `analytics.appointment_outcome_current_v`
- `analytics.partner_attribution_current_v`
- `analytics.candidate_funnel_period_v`
- `analytics.partner_performance_v`
- `analytics.finance_monthly_v`

Late-arriving observations do not silently rewrite history. Current semantic views select the strongest/latest normalized observation and expose conflict as NEEDS_REVIEW where verified outcomes conflict.

### KPI evaluator V2

- `analytics.evaluate_kpi_v2(...)`

Additional runtime semantics implemented for:

- KPI-CAN-004 Appointment Rate
- KPI-CAN-005 Show Rate
- KPI-CAN-006 No-show Rate
- KPI-PAR-001 Partner Leads
- KPI-PAR-002 Partner Starts
- KPI-PAR-003 Partner Start Conversion

Existing Part 6A KPI semantics continue through the original evaluator fallback.

### Read-only API

- updated `api.analytics_kpi_result(kpi_id)` to evaluator V2
- `api.analytics_kpi_drillthrough(kpi_id, limit)`
- `api.analytics_finance_monthly(month)`

Access still requires `analytics_read` capability.

Drill-through returns only identifiers/provenance such as:

- Candidate / Placement / Revenue / Partner IDs
- Evidence ID
- Raw Input ID
- occurred timestamp
- semantic source object

It does not expose Candidate PII.

## Acceptance results

Part 6B passed:

- `AN-003` — NO_SHOW numerator/occurred appointment denominator
- `AN-004` — ambiguous appointment outcome blocks/flags rate
- `AN-007` — partner response/current partner field without approved attribution receives no KPI credit
- `AN-008` — Content Studio denied analytics API / no Candidate PII or Finance analytics exposure
- `AN-010` — Founder KPI drill-through resolves underlying entity/provenance IDs
- `AN-012` — monthly accounting semantic derives from POSTED journal and labels CLOSED only after 6/6 close checks pass

Combined with Part 6A:

- **AN-001…010 = PASS**
- **AN-012 = PASS**
- **AN-011 = NOT_RUN**

Overall canonical acceptance: **11 PASS / 1 NOT_RUN / 0 FAIL**.

AN-011 is intentionally deferred because the architecture says materialization is introduced only after measured query/performance need. Part 6B does not manufacture a slow workload just to justify a materialized view.

## Smoke / cleanup

Acceptance also proved:

- appointment fact recording is idempotent
- partner attribution recording is idempotent
- synthetic Auth impersonation enforces `analytics_read`
- synthetic Founder drill-through works under temporary TEST-only publish gate
- all TEST-only publish changes are restored before migration commit

Synthetic residue after test:

- appointment facts: 0
- attribution facts: 0
- synthetic journal: 0
- synthetic Auth users: 0

## Safety state

- `part6b_foundation_closed = true`
- `analytics_core_acceptance_ready = true`
- `analytics_postgres_publish_enabled = false`
- `analytics_business_source_ready = false`
- `analytics_materialization_enabled = false`
- `current_operational_source = GOOGLE_SHEETS_DRIVE`

Therefore:

**Part 6B Foundation = CLOSED / PASS**

**Official PostgreSQL Analytics = NOT_READY**

Google Sheets + Google Drive remain the operational Source of Truth.

## Security / performance

- Supabase Security Advisor: **PASS / 0 lint**
- no missing-FK-index blocker
- remaining notices are `unused_index` INFO in TEST
- materialized views remain disabled

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Migration history

- `20260831162649` — normalized fact foundation
- `20260831162827` — semantic views + evaluator extension
- `20260831162914` — read API + RLS hardening
- `20260831163119` — pgcrypto schema hardening
- `20260831163234` — KPI evaluator name hardening
- `20260831163404` — core analytics acceptance smoke
- `20260831163546` — final closeout

Supabase total after Part 6B: **119 migrations**.

## Boundary after 6B

Part 6B completes the core semantic correctness acceptance except the measured-performance/materialization scenario.

Next implementation track: **Part 6C — Founder/Role Dashboard Semantic Surfaces + Query Performance Benchmark + AN-011 materialization decision**, while keeping official PostgreSQL analytics publishing OFF until the operational-source cutover is explicitly approved.
