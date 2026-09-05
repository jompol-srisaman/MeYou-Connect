# MYC Internal Operations Web App — Phase 0 Audit

Date: 2026-09-05  
Owner: AI ENGINEERING ORCHESTRATOR V1  
Repository: `jompol-srisaman/MeYou-Connect`  
Status: `PHASE0_AUDITED_P0_IMPLEMENTATION_STARTED`

## Guardrails

- Current brand: MeYou Connect / MYC.
- Operational Source of Truth remains `MEYOU_CONNECT_MVP_DATA_HUB_V1` (GOOGLE_SHEETS_DRIVE).
- Supabase project `pgjmxdeafzogzsyawejs` remains the existing technical/test-shadow platform and live LINE raw/event receiver.
- No Source-of-Truth cutover is authorized by this work.
- No parallel LINE Raw → Candidate pipeline may be created for `MYC-DQ-000011`.
- Protected production/security/financial actions retain Human Gates.

## Verified Existing / Reuse

### Repository / Part 3–7

- Event / automation kernel and worker controls.
- Core master schemas and canonical MYC ID alignment.
- Raw input, evidence, docs, privacy and consent foundations.
- AuthZ roles/capabilities, RLS and API projections.
- Finance state safety and read surfaces.
- Security / reliability / observability control plane.
- Analytics semantic layer, KPI contracts and role-scoped dashboard API.
- Geo / organization / portal access foundations.
- Controlled portal command/event boundary, MFA/step-up controls.
- Client Demand Lite technical pilot.
- Portal production readiness and province scale preflight gates.

### Supabase

- Existing schemas: `core`, `private`, `privacy`, `docs`, `ops`, `finance`, `authz`, `analytics`, `api`, `geo`, `config`.
- Existing read APIs include candidate/job/client/placement/finance/analytics/readiness surfaces.
- Existing analytics dashboard surfaces include Founder Daily/Weekly/Monthly, Candidate Ops, Client Sales, Finance, Partner Review and Data Quality.
- Analytics intentionally returns NOT_READY while PostgreSQL is TEST/shadow and not the operational Source of Truth.
- Existing active Edge Functions include LINE webhook ingestion and protected LINE backup export.

### Vercel

- Existing project `me-you-connect` is connected to this GitHub repository.
- Existing production deployment before P0 contained no application output and returned 404.
- Existing Vercel project must be reused.

### Google Drive / Data Hub

- `MEYOU_CONNECT_MVP_DATA_HUB_V1` exists and contains the canonical operational tabs.
- Current Control Index is MeYou Connect V3.6 / Part 7 final architecture.
- `MYC-DQ-000011` confirms LINE raw/event capture is healthy and downstream sync/promotion is the current candidate-data gap.

## Gap Map

| Area | Classification | Current truth | P0 action |
|---|---|---|---|
| App framework / UI | MISSING → STARTED | No frontend existed in repo | Build Next.js Internal Ops shell in existing repo/Vercel |
| Founder Dashboard | PARTIAL | Analytics contract exists; official live adapter absent | UI shell + official Data Hub adapter + technical health reads |
| Candidate Operations | BLOCKED BY DATA MANAGER | Candidate downstream promotion gap is open | Build UI boundary; do not create parallel promotion pipeline |
| Job workspace | PARTIAL | Job Master + read API foundations exist | Connect official read adapter |
| Client workspace | PARTIAL | Client Master/AuthZ/Demand Lite exist | Read-first workspace; controlled writes later |
| Partner workspace | PARTIAL | Partner/attribution foundations exist | Read-first workspace + evidence drillthrough |
| Auth for Internal App | PARTIAL | Supabase Auth/AuthZ schema exists; no live users/role assignments were present at audit | Implement only after approved credential/user activation path |
| Application API/backend | PARTIAL | SQL RPC/API surfaces exist; no web application server existed | Reuse API contracts, add app adapter only where needed |
| Edge Functions | EXISTING / REUSE | LINE functions active | Do not duplicate; application integration only |
| Vercel deployment | PARTIAL | Project linked, old production 404 | Preview P0 on branch; production activation remains gated |
| Operational data adapter | MISSING | Official source remains Drive/Sheets | Data Manager handoff + application read adapter |
| Production portal | BLOCKED / HUMAN GATE | Portal feature flags remain off | Do not activate in P0 |

## P0 Work Split

### Codex — Frontend / Test Lane

Own:
- `app/**`
- `components/**`
- presentation/UI tests
- build/CI checks

Must not modify:
- Supabase migrations
- canonical Data Contract / ID / event flow

### Claude Code — Integration Lane

Own:
- `lib/data/**`
- `app/api/**`
- backend adapter integration docs/tests

Must:
- reuse canonical API/data surfaces
- preserve operational Source-of-Truth authority
- avoid direct writes to protected master tables
- respect `MYC-DQ-000011` ownership

### Review

Implementer must not be the sole reviewer. Use cross-review before merge.

## First P0 Deliverable

Branch: `feat/p0-internal-ops-shell`

Deliver:
- MYC-branded Founder Control Center shell
- Founder/Candidate/Job/Client/Partner/System navigation
- explicit readiness/source state
- no fake business metrics
- Candidate DQ boundary visible
- preview deployment in the existing Vercel project

Production merge/activation is not authorized by this audit.
