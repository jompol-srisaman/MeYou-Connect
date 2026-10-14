# MYC — ENGINEER REALITY AUDIT
Date: 2026-10-09
Owner: Maple — MYC Engineering Control Lead
Status: REALITY AUDIT / NO PRODUCTION CHANGE

## 1. Audit Purpose
Validate the live technical and operational reality of MeYou Connect against the Founder Strategy Consolidation before Canonical Package, architecture migration, or new implementation.

This audit does not authorize production migration, database cutover, pricing changes, partner-rule changes, or business-model changes.

## 2. Executive Finding
MYC has a real operating business and a real technical stack, but the current stack is split between:
- Google Sheets / Drive as the live business master;
- Supabase as live raw/event ingestion plus a large shadow/infrastructure layer;
- Vercel as a deployed Founder WebApp/runtime surface;
- GitHub as code/migration/engineering-history source.

The most important structural gap is:
**the business truth has not been migrated into Supabase canonical core tables.**

Live evidence on 2026-10-09:
- Supabase project `pgjmxdeafzogzsyawejs` = ACTIVE_HEALTHY.
- `core.candidates`, `core.clients`, `core.jobs`, `core.placements`, `core.partners`, `core.followups` = 0 rows.
- `finance.revenue`, `finance.commissions` = 0 rows.
- `ops.raw_inputs` = 4,463 rows.
- `ops.events` = 4,626 rows.
- `ops.raw_datahub_sync_ledger` = 4,463 rows.
- `ops.shadow_import_rows` = 684,506 rows.
- `ops.shadow_import_sessions` = 2,757 rows.
- Google Data Hub remains populated and current; Candidate allocator is at MYC-C-000257 next, Job MYC-J-000018 next, Partner MYC-P-0011 next, Placement MYC-PL-000016 next, Raw Input MYC-RAW-004469 next.
- Data Hub has actual Candidate, Client, Partner, Job, Placement, Commission and DQ business rows.
- Vercel project `me-you-connect` has READY production deployments.
- The eight previously defined Official Read routes currently return HTTP 404 on the production alias.

## 3. Current Source-of-Truth Reality

### 3.1 Raw / Channel Provenance
Current live authority:
- Supabase `ops.raw_inputs`
- Supabase `ops.events`
- LINE Edge Functions / ingestion pipeline

Assessment: **KEEP / REPAIR**

Reason:
Raw/event capture is real and populated. It should not be replaced. It needs reconciliation, security hardening, and clear official-read contracts.

### 3.2 Business Operational Master
Current live authority:
- `MEYOU_CONNECT_MVP_DATA_HUB_V1`
- Google Drive evidence / controlled documents

Assessment: **KEEP TEMPORARILY → MIGRATE UNDER CONTROL**

Reason:
This is where current business records actually live. Supabase core tables are not yet the live business truth.

### 3.3 Target Structured Operational Truth
Founder-locked target:
- PostgreSQL / Supabase

Assessment: **TARGET CONFIRMED, CUTOVER NOT READY**

Required path:
Legacy Audit
→ Mapping
→ Reconciliation
→ Validation
→ Migration
→ Read-back
→ Controlled Cutover
→ Legacy Read-only

### 3.4 GitHub
Repository:
`jompol-srisaman/MeYou-Connect`

Assessment: **KEEP as Engineering Source of Truth**

Current README correctly states:
- Operational Source of Truth is still Google Sheets + Drive.
- Supabase production master is NOT_READY.
- Business namespace is MYC-*.
- Founder WebApp exists.
- Known gaps include missing Edge Function source and runtime pipeline defects.

### 3.5 Vercel
Project:
`me-you-connect`

Assessment: **KEEP / REPAIR RUNTIME CONTRACT**

Production deployment is READY at platform level, but this does not mean the MYC operating loop is production-ready.

Current official-read checks:
- /api/v1/read/inbox/line → 404
- /api/v1/read/system/health → 404
- /api/v1/read/jobs → 404
- /api/v1/read/clients → 404
- /api/v1/read/partners → 404
- /api/v1/read/candidates → 404
- /api/v1/read/dq → 404
- /api/v1/read/founder/today → 404

This is a P0 contract/runtime gap.

## 4. Data Model Reality vs Founder Strategy

### Current Supabase core
Existing core entities include:
- Candidate
- Client
- Job
- Partner
- Placement
- FollowUp

### Founder-locked domain decisions not yet fully represented
Required separation:
- Demand ≠ Job
- Person ≠ Candidate Profile
- Candidate ≠ Application
- Application ≠ Placement
- Current State ≠ Event History

Reality:
- There is an operational `client_demand_review_queue`, but not yet a canonical Demand domain master.
- There is no canonical Person domain master.
- There is no canonical Application domain master.
- Event history infrastructure exists and is substantial.
- Current core schema is therefore not yet sufficient for the locked MYC V2 domain model.

Assessment:
**REPAIR / EVOLVE THROUGH VERSIONED MIGRATION — DO NOT AD-HOC ALTER PRODUCTION**

## 5. Commercial / Finance Reality

Founder-locked:
EXPECTED → EARNED → INVOICED → COLLECTED

Current:
- Supabase finance schema is extensive.
- Live canonical finance rows are still empty in Supabase.
- Data Hub contains actual Commission records and operational finance evidence.
- Commercial rules in live sheets contain legacy/client-specific logic and recent founder corrections.

Assessment:
**RECONCILE FIRST**

No rate, commission, or collection logic should be hard-coded into new application code until current client/deal rules are normalized into configurable commercial contracts.

## 6. Security Reality

Current Supabase advisor findings on 2026-10-09:
- `ops.cashbook_links`: RLS enabled but no policies.
- `public.list_candidates()`: SECURITY DEFINER executable by anon.
- `public.list_cashbook()`: SECURITY DEFINER executable by anon.
- Multiple SECURITY DEFINER functions executable by authenticated users.
- Leaked-password protection disabled.

Assessment:
**P0/P1 SECURITY REPAIR REQUIRED BEFORE BROADENING ACCESS**

No new customer/partner/candidate portal should be expanded before security boundaries and function grants are reviewed.

## 7. Architecture Reality

Strong existing assets:
- PostgreSQL/Supabase schemas for core, ops, finance, docs, analytics, authz.
- Event kernel / idempotency / trace infrastructure.
- Raw ingestion.
- Evidence and DQ concepts.
- Security / observability / backup structures.
- Shadow import.
- Founder WebApp.
- GitHub migration history.
- MYC-* namespace already present.

Main concern:
**Infrastructure is ahead of migrated business truth.**

There is substantial architecture for portal, analytics, scale, workers, backup and observability while canonical business masters in Supabase remain empty.

Classification:
- Event / ingestion kernel: KEEP
- Raw provenance: KEEP
- Security / audit concepts: KEEP, HARDEN
- Shadow import: KEEP as migration aid, not business master
- Current empty core schema: EVOLVE
- Spreadsheet as long-term backend: DEPRECATE after controlled cutover
- Customer SaaS expansion: DEFER
- Marketplace: DEFER
- Payroll/Staffing: DO NOT BUILD
- Candidate-paid service logic: DEPRECATE

## 8. P0 Reality Conflicts

### P0-01 — Business Master Split
Data Hub has real business truth; Supabase core business tables are empty.

Required:
Define and execute controlled migration, not dual-write ambiguity.

### P0-02 — Official Read Runtime Missing
All eight defined official-read endpoints currently return 404 on current production alias.

Required:
Re-establish official read contract or deliberately replace it under architecture control.

### P0-03 — Locked Domain Model Gap
Person, Demand, Application are not represented as canonical masters.

Required:
Architecture decision and versioned domain migration blueprint.

### P0-04 — Security Definer Exposure
Public/authenticated execution exists for privileged SECURITY DEFINER functions.

Required:
Review intended callers; revoke unnecessary grants or redesign under least privilege.

### P0-05 — Legacy Commercial Logic
Live Sheets include old and revised partner/client rules.

Required:
Freeze facts, distinguish historical vs current effective rules, and encode only after Founder Strategy reconciliation.

## 9. Decision Classification

### KEEP
- MYC-* ID namespace
- Supabase project
- Raw/event ingestion
- GitHub repository
- Vercel project
- Google Drive controlled document/evidence role
- Security-by-design principle
- Human approvals
- Event history
- Evidence / DQ / audit concepts

### REPAIR
- Official read layer
- Security grants / exposed SECURITY DEFINER functions
- Runtime/source-code parity for Edge Functions
- Source-of-truth documentation
- worker/readiness truth
- DQ/reconciliation loop

### MIGRATE
- Candidate
- Client
- Job
- Partner
- Placement
- Finance / Commission
- Evidence links
- current statuses
from live Data Hub into canonical PostgreSQL models after schema reconciliation.

### BUILD / EVOLVE
- Person
- Demand
- Application
- configurable commercial agreement/rate/milestone model
- MYC OS work inbox / founder operating surfaces
- controlled AI role/task/approval integration

### DEPRECATE
- Work Connect current identity
- WC-* IDs
- Candidate-paid MYC services
- spreadsheet-centric long-term architecture
- dashboard-first architecture
- disconnected AI chat-room agents
- uncontrolled Foundry access to MYC raw data

### DO NOT BUILD
- Staffing employer / EOR payroll float
- own payroll engine as business model
- candidate personal-data sales
- marketplace before density
- large external SaaS before internal OS reliability

## 10. Engineering Gate Result

### Overall
**PARTIAL / NOT READY FOR CANONICAL CUTOVER**

### Passed
- Live Supabase project exists and is healthy.
- Raw/event ingestion contains real production data.
- MYC-* IDs are in active operational use.
- Data Hub contains current business records.
- GitHub and Vercel infrastructure exist.
- Founder WebApp has production deployments.
- Audit/evidence/security concepts already exist.

### Failed / Open
- Supabase core business truth is not populated.
- Official read endpoints are not present on current production runtime.
- Locked MYC V2 domain model is incomplete.
- Security advisor has actionable warnings.
- Commercial/rate/commission history needs canonical reconciliation.
- Current runtime/source-code parity is incomplete.

## 11. Required Next Gate
Do not start uncontrolled implementation.

Next:
1. Founder Strategy Handoff Review
2. Canonical Data/Domain Truth Map
3. Current-vs-Target Migration Contract
4. Security Remediation Plan
5. Official Read Contract Decision
6. MYC Canonical Package
7. Architecture + Migration Blueprint
8. 90-Day Execution Roadmap
9. Controlled Astra/Codex/Claude implementation

## 12. Final Audit Conclusion
The current MYC system is not a failed system. It has valuable infrastructure and real operating data.

The core issue is misalignment between:
- where the real business truth currently lives,
- how much infrastructure has already been built,
- and the new Founder-locked operating/domain model.

The correct move is not restart and not mass rewrite.

The correct move is:
**preserve → reconcile → simplify → migrate → close loop → automate → scale.**
