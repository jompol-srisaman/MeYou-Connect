# Part 6 Wave 6C — Founder / Role Dashboard Surfaces + Performance Benchmark

Status: **CLOSED / PASS (TEST FOUNDATION)**  
Part 6 TEST Foundation: **CLOSED / 12 of 12 canonical Analytics Acceptance PASS**  
Official PostgreSQL Analytics: **NOT_READY**  
Date: 2026-09-01 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Implemented from:

- `MEYOU_CONNECT_ANALYTICS_DATA_MART_DASHBOARD_BLUEPRINT_V1.md`
- `MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1`
- `MEYOU_CONNECT_KPI_REPORTING_STANDARD_V2.md`
- KPI Catalog tabs `04_Dashboard_Pages`, `06_Refresh_Strategy`, `08_Analytics_Acceptance`

Canonical rules preserved:

- Dashboard is a consumer, not a Source of Truth.
- Founder dashboard prioritizes Cash / Collected / AR / Client Demand / Placement / DQ before vanity metrics.
- `0` is not `NOT_READY`.
- Role dashboards follow Part 5 authorization boundaries.
- Dashboard responses expose freshness/as-of/readiness.
- Official PostgreSQL business metrics are not published while PostgreSQL remains TEST/shadow.
- Normal SQL views remain the default.
- Materialized views are introduced only after measured performance need.
- Founder primary internal response target is approximately 5 seconds.

## Dashboard contract

Implemented **8 canonical dashboard pages**:

1. Founder Daily
2. Founder Weekly
3. Founder Monthly
4. Candidate Ops
5. Client & Sales
6. Finance
7. Partner Review
8. Data Quality

`analytics.dashboard_pages` stores the canonical page contract including audience, top row, sections, default filters, drill-through, freshness, rule and role capability.

`analytics.dashboard_kpi_map` contains **58 KPI-to-page mappings** using only canonical KPI IDs from the Part 6 KPI Catalog.

## Role-scoped capabilities

Added page-specific capabilities such as:

- `founder_dashboard_read`
- `candidate_ops_dashboard_read`
- `client_sales_dashboard_read`
- `finance_dashboard_read`
- `partner_dashboard_read`
- `dq_dashboard_read`

Candidate Ops, Client Sales and Finance roles receive only their intended dashboard surface. Founder/Data Audit have broader access according to existing internal authority. Content Studio receives no analytics dashboard capability.

Direct access to Analytics contract/benchmark tables remains denied to `anon` and `authenticated`.

## Semantic surfaces

Implemented normal SQL views:

- `analytics.founder_daily_v`
- `analytics.founder_weekly_v`
- `analytics.founder_monthly_v`
- `analytics.candidate_ops_dashboard_v`
- `analytics.client_sales_dashboard_v`
- `analytics.finance_dashboard_v`
- `analytics.data_quality_dashboard_v`
- existing `analytics.partner_performance_v` reused for Partner Review

Founder surfaces preserve the intended time semantics:

- Daily: today + current as-of operational controls
- Weekly: last 7 days + eligible cohort metrics
- Monthly: current month + accounting close state

Appointment rates remain null/blocked when normalized outcomes are ambiguous. Retention rates remain null when the eligible cohort is missing or unresolved. Finance Collected continues to use evidence-backed reconciled payment semantics.

## KPI evaluator V3

`analytics.evaluate_kpi_v3(...)` extends the existing semantic evaluator with additional safe snapshot/runtime metrics used by dashboards, including:

- Open Job Demand
- Open Headcount with PARTIAL behavior for missing confirmed headcount
- Expected Revenue
- Earned Revenue
- Invoiced Revenue
- Client Outstanding / AR readiness
- Commission Payable
- Cash Balance readiness

The existing Part 6A/6B semantic evaluators remain the fallback for other KPI definitions.

## Dashboard API

Read-only API:

- `api.analytics_dashboard_contract(page_key)`
- `api.analytics_dashboard(page_key)`
- updated `api.analytics_kpi_result(kpi_id)` using evaluator V3
- `api.analytics_part6_status()`

Important shadow-source gate:

When `analytics_postgres_publish_enabled = false`, authorized Dashboard API calls return:

- `status = NOT_READY`
- `blocked_reason = POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE`
- freshness/readiness metadata
- `data = null`

Therefore TEST numbers cannot leak into an official business dashboard merely because a user has dashboard permission.

## Query benchmark / materialization decision

Implemented:

- `analytics.query_benchmark_samples`
- `analytics.materialization_decisions`
- `analytics.benchmark_dashboard_surface(...)`
- `analytics.evaluate_materialization_need(...)`
- `analytics.surface_definition_hash(...)`

Benchmark forces full-row JSON serialization so the query cannot be reduced to a trivial projected column count.

Actual TEST/shadow benchmark collected **110 samples**:

| Surface | Samples | p95 ms | Max ms |
| --- | ---: | ---: | ---: |
| Candidate Ops | 10 | 1.3060 | 2.1610 |
| Client Sales | 10 | 2.2582 | 3.9880 |
| Data Quality | 10 | 2.2330 | 3.9340 |
| Finance | 10 | 8.2374 | 14.6540 |
| Founder Daily | 20 | 4.2842 | 79.1870 |
| Founder Monthly | 20 | 1.6033 | 23.6690 |
| Founder Weekly | 20 | 1.9603 | 32.4420 |
| Partner Review | 10 | 1.7139 | 3.0270 |

Founder page accepted threshold: **5,000 ms**.

Measured decisions:

- Founder Daily → `KEEP_NORMAL_VIEW`
- Founder Weekly → `KEEP_NORMAL_VIEW`
- Founder Monthly → `KEEP_NORMAL_VIEW`

No `founder_weekly_mv` or `monthly_review_mv` was created.

These timings are TEST/shadow measurements on a low/no-production-traffic database. They prove that materialization is not justified now; they are not a Production performance guarantee.

## AN-011 — PASS

Canonical acceptance scenario `AN-011` is now **PASS**.

Acceptance proved:

1. Real measured Founder p95 is below the accepted 5-second target.
2. Normal views remain the chosen implementation when measured performance is sufficient.
3. A synthetic policy-branch benchmark above threshold returns `RECOMMEND_MATERIALIZATION`.
4. The recommendation does not auto-create a materialized view.
5. Semantic view-definition hash remains unchanged by the decision process.
6. Synthetic policy samples and decisions are removed after the smoke test.

This tests the materialization gate without manufacturing a fake slow production workload or falsely claiming a materialized view is needed today.

## Role / API acceptance

Synthetic Auth acceptance verified:

- Candidate Ops → Candidate Ops Dashboard allowed; Finance Dashboard denied.
- Client Sales → Client & Sales Dashboard allowed; Candidate Ops Dashboard denied.
- Finance Control → Finance Dashboard allowed; Partner Review denied.
- Content Studio → Data Quality/Analytics dashboard denied.
- Founder → Founder Daily contract/dashboard allowed.
- direct Analytics table query by authenticated client denied.
- all authorized dashboard calls still return `NOT_READY` while publish is OFF.

Synthetic Auth users remaining after smoke: **0**.
Synthetic AN-011 policy benchmark rows/decisions remaining: **0**.

## Part 6 canonical acceptance

Final acceptance state:

- `AN-001` PASS
- `AN-002` PASS
- `AN-003` PASS
- `AN-004` PASS
- `AN-005` PASS
- `AN-006` PASS
- `AN-007` PASS
- `AN-008` PASS
- `AN-009` PASS
- `AN-010` PASS
- `AN-011` PASS
- `AN-012` PASS

**12 PASS / 0 NOT_RUN / 0 FAIL**.

## Current status

- Dashboard pages: **8**
- KPI mappings: **58**
- Canonical analytics acceptance: **12/12 PASS**
- Actual benchmark samples: **110**
- Founder maximum p95 among Daily/Weekly/Monthly: **4.2842 ms**
- Founder materialization decision: **KEEP_NORMAL_VIEW**
- Materialized views enabled: **false**
- Official PostgreSQL publish enabled: **false**
- Operational Source of Truth: `GOOGLE_SHEETS_DRIVE`

Settings:

- `analytics_dashboard_surfaces_ready = true`
- `analytics_query_benchmark_ready = true`
- `analytics_materialization_recommended = false`
- `analytics_materialization_enabled = false`
- `analytics_postgres_publish_enabled = false`
- `analytics_business_source_ready = false`
- `part6c_foundation_closed = true`
- `part6_foundation_closed = true`

Therefore:

**Part 6 TEST Foundation = CLOSED / PASS**

**Official PostgreSQL Analytics = NOT_READY**

## Security / performance

- Supabase Security Advisor: **PASS / 0 lint**
- no new missing-FK-index blocker
- remaining Performance Advisor notices are `unused_index` INFO on the low/no-traffic TEST environment
- no premature Materialized View was introduced

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Migration history

Part 6C migrations:

- `20260901014102` — dashboard contract + benchmark foundation
- `20260901014321` — dashboard semantic surfaces
- `20260901014357` — role-scoped dashboard API
- `20260901014440` — query benchmark + materialization policy
- `20260901014530` — actual dashboard benchmark
- `20260901014651` — dashboard/materialization acceptance smoke
- `20260901014822` — final closeout

Supabase total after Part 6C: **126 migrations**.

## Boundary after Part 6

Part 6 semantic/dashboard foundation is complete in TEST.

This does not switch the business Source of Truth and does not authorize official PostgreSQL publishing. Google Sheets + Google Drive remain operational until a separately approved production/cutover process completes.

Next architecture track: **Part 7 — Scale / Multi-province / Portal**, beginning with a TEST-first geography/organization/portal-access foundation rather than a Production portal launch.
