# MYC — FOUNDER STRATEGY HANDOFF REVIEW
Date: 2026-10-09
Company: MeYou Connect — MYC
Portfolio: Jompol Enterprises
Prepared by: Maple — MYC Engineering Control Lead
Status: FOUNDER STRATEGY HANDOFF REVIEW
Input: Founder Strategy Consolidation + Live Engineer Reality Audit
Production Changes: NONE

---

## 0. REVIEW OUTCOME

**ENGINEERING ACCEPTS THE FOUNDER STRATEGY AS THE CURRENT BUSINESS AUTHORITY.**

The strategy is internally coherent enough to proceed to the **MYC Canonical Package**, provided that the Canonical Package treats current live facts as migration evidence rather than silently rewriting them.

No business-model reinterpretation is required.

No restart is required.

No mass rewrite is required.

No immediate Production cutover is authorized.

Recommended operating principle:

**Preserve → Reconcile → Simplify → Migrate → Close Loop → Automate → Scale**

---

## 1. AUTHORITY ORDER

When sources conflict, use this order:

1. Founder Strategy Consolidation — current business direction / policy
2. Verified current business facts and evidence
3. Current operational Master / live source-of-truth evidence
4. Controlled Engineering documentation
5. Historical implementation documentation
6. AI inference — never a business fact by itself

Important:

A live legacy behavior does not override Founder Strategy.

A Founder Strategy direction does not erase historical business facts.

Historical facts must be preserved with effective dates / source / evidence.

---

## 2. CURRENT → TARGET TRUTH MAP

| Domain | Current Reality | Target State | Transition |
|---|---|---|---|
| Business Operational Master | Google Data Hub + Drive evidence | PostgreSQL / Supabase | Controlled migration |
| Raw Channel Provenance | Supabase ops.raw_inputs / ops.events | Supabase | Keep + harden |
| Candidate | Data Hub has live records; Supabase core empty | Canonical Candidate Profile linked to Person | Migrate + evolve |
| Person | Not canonical | Canonical Person identity | Build |
| Client | Data Hub live; Supabase core empty | Canonical Client CRM | Migrate |
| Opportunity | Not canonical | Canonical B2B opportunity | Build |
| Demand | Review queue exists, no canonical master | Canonical Demand separate from Job | Build |
| Job | Data Hub live; Supabase core empty | Canonical Job linked to Demand | Migrate + evolve |
| Application | No canonical master | Candidate↔Job Application journey | Build |
| Placement | Data Hub now has live rows; Supabase core empty | Canonical successful-start / placement record | Migrate |
| Follow-up | Existing structures but not authoritative in Supabase | Controlled follow-up / retention workflow | Migrate / evolve |
| Revenue | Live business evidence in Data Hub / cashbook; Supabase canonical empty | Configurable commercial ledger | Reconcile + migrate |
| Commission | Live rows/rules in Data Hub; Supabase canonical empty | Evidence-backed configurable payout ledger | Reconcile + migrate |
| Evidence | Drive + Data Hub + Supabase metadata concepts | Controlled evidence layer | Reconcile |
| Data Quality | Data Hub queue + Supabase DQ structures | Single controlled DQ workflow | Reconcile |
| Current State | Spread across business masters | Structured current projections | Build on event history |
| Event History | Supabase event kernel exists | Canonical immutable/auditable history | Keep |
| Founder Interface | Founder WebApp exists | MYC OS Founder Home + Work Inbox | Evolve |
| AI Interaction | Several agent/chat/runtime experiments | Maple-led AI workforce with roles/permissions/tasks | Consolidate |
| Documents | Google Drive | Controlled documents/evidence | Keep |
| Engineering | GitHub | GitHub | Keep |
| Channels | LINE/Facebook/TikTok/etc. | Channels, not databases | Keep boundary |

---

## 3. DOMAIN MODEL HANDOFF

Founder-locked distinctions are accepted as canonical architecture constraints:

### 3.1 Person ≠ Candidate Profile

Target:

`Person`
→ may have one or more MYC candidate/recruitment journeys over time.

Reason:
A human can return, change preferences, re-apply, or be sourced again without becoming a second person.

### 3.2 Demand ≠ Job

Target:

`Client → Demand → Job(s)`

Reason:
One commercial workforce requirement may create multiple jobs, locations, shifts, positions, cohorts, or campaigns.

### 3.3 Candidate ≠ Application

Target:

`Candidate Profile → Application(s) → Job`

Reason:
One candidate can be considered/submitted for multiple jobs.

### 3.4 Application ≠ Placement

Target:

`Application → outcome / Start → Placement`

Placement should represent successful placement/start according to business definition, not every submission.

### 3.5 Current State ≠ Event History

Target:
- event/history layer preserves what happened;
- current projections answer what is true now.

This should reuse the existing event infrastructure rather than create a second history engine.

---

## 4. CANONICAL BUSINESS LOOP HANDOFF

The Founder Strategy loop is accepted as the operating backbone:

Prospect
→ Client Discovery
→ Demand
→ Commercial Agreement
→ Job Order
→ Sourcing Plan
→ Candidate Acquisition
→ Intake
→ Screening
→ Matching
→ Submission
→ Application / Interview / Training
→ Start
→ Milestone Verification
→ Earned Revenue
→ Invoice
→ Collection
→ Partner Payout
→ Retention
→ Client Report
→ Repeat / Expansion

Engineering implication:

MYC OS must be designed around closing this loop.

A dashboard is a projection of the loop, not the product architecture.

---

## 5. COMMERCIAL TRUTH HANDOFF

Locked state machine:

`EXPECTED → EARNED → INVOICED → COLLECTED`

Engineering constraints:

- `COLLECTED` requires real collection evidence.
- Client/deal/milestone rates must be configurable.
- Rate changes must have effective dates.
- Historical rates must remain reproducible.
- Partner payout rules must be separate from client revenue rules.
- No rate should be inferred from prose and silently promoted to current commercial truth.
- Unknown remains Unknown.

Recommended target abstraction:

`Commercial Agreement`
→ `Commercial Rule Version`
→ `Milestone Rule`
→ `Revenue Event`
→ `Invoice / AR`
→ `Collection`

Partner side:

`Partner Agreement / Compensation Rule Version`
→ `Commission Eligibility`
→ `Commission State`
→ Human-approved payment execution

---

## 6. MIGRATION CONSTRAINTS

### MC-01 — No Big-Bang Rewrite

The system already contains valuable production ingestion, evidence, IDs, documents, history and business data.

Migration must be incremental and evidence-backed.

### MC-02 — No Dual-Write as Default End State

During transition, shadow/import/read-parity is acceptable.

Do not create permanent ambiguity where Sheets and Supabase can both independently mutate the same canonical business fact.

### MC-03 — Stable MYC IDs

Existing valid `MYC-*` business IDs must be preserved where possible.

Do not re-key existing business records for aesthetic schema reasons.

Technical UUIDs may be added underneath.

### MC-04 — Historical Facts Are Immutable Evidence

Old rates, old partner structures, old job terms and old candidate states may be superseded but must not be deleted merely because strategy changed.

Use:
- valid_from
- valid_to
- effective_at
- source
- evidence
- actor

where appropriate.

### MC-05 — Unknown Must Survive Migration

Do not turn missing source data into defaults.

### MC-06 — Evidence Before State Promotion

Critical transitions such as Start, Milestone, Earned, Collected, Paid, consent or sensitive approvals require source/evidence according to policy.

### MC-07 — Current Business Must Keep Running

Migration cannot freeze MYC revenue operations for a long engineering rewrite.

The live Data Hub remains the operational business master until cutover gates pass.

### MC-08 — Legal Validation Is a Gate, Not a Schema Guess

Recruitment-license, partner activity, advertising, PDPA and contract requirements must be validated externally before scale-sensitive automation.

### MC-09 — Foundry Must Not Become a Hard Blocker

MYC may consume generic Foundry runtime contracts when useful, but MYC V2 delivery must not wait for a perfect Foundry.

### MC-10 — Security Before Wider External Access

Do not expand Candidate/Partner/Client portals while current privileged-function grants and access boundaries remain unresolved.

---

## 7. CONFLICT REGISTER

### CR-001 — Current Source of Truth vs Target Source of Truth

**Current:** Google Sheets/Drive business master.

**Target:** PostgreSQL/Supabase.

**Classification:** Migration gap, not strategy contradiction.

**Action:** Controlled cutover program.

---

### CR-002 — Empty Canonical Core vs Live Business

Supabase:
- candidates = 0
- clients = 0
- jobs = 0
- partners = 0
- placements = 0
- revenue = 0
- commissions = 0

Meanwhile Data Hub contains live business entities.

**Classification:** P0 migration/reconciliation gap.

---

### CR-003 — Domain Model Behind Founder Strategy

Current core model does not have canonical:
- Person
- Demand
- Application

**Classification:** Architecture evolution required.

**Action:** Versioned schema change during Canonical Package / migration blueprint.

---

### CR-004 — Official Read Contract Missing on Current Production Runtime

Current checked routes return 404:
- /api/v1/read/inbox/line
- /api/v1/read/system/health
- /api/v1/read/jobs
- /api/v1/read/clients
- /api/v1/read/partners
- /api/v1/read/candidates
- /api/v1/read/dq
- /api/v1/read/founder/today

**Classification:** P0 runtime/contract gap.

**Recommended decision:** preserve a stable official-read façade, but redefine its backing sources under MYC V2 rather than binding consumers directly to Sheets or raw DB tables.

---

### CR-005 — Security Documentation Drift

Historical Part 7 documentation reports Supabase Security Advisor 0 lints at that earlier snapshot.

Current live advisor reports:
- RLS-enabled table with no policies for `ops.cashbook_links`
- anon-executable SECURITY DEFINER functions including `public.list_candidates()` and `public.list_cashbook()`
- multiple authenticated-executable SECURITY DEFINER functions
- leaked-password protection disabled

**Classification:** P0/P1 current security drift.

**Action:** current evidence overrides historical clean snapshot.

---

### CR-006 — Runtime / Repository Source Parity

README states some active Edge Function source is not fully in repository.

**Classification:** Engineering governance gap.

**Action:** recover and version runtime source before major modification.

---

### CR-007 — Infrastructure Ahead of Business Migration

Portal, analytics, worker, observability, backup and shadow infrastructure are extensive while canonical business master tables remain empty.

**Classification:** Architecture sequencing imbalance.

**Action:** stop adding broad platform layers until core business loop migration/reliability catches up.

---

### CR-008 — Legacy Commercial Rules

Data Hub contains historical and revised client/partner rules.

Founder Strategy defines current direction but does not erase past effective facts.

**Classification:** Business fact reconciliation required.

**Action:** normalize rules by deal/effective period; do not hard-code prose.

---

### CR-009 — README Documentation References Missing

Current README references some paths such as ROADMAP / AI_HANDOFF / Founder Dashboard spec that are not present at the referenced locations on current `main`.

**Classification:** Documentation integrity defect.

**Action:** repair during Canonical Package documentation consolidation.

---

## 8. LOCK / VALIDATION / OPEN DECISION MATRIX

### LOCKED — Engineering Must Treat as Non-Negotiable

- MeYou Connect / MYC current brand
- `MYC-*` current business IDs
- Candidate = 0 THB to MYC
- No staffing-employer / payroll-float strategy
- B2B as primary payer
- Technology amplifies the business
- MYC remains standalone business first
- Revenue lifecycle EXPECTED→EARNED→INVOICED→COLLECTED
- Data monetization = insight, not raw personal data
- Shared Intelligence ≠ Shared Raw Data
- Human approval boundaries
- MYC owns workforce domain
- Foundry owns generic runtime
- Internal Business OS before external SaaS
- Selective Value Pool Capture
- Supply Engine + Demand Engine
- Small exceptional human team × AI workforce

### VALIDATION-LOCKED — Direction Accepted, Evidence Required

- Thai recruitment-license operating model
- interim pre-license operating model
- partner legal boundaries
- advertising compliance
- PDPA implementation details
- current commercial rule truth
- current partner compensation truth
- unit economics baseline
- revenue truth
- production canonical status truth
- migration readiness

### OPEN FOUNDER DECISIONS — NOT REQUIRED TO DESIGN THE CANONICAL CORE

Can remain open during Canonical Package:
- final legal entity name
- recruitment-license filing date/structure
- standard rate card
- minimum contribution margin
- discount authority
- exact RPO package
- outbound industry/geography priority
- human hiring plan
- founder capital budget
- exact Foundry sequencing

These should become explicit decision records when evidence is available.

---

## 9. ENGINEERING DECISIONS TO CARRY INTO CANONICAL PACKAGE

These are implementation decisions, not business-policy reinterpretations.

### ED-01 — Official Read Façade

**Recommendation: KEEP the concept.**

Consumers should read via stable controlled contracts rather than know whether truth is currently in Sheets, shadow tables or canonical Postgres.

Target:
`consumer → official read contract → authorized projection → current canonical source`

### ED-02 — Migration Mode

**Recommendation: Shadow → Reconcile → Read Parity → Controlled Writer Cutover.**

Avoid permanent dual-write.

### ED-03 — Core Domain Evolution

**Recommendation: evolve current schema rather than discard it.**

Add/normalize:
- Person
- Candidate Profile
- Opportunity
- Demand
- Job
- Application
- Placement
- Commercial Agreement / Rule Version

Reuse:
- Event
- Evidence
- DQ
- AuthZ
- Audit
- Finance foundations where valid

### ED-04 — Foundry Integration

**Recommendation: contract-first, optional-at-runtime during V1 transformation.**

MYC should be able to run without Foundry availability for its core revenue loop.

### ED-05 — AI Workforce

**Recommendation: task/event/permission based, not one chat per agent.**

Maple orchestrates:
Founder → Maple → task/approval/event system → Human/AI role

### ED-06 — Analytics

**Recommendation: downstream of operational truth.**

Do not treat current analytics/dashboard tables as canonical facts if upstream business masters are not canonical.

---

## 10. MYC CANONICAL PACKAGE REQUIRED CONTENT

The next package should contain at minimum:

1. Canonical Business Definition
2. Scope / Non-Scope
3. Domain Model
4. Entity Definitions
5. ID Rules
6. Lifecycle / State Machines
7. Business Loop
8. Commercial Model
9. Partner Model
10. Human / AI Roles
11. Permission / Approval Matrix
12. Data Classification / Provenance
13. Source-of-Truth Matrix
14. Evidence Rules
15. Data Quality Rules
16. Current→Target Mapping
17. Legacy / Deprecation Map
18. Migration Principles
19. Security Principles
20. Legal / Compliance Gates
21. Foundry Boundary
22. API / Official Read-Write Contracts
23. Observability / Audit Requirements
24. Acceptance Definition
25. Open Decision Register

---

## 11. GATE DECISION

### Engineer Reality Audit
**PASS as an audit artifact.**

The audit found material gaps, which is the purpose of the gate.

### Founder Strategy Handoff Review
**PASS WITH CONTROLLED CONSTRAINTS.**

Reason:
- Founder strategy is implementable.
- No fundamental contradiction requires reopening the business strategy.
- Current live architecture contains reusable assets.
- Known conflicts can be handled through migration and architecture controls.
- Open Founder decisions do not block definition of the canonical core.

### Authorized Next Step
**MYC CANONICAL PACKAGE — YES**

### Not Authorized Yet
- Production schema cutover
- mass data migration
- new external portal activation
- autonomous finance execution
- commercial rule rewrite
- security-sensitive production mutations
- uncontrolled Astra/Codex/Claude coding

---

## 12. FINAL HANDOFF STATEMENT

The Founder Strategy is now sufficiently translated into engineering constraints.

The Canonical Package must not describe an imaginary clean startup.

It must define the target system while preserving:
- the real current business,
- the real operational data,
- historical evidence,
- stable MYC identities,
- live revenue operations,
- and safe migration from the current Data Hub.

The next artifact is therefore not a roadmap and not code.

**The next artifact is the MYC Canonical Package.**
