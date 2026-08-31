# Part 6 Wave 6A — Analytics Readiness / KPI Semantic Layer Foundation

Status: **CLOSED / PASS (TEST FOUNDATION)**  
Official PostgreSQL Analytics: **NOT_READY**  
Date: 2026-08-31 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Implemented from:

- `MEYOU_CONNECT_ANALYTICS_DATA_MART_DASHBOARD_BLUEPRINT_V1.md`
- `MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1`
- `MEYOU_CONNECT_KPI_REPORTING_STANDARD_V2.md`

Canonical rules preserved:

- Dashboard is a consumer, not a Source of Truth.
- Current Snapshot, Historical/Event and Cohort KPIs are separate semantic classes.
- `0` is not the same as `NOT_READY`.
- Historical funnels must use actual stage-transition history, never reconstruction from current status.
- Retention denominators include only mature/eligible starts.
- Official Collected requires verified payment evidence and reconciled incoming bank match.
- Partner attribution must be evidence-backed before credited analytics.
- Business reporting timezone is `Asia/Bangkok`.
- Freshness/as-of/readiness must be visible.
- Important KPI surfaces must support authorized drill-through to underlying entity/evidence.

## Implemented

### Analytics foundation

- `analytics` schema
- `analytics.kpi_catalog`
- `analytics.semantic_rules`
- `analytics.dq_gate_catalog`
- `analytics.acceptance_catalog`
- `analytics.dim_date`
- `analytics.stage_transition_fact`
- `analytics.placement_milestone_fact`
- `analytics.source_freshness`

Canonical catalog loaded from Google source:

- **31 KPI IDs**
- **10 semantic rules (`SEM-001…010`)**
- **10 Data Quality gates (`DQG-001…010`)**
- **12 Analytics acceptance scenarios (`AN-001…012`)**

### Historical fact boundaries

`analytics.stage_transition_fact` stores only traceable stage transitions with Event / Raw Input / Evidence provenance.

It does not infer a historical LEAD / QUALIFIED / APPOINTED state from a candidate's current status.

`analytics.placement_milestone_fact` standardizes retention outcomes for:

- D7
- D30
- D90
- D120

Allowed outcome vocabulary includes:

- ACTIVE / PASS
- LEFT / DROPOUT
- UNKNOWN / NOT_REACHED
- CONTACT_FAILED / NEEDS_REVIEW

No historical or retention facts are auto-invented/backfilled by Part 6A.

### Semantic views

- `analytics.candidate_current_v`
- `analytics.candidate_stage_events_v`
- `analytics.placement_cohort_v`
- `analytics.job_demand_v`
- `analytics.finance_collected_official_v`
- `analytics.data_quality_v`
- `analytics.source_readiness_v`

### KPI evaluator

- `analytics.evaluate_kpi(...)`

The evaluator has explicit `READY / PARTIAL / NOT_READY` behavior.

Key safeguards:

- no eligible retention cohort → `NOT_READY`, not `0%`
- missing eligible milestone outcome → `NOT_READY`
- missing stage history → historical funnel KPI `NOT_READY`
- unmatched/unverified collected rows are excluded from official Collected
- stale sources become `STALE`
- unsupported runtime KPI in 6A returns `KPI_RUNTIME_IMPLEMENTATION_NOT_INCLUDED_IN_PART6A`

### Shadow-source safety gate

PostgreSQL remains TEST/shadow.

Official API calls cannot bypass this gate. While `analytics_postgres_publish_enabled = false`, PostgreSQL business KPI results return:

`NOT_READY / POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE`

This prevents an empty TEST database from being reported as real business zero.

### Read-only API / authorization

Added `analytics_read` capability to:

- Founder
- Secretary
- Data Audit

Read-only API:

- `api.analytics_foundation_status()`
- `api.analytics_kpi_catalog()`
- `api.analytics_kpi_result(kpi_id)`
- `api.analytics_source_readiness()`
- `api.analytics_acceptance_status()`

All analytics base tables use RLS with explicit DENY for `anon` / `authenticated`.

No browser-facing analytics write API was added.

## Acceptance smoke — PASS

Part 6A executed these canonical acceptance tests:

- `AN-001` — no D30-eligible placement => `NOT_READY`, never misleading `0%`
- `AN-002` — current STARTED candidate retains historical LEAD/QUALIFIED transition facts
- `AN-005` — chat claim that client paid does not change Collected KPI
- `AN-006` — verified payment evidence + reconciled incoming bank match enters official Collected
- `AN-009` — stale source produces `STALE` readiness

Passed in 6A: **5 / 12**.

The remaining 7 scenarios stay intentionally `NOT_RUN` for later Part 6 waves; they are not silently marked PASS.

Synthetic Candidate / Placement / Revenue / File / Evidence / Bank / stage-transition records remaining after smoke: **0**.

## Current status

- KPI catalog: **31**
- Semantic rules: **10**
- DQ gates: **10**
- Acceptance tests: **12 total / 5 PASS / 7 NOT_RUN**
- real stage-transition fact rows in PostgreSQL TEST: **0**
- real placement-milestone fact rows in PostgreSQL TEST: **0**
- reporting timezone: `Asia/Bangkok`

Settings:

- `analytics_foundation_ready = true`
- `part6a_foundation_closed = true`
- `analytics_business_source_ready = false`
- `analytics_postgres_publish_enabled = false`
- `analytics_materialization_enabled = false`
- `current_operational_source = GOOGLE_SHEETS_DRIVE`

Therefore:

**Semantic Foundation = CLOSED / PASS**

**Official PostgreSQL Analytics = NOT_READY**

## Security / performance

- Supabase Security Advisor: **PASS / 0 lint**
- no missing-FK-index blocker
- remaining performance notices are `unused_index` INFO in the low/no-traffic TEST environment
- no materialized views were introduced before measured need

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Migration history

Part 6A migrations:

- `20260831160133` — analytics semantic foundation
- `20260831160230` — canonical KPI Catalog seed
- `20260831160434` — semantic views + KPI evaluator
- `20260831160511` — read API + RLS hardening
- `20260831160702` — semantic acceptance smoke
- `20260831160824` — final closeout

Supabase total after Part 6A: **112 migrations**.

## Boundary after 6A

Part 6A creates the semantic/readiness foundation only.

It does **not** declare historical funnel or retention performance implemented from real business data, because the PostgreSQL historical facts are currently empty and PostgreSQL is not the operational Source of Truth.

Google Sheets + Google Drive remain the operational Source of Truth. No Production analytics publish, materialized-view rollout, warehouse replication, or Production cutover was enabled.

Next implementation track: **Part 6B — Historical Funnel / Appointment Outcome / Retention Fact Normalization + remaining core Analytics Acceptance**.
