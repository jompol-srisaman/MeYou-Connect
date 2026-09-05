# MEYOU CONNECT — AI TEAM OPERATING LOOP V1

> Status: DRAFT FOR FOUNDER REVIEW
> Purpose: Define how ChatGPT, Claude Code, Codex and automatic gates collaborate with minimal human intervention.

## 1. Core Principle

GitHub is the shared execution bus and audit trail.

Do not use chat copy/paste as the primary handoff method.
Every material implementation task must exist as a GitHub Issue and every code change must arrive through a Pull Request.

## 2. Roles

### A. ChatGPT — AI Engineering Orchestrator / Founder Interface
Owns:
- Read Founder intent and canonical project sources.
- Convert goals into Epics, Issues, acceptance criteria and dependencies.
- Decide work split between Claude Code and Codex.
- Check architecture, ownership, source-of-truth and Human Gate boundaries before work starts.
- Inspect GitHub, Vercel, Supabase, Drive and CI evidence.
- Review final outcome against acceptance criteria.
- Escalate only true Founder Decisions / Human Gates.

Must not:
- Invent a new Source of Truth, Data Contract, ID lifecycle or security model without approved architecture review.
- Bypass Data Manager ownership.
- Present TEST/shadow data as operational truth.

### B. Claude Code — Integration / Backend / Architecture Implementer
Primary ownership:
- `lib/data/**`
- `app/api/**`
- backend adapters
- API integrations
- authentication/session integration
- server-side data access
- integration tests
- architecture-sensitive implementation docs

Responsibilities:
- Reuse existing canonical APIs/contracts before creating anything new.
- Preserve source authority and privacy/security boundaries.
- Open PR with implementation evidence and tests.

Default reviewer: Codex + ChatGPT Orchestrator.

### C. Codex — Frontend / Product Engineering / Test Implementer
Primary ownership:
- `app/**` presentation routes
- `components/**`
- UI state and error/readiness states
- frontend tests
- accessibility and responsive behavior
- CI/build fixes tied to frontend scope

Responsibilities:
- Build against documented interfaces; do not invent backend truth.
- Keep NOT_READY/BLOCKED behavior explicit.
- Open PR with screenshots/build/test evidence when applicable.

Default reviewer: Claude Code + ChatGPT Orchestrator.

### D. DATA & AI SYSTEM MANAGER V2 — Data Layer Owner
Owns:
- Raw → Parse → Validate → Dedupe → Route → Master promotion
- canonical entity/data contracts
- Data Hub / Supabase master synchronization
- DQ resolution
- data-source readiness

Engineering AIs may consume the approved contract but must not create a parallel promotion path.

## 3. Work State Machine

`FOUNDER_INTENT → ORCHESTRATED → READY_FOR_IMPLEMENTATION → IN_PROGRESS → IMPLEMENTED → CROSS_REVIEW → CI_VERIFIED → ORCHESTRATOR_ACCEPTED → HUMAN_GATE_IF_REQUIRED → MERGE_READY → DEPLOYED → VERIFIED → CLOSED`

Blocked states:
- `BLOCKED_DATA`
- `BLOCKED_ARCHITECTURE`
- `BLOCKED_SECURITY`
- `BLOCKED_DEPENDENCY`
- `BLOCKED_FOUNDER_DECISION`

## 4. Mandatory Issue Contract

Every implementation Issue must contain:
- Goal
- Owner AI
- Reviewer AI
- Canonical sources / interfaces
- Allowed paths
- Forbidden paths / ownership boundaries
- Dependencies
- Acceptance criteria
- Test requirements
- Human Gate: YES/NO and exact trigger
- Handoff destination

No AI should start work when Owner, acceptance criteria or data authority is ambiguous.

## 5. Handoff Protocol

Implementer finishes by posting to its Issue/PR:

### RESULT
- What changed
- Files changed
- Tests run and result
- Preview/deployment evidence

### CONTRACT CHECK
- Source of Truth preserved: PASS/FAIL
- No direct protected-master bypass: PASS/FAIL
- No secrets committed: PASS/FAIL
- Existing API/architecture reused: PASS/FAIL

### OPEN RISKS
- unresolved risks only

### HANDOFF
- Reviewer AI
- exact review request
- blocking dependencies

The next AI reads GitHub evidence directly. Founder does not relay messages manually.

## 6. Cross-Review Rules

Claude Code must review Codex changes for:
- API/data contract correctness
- auth/privacy boundary
- server/client separation
- architecture drift

Codex must review Claude Code changes for:
- consumer contract usability
- edge/error/loading states
- frontend integration risk
- testability

ChatGPT Orchestrator performs final acceptance review for:
- scope
- acceptance criteria
- cross-system effects
- canonical architecture
- Human Gate decision

Implementer cannot be the sole reviewer of its own work.

## 7. Automatic Gates

The repository should automatically run at minimum:
- typecheck
- build
- unit/integration tests where present
- lint when configured
- secret scan when available
- changed-file / protected-path checks where practical

A PR cannot be considered merge-ready unless required checks pass.

## 8. Founder / Human Gate

Founder is required only when the change does one of these:
1. Real payment / financial approval
2. Contract acceptance / legally binding action
3. Production activation or irreversible cutover
4. New/changed business policy
5. New/changed canonical Source of Truth
6. New Master Entity / ID format / lifecycle / Data Contract
7. Material security/privacy boundary change
8. External portal/public exposure
9. Destructive deletion or irreversible migration
10. Out-of-authority price/discount decision

Everything else should proceed through AI review + automated checks without Founder intervention.

## 9. Escalation Format to Founder

Founder should receive only:
- Decision required
- Why it is blocked
- 2–3 options
- Recommended option
- Impact if approved
- Impact if not approved

No raw logs unless requested.

## 10. Current P0 Routing

### P0.1 Operational Read Adapter
Owner: DATA & AI SYSTEM MANAGER V2 for data contract; Claude Code for consuming adapter after contract is approved.
Reviewer: Codex + ChatGPT.

### P0.2 Internal Auth
Owner: Claude Code.
Reviewer: Codex + ChatGPT.
Human Gate only if security/auth policy boundary changes.

### P0.3 Founder Dashboard Live Data
Owner: Codex for UI; Claude Code for integration layer.
Reviewer: reciprocal + ChatGPT.

### P0.4 Job / Client / Partner Workspaces
Owner: split by path: Claude integration, Codex UI.
Reviewer: reciprocal + ChatGPT.

### P0.5 Candidate Workspace
Blocked until canonical resolution/contract for `MYC-DQ-000011`.
No parallel candidate promotion implementation is allowed.

## 11. Founder Minimal-Work Mode

Default operating behavior:
1. Founder states goal in normal Thai.
2. ChatGPT creates/updates GitHub work items and assigns AI ownership logically.
3. Implementer executes in its lane.
4. Other AI cross-reviews.
5. CI verifies automatically.
6. ChatGPT checks final evidence.
7. Founder is contacted only if a Human Gate triggers.

Target Founder workload: approve decisions, not coordinate implementation.
