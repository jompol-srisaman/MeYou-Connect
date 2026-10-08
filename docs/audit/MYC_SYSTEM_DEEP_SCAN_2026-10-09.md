# MYC — SYSTEM DEEP SCAN
Date: 2026-10-09
Owner: Maple — MYC Engineering Control Lead
Scope: GitHub + Supabase + Vercel + Google Data Hub / Drive
Mode: READ-ONLY AUDIT
Production Mutation: NONE

---

## 0. EXECUTIVE VERDICT

MYC is **not a dead or failed technical system**.

It has several valuable, live components:
- LINE raw/event capture
- Raw → Data Hub synchronization
- shadow import
- Google Sheets status writer
- Founder WebApp
- Supabase security/audit/event foundations
- an implemented Official Read V1 contract in an unmerged branch

The core problem is not absence of technology.

The core problem is **technical fragmentation**:

1. live business truth is in Google Data Hub / Drive;
2. live raw/event truth is in Supabase;
3. current Vercel Production runs an app whose source is not represented on current `main`;
4. Official Read V1 exists in an unmerged stacked branch;
5. deployed Supabase Edge Function source is not stored on current `main`;
6. many TEST-era infrastructure layers exist while canonical business tables remain empty.

The correct response is not restart.

The correct response is:

**Recover → Reconcile → Consolidate → Canonicalize → Migrate → Cut Over**

---

## 1. SOURCE CONTROL REALITY

### 1.1 Current `main`

Current recursive tree on `main` contains:
- 38 docs paths
- 160 migration files
- 1 script
- no `web/`
- no `supabase/functions/`
- no Next.js application source at repository root

Current root:
- `.gitignore`
- `README.md`
- `docs/`
- `scripts/`
- `supabase/`

### 1.2 README Drift

Current README says the repository contains:
- `supabase/functions/`
- `web/`
- `docs/ROADMAP.md`
- `docs/AI_HANDOFF.md`
- `docs/product/FOUNDER_DASHBOARD_SPEC.md`

Those paths are not present on current `main`.

Classification:
**DOCUMENTATION / SOURCE-CONTROL DRIFT**

---

## 2. BRANCH / PR FRAGMENTATION

Important implementation remains in open, unmerged stacked branches.

Observed open PR chain:

- PR #3: `feat/p0-internal-ops-shell` → `develop`
- PR #20: `feat/pwa-v0-1-founder-usable` → `feat/p0-internal-ops-shell`
- PR #22: `data/p0-official-read-contract` → `develop`
- PR #24: `feat/p0-official-read-bind` → `feat/pwa-v0-1-founder-usable`
- PR #26: `data/unified-intake-readiness` → `data/p0-official-read-contract`

All remain open and unmerged.

Current audit PR:
- PR #27: `audit/founder-strategy-reality-2026-10-09` → `main`

### Risk

The repository has a real implementation lineage that never became one canonical branch.

This creates:
- unclear ownership of final source;
- runtime/source mismatch;
- difficulty reproducing deployments;
- duplicated architecture paths;
- risk that a future engineer builds again what already exists.

Classification:
**P0 ENGINEERING GOVERNANCE GAP**

---

## 3. OFFICIAL READ V1 — RECOVERABLE ASSET

The Official Read layer is not missing from history.

It exists in branch:
`feat/p0-official-read-bind`

Key source:
- `app/api/v1/read/[...segments]/route.ts`
- `lib/data/official-read.ts`
- `lib/data/source-clients.ts`
- `lib/platform/contracts.ts`
- `lib/platform/module-registry.ts`

Implemented route groups:
- `/api/v1/read/inbox/line`
- `/api/v1/read/system/health`
- `/api/v1/read/jobs`
- `/api/v1/read/clients`
- `/api/v1/read/partners`
- `/api/v1/read/candidates`
- `/api/v1/read/dq`
- `/api/v1/read/founder/today`

It also contains detail routing where supported.

### Valuable design patterns

- stable read envelope
- `contract_version`
- `interface_key`
- `source_authority`
- `source_ref`
- freshness metadata
- readiness states
- warnings / reason codes
- sensitive-field redaction
- Candidate completeness guard
- Data Hub server-side read adapter
- Supabase technical read adapter
- safe-write boundary:
  `Command → Validate → Permission → Event → Master Effect → Audit`

Historical PR #24 states this implementation passed:
- typecheck
- tests
- build
- built-server endpoint smoke

It was a Preview implementation, not Production activation.

### Current status

Current Production returns HTTP 404 for these routes because this Next.js read layer is not what the current Production alias is serving.

Classification:
**SALVAGE / REFIT — DO NOT REBUILD FROM ZERO**

---

## 4. CURRENT VERCEL PRODUCTION REALITY

Project:
`me-you-connect`

Current Production aliases include:
- `me-you-connect-jompol-srisamans-projects.vercel.app`
- `me-you-connect-five.vercel.app`

Current Production root:
- HTTP 200
- Founder-only static WebApp
- Dashboard
- Jobs
- Candidates
- Finance
- Partners
- AI Assistant

Current app reads through Supabase RPCs such as:
- `get_founder_daily`
- `list_jobs`
- `list_candidates`
- `list_cashbook`
- `list_partners_payable`

Current app also allows controlled operational writes:
- status change via `web_submit_status_change`
- cashbook linking via `link_cashbook_txn`

Status changes are eventually written back to Google Sheets through the transition pipeline.

### Critical finding

The current Production deployment is READY at Vercel level but its current source is not represented as a reproducible canonical application tree on `main`.

The latest Production deployment metadata used by the active aliases does not identify a Git commit.

Classification:
**P0 RUNTIME SOURCE TRACEABILITY GAP**

---

## 5. TWO READ ARCHITECTURES CURRENTLY EXIST

### Architecture A — Current Production tactical path

Browser
→ Supabase RPC
→ `dash.*` projections / shadow-imported Data Hub data

Benefits:
- currently operational
- Founder UI works
- Finance/cashbook linking exists
- status workflow exists

Risks:
- tight coupling to tactical dashboard RPC layer
- not the same Official Read V1 contract
- source not canonicalized in `main`

### Architecture B — Official Read V1 branch

Browser / Consumer
→ `/api/v1/read/**`
→ governed server adapter
→ current authoritative source
→ explicit source/readiness/freshness envelope

Benefits:
- cleaner contract boundary
- can survive source migration from Sheets to Postgres
- consumers do not need to know the underlying source
- supports transition without lying about authority

Current issue:
- unmerged
- not current Production runtime

### Recommendation

Do not run both indefinitely.

Canonical Package should preserve the **Official Read façade concept** and absorb useful current Production capabilities behind that architecture.

Classification:
**CONSOLIDATE**

---

## 6. SUPABASE LIVE RUNTIME

Project:
`pgjmxdeafzogzsyawejs`

Status:
`ACTIVE_HEALTHY`

### Live raw / event state

- `ops.raw_inputs` = 4,463
- `ops.events` = 4,626
- `ops.raw_datahub_sync_ledger` = 4,463

Raw sync runtime:
- unstaged = 0
- pending = 0
- in-flight = 0
- retry = 0
- synced = 4,463
- DQ = 0

### Worker reality

HEALTHY:
- `candidate_intake`
- `raw_sync`

Most other registered workers:
- `NOT_STARTED`

Examples:
- placement
- commission
- finance
- reconciliation
- follow-up
- job
- consent
- attribution
- DQ review
- portal workers
- notification
- retry router

### Interpretation

The runtime has a working ingestion spine.

It does **not** yet have a fully automated MYC operating organization.

Classification:
- ingestion spine = KEEP
- worker registry = KEEP AS INVENTORY
- unimplemented worker claims = DO NOT PRESENT AS CAPABILITY

---

## 7. EDGE FUNCTION SOURCE PARITY

Active Supabase Edge Functions observed:

1. `line-official-webhook` v9
2. `line-group-bot-webhook` v9
3. `line-backup-export` v8
4. `raw-datahub-sync` v8
5. `datahub-shadow-import` v3
6. `sheet-status-writer` v2
7. `gpt-actions` v1
8. `ai-assistant` v1

Current `main` contains no `supabase/functions/` source.

However, deployed function source can currently be retrieved from Supabase.

### Meaning

This is a serious but recoverable condition.

The deployed runtime is ahead of GitHub Source of Truth.

### Recommendation

Before modifying these functions:
1. export exact deployed source;
2. record deployment slug/version/hash;
3. place source under version control;
4. compare against historical branch/source;
5. only then modify.

Classification:
**P0 SOURCE RECOVERY REQUIRED**

---

## 8. EDGE RUNTIME HEALTH

Observed recent function-edge responses include successful HTTP 200 traffic for:

- `sheet-status-writer`
- `datahub-shadow-import`
- `raw-datahub-sync`
- `line-group-bot-webhook`

Vercel grouped runtime errors for the last 7 days:
- no runtime errors returned for current project.

### Conclusion

The live system is operating.

Do not treat it as disposable.

---

## 9. SECURITY DEEP SCAN

Current Supabase Advisor reports:

- `ops.cashbook_links`: RLS enabled but no policies
- public `list_candidates()`: SECURITY DEFINER executable by `anon`
- public `list_cashbook()`: SECURITY DEFINER executable by `anon`
- several privileged functions executable by `authenticated`
- leaked-password protection disabled

### Important nuance

Detailed function inspection shows:

`public.list_candidates()`
→ calls `dash.list_candidates()`

`public.list_cashbook()`
→ calls `dash.list_cashbook()`

Those inner functions filter:
`dash.current_role() = 'founder'`

and `dash.current_role()` resolves by `auth.uid()`.

Therefore:

**The scan did not prove an anonymous data leak.**

But the current EXECUTE grants create unnecessary public callable surface and violate least-privilege hygiene unless explicitly required.

Classification:
**P1 SECURITY HARDENING / VERIFY BEFORE PORTAL EXPANSION**

Historical docs that reported “0 lints” were true for their historical snapshot but are no longer current evidence.

---

## 10. DATA / MASTER REALITY

### Current Business Master
Google Data Hub + Drive evidence.

### Current Target
PostgreSQL / Supabase.

### Current canonical Supabase core
Still empty for:
- Candidate
- Client
- Job
- Partner
- Placement
- Revenue
- Commission

### Current transition/shadow scale
- shadow import rows: 684,506
- shadow import sessions: 2,757

### Interpretation

The system has repeatedly imported and projected business data, but has not performed canonical business-master cutover.

This is not a data absence problem.

It is a **canonical ownership transition problem**.

---

## 11. DQ REALITY

Supabase technical DQ currently has one open HIGH item:
- `MYC-DQ-000013`
- entity `MYC-RAW-000929`
- `RAW_ID_PROVENANCE_COLLISION`

Google Data Hub maintains a broader business DQ queue with later IDs.

### Implication

There are currently multiple DQ representations.

Canonical Package must define:
- one DQ ownership model;
- technical vs business DQ categories;
- whether they share one canonical record or governed projections.

Do not silently collapse them during migration.

---

## 12. STRATEGY CONFLICT FOUND IN OLD APP PLAN

The old module registry includes:

- Finance
- Payroll
- Accounting
- AI Matching
- Partner Portal
- Candidate Portal

The current Founder Strategy explicitly locks:
- no staffing-employer model
- no payroll float
- Payroll is not MYC OS V1 priority

### Decision

`Payroll` as workforce payroll/staffing functionality must be:
**DEPRECATED / REMOVED FROM CURRENT PRODUCT ROADMAP**

A future internal MYC employee-payroll function, if ever needed, would be a separate scope and must not be confused with managing client workforce payroll.

---

## 13. AI ASSISTANT REALITY

Current deployed `ai-assistant`:
- Founder-authenticated
- uses live MYC tools
- can list Jobs/Candidates/Cashbook/Partners
- can submit status changes
- can link cashbook records
- has remember/forget notes
- currently calls Google Gemini
- is implemented as an in-app assistant

### Assessment

Useful patterns to salvage:
- tool-based live reads
- explicit action confirmation
- structured tool calls
- role verification
- auditable write paths

Do not treat the current single assistant as the final AI Organization.

Founder Strategy requires:

`Founder → Maple → Organization`

with:
- Roles
- Permissions
- Triggers
- Task Queue
- Output Contracts
- KPI
- Escalation
- Approval gates

Classification:
**SALVAGE TOOLING / EVOLVE ORCHESTRATION MODEL**

---

## 14. RECOVERED ASSET INVENTORY

### KEEP

- MYC-* namespace
- Supabase project
- raw/event kernel
- LINE capture
- Raw → Data Hub sync
- evidence concepts
- DQ concepts
- event history
- AuthZ concepts
- audit / observability foundations
- shadow migration tooling
- Google Drive evidence/document role
- Vercel project
- Founder WebApp user-learning
- controlled status-write pattern

### SALVAGE / REFIT

- Official Read V1 contract
- Next.js Founder shell
- server-side source adapters
- Founder dashboard projections
- cashbook linking
- sheet-status-writer as transitional writer
- AI Assistant tool definitions
- portal access/security patterns
- migration/reconciliation utilities

### REPAIR / CONSOLIDATE

- branch / PR lineage
- deployed function source parity
- current Production source traceability
- README / docs integrity
- Official Read vs dash RPC architecture
- business vs technical DQ
- security grants
- worker capability truth
- commercial rule versioning
- source-of-truth documentation

### MIGRATE

- Candidate
- Client
- Job
- Partner
- Placement
- Commercial data
- Commission
- Evidence links
- current operational statuses

### BUILD / EVOLVE

- Person
- Opportunity
- Demand
- Application
- Commercial Agreement / Rule Version
- Work Inbox
- Maple orchestration layer
- AI Workforce task/approval model

### DEPRECATE

- Work Connect / WC-* current identity
- spreadsheet as long-term master
- disconnected AI-agent chat-room model
- payroll/staffing module
- direct dashboard projection as long-term public integration contract
- legacy Part/Wave documents as current strategy authority

### DO NOT BUILD NOW

- external Candidate Portal
- external Partner Portal
- Employer SaaS
- marketplace
- workforce payroll
- staffing employer / EOR
- candidate-paid services
- large new analytics warehouse

---

## 15. CONSOLIDATION REQUIREMENT BEFORE IMPLEMENTATION

A **Codebase Recovery & Consolidation** workstream is required before major new MYC V2 coding.

This is not a restart.

Required sequence:

1. inventory all live deployed artifacts;
2. export deployed Edge Function source;
3. identify current Vercel Production source;
4. map open PR/branch lineage;
5. preserve useful Official Read / PWA assets;
6. identify obsolete/conflicting code;
7. create one controlled integration baseline;
8. run build/test/security checks;
9. only then begin Canonical V2 implementation.

No old branch should be deleted until recovery is complete.

---

## 16. DEEP SCAN GATE RESULT

### System Existence
**PASS**

The real system is alive and contains valuable assets.

### Business Truth Integrity
**PARTIAL**

Current truth remains split between operational Data Hub and technical Supabase.

### Source-Control Integrity
**FAIL / P0**

Runtime code and important app work are not fully represented on current `main`.

### Runtime Health
**PASS WITH CAVEATS**

Critical ingestion/sync paths are actively succeeding.

### Canonical Domain Readiness
**PARTIAL**

Current core does not yet satisfy locked Person/Demand/Application separation.

### Security Readiness
**PARTIAL**

No proven anonymous business-data leak in this scan, but current least-privilege/security-advisor findings require remediation.

### Production Cutover
**NOT READY**

### Canonical Package
**READY TO AUTHOR**

The scan provides sufficient reality evidence to author the Canonical Package without inventing the current state.

---

## 17. FINAL SYSTEM DIAGNOSIS

MYC's current technical problem is best described as:

**A functioning but fragmented transition architecture.**

It contains:
- real production ingestion,
- real operational data,
- real business UI,
- real migration tooling,
- real security/control foundations,

but these have not been consolidated into one reproducible, canonical engineering baseline.

Therefore the next phase must not be “build more features.”

It must be:

**Canonicalize the business and architecture first, then consolidate the code and migrate the truth under controlled gates.**
