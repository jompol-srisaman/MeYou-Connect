# Part 7 Wave 7B — Purpose-Specific Portal Read Projections + Cross-Scope Isolation

Status: **CLOSED / PASS (TEST READ-PROJECTION FOUNDATION)**  
External Portal Production: **NOT_READY / DISABLED**  
Date: 2026-09-01 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Canonical scope

Wave 7B implements only the Part 7 handoff scope that is supported by current architecture:

- **S4 — Portal API Projection**
- **S6 — Cross-scope / RLS-oriented portal acceptance for implemented read projections**

It does **not** implement or approve:

- S5 Portal Command/Event writes
- S7 MFA / Step-up
- S9 real P1A/P1B pilot rollout
- Production portal access
- Production province activation
- Public marketplace / public Candidate directory

Canonical sources:

- `MEYOU_CONNECT_SCALE_MULTI_PROVINCE_PORTAL_BLUEPRINT_V1.md` — Drive `13tRfZk9l3BMW1qWCKMzhJ3dnEtqpW012`
- `MEYOU_CONNECT_PORTAL_SCALE_CONTROL_MATRIX_V1.xlsx` — Drive `1OC_KY5GJYbnkjZPPGf29OqWwEOmRV-4F`
- `MEYOU_CONNECT_SCALE_ROLLOUT_PLAYBOOK_V1.md` — Drive `17br2k4V2r2U17HaxrJc-yfwZnd_xUSUj`
- `MEYOU_CONNECT_PORTAL_SCALE_SQL_SKELETON_V1.sql` — Drive `1m7f8v3ZHfXs8aqOQJlcF7Fe9iaWsAqG8`
- `MEYOU_CONNECT_CLAUDE_CODEX_IMPLEMENTATION_HANDOFF_PART7_V1.md` — Drive `16sW2ZnaGPCXD4zgp4jCMEZ_Id6MH53R2`

## Implemented

### Client Candidate purpose/access boundary

Created:

- `authz.client_candidate_purpose_access`

Purpose implemented in this wave:

- `RECRUITMENT_SUBMISSION`

Access lifecycle:

- `ACTIVE`
- `REVOKED`
- `EXPIRED`

An access grant is accepted only when:

- organization is an ACTIVE `CLIENT` organization
- organization maps to the real `MYC-B2B-*` client of the placement job
- Candidate ID matches the actual placement Candidate
- access purpose is active and within its validity window
- active database organization membership still exists at read time

This implements the minimum foundation required for purpose-limited Client Candidate visibility. It does not create a broad Candidate directory.

### Purpose-specific read APIs

Implemented authenticated read RPCs:

- `api.portal_candidate_self_profile()`
- `api.portal_partner_referral_status(org_id)`
- `api.portal_partner_commission_status(org_id)`
- `api.portal_client_jobs(org_id)`
- `api.portal_client_candidate_submissions(org_id)`
- `api.portal_client_invoices(org_id)`

All are `SECURITY DEFINER` with an empty `search_path` and explicit internal authorization checks.

`anon` has no EXECUTE permission.

All external portal RPCs also require the external portal master gate plus the relevant Candidate/Partner/Client portal gate. These gates remain OFF outside the controlled TEST acceptance transaction.

### Minimum-data projection boundary

Candidate self projection is linked to `authz.current_candidate_id()` and does not accept a caller-supplied Candidate selector.

Partner referral/status projection is constrained to the Partner business ID mapped from the active organization membership.

Partner commission projection returns commission status/amount/milestones only and omits payment evidence, bank transaction references and unrestricted Finance data.

Client Candidate submission projection returns a minimum recruitment-purpose profile only. It intentionally omits fields such as:

- Candidate source / Partner attribution
- full Candidate Master
- internal notes
- unrelated job history
- dropout detail outside the submitted placement projection
- private evidence / audit history

Client invoice projection returns the Client's own AR/invoice status only and does not expose Finance evidence/file/journal internals.

### Least-privilege hardening found during closeout

Security review found one over-broad role path before final closeout:

- initial `portal_client_jobs` allowed `client_finance`

This was hardened before closing Wave 7B.

Final Client Jobs read roles are:

- `client_admin`
- `client_recruiter`

`client_finance` is denied Client Jobs and remains limited to the finance-oriented projection path. A synthetic deny test passed and was cleaned up.

## Wave 7B acceptance

Internal Wave 7B catalog:

- P7B-001 … P7B-010 = **10 / 10 PASS**

Covered behavior includes:

- Candidate self isolation
- Partner own referral isolation
- Partner own commission isolation
- Client own job isolation
- Client Candidate active-purpose isolation
- purpose revoke removes visibility immediately
- Client own invoice isolation
- removed membership denial despite stale JWT subject
- spoofed organization denial
- anonymous RPC denial
- direct full Candidate Master denial
- minimum Candidate projection boundary

Synthetic business/auth/finance/purpose records were removed after acceptance.

## Canonical Portal Acceptance PT-001 … PT-014

Wave 7B closes only tests that have real implementation evidence.

**PASS — 7**

- PT-001
- PT-002
- PT-004
- PT-007
- PT-008
- PT-012
- PT-013

**NOT_RUN — 7**

- PT-003
- PT-005
- PT-006
- PT-009
- PT-010
- PT-011
- PT-014

The remaining tests require write/event/admin/support implementations that are outside Wave 7B. They are intentionally not marked PASS.

## Security / performance closeout

Supabase Security Advisor after final hardening:

- **0 lint**

Part 7B new control tables:

- RLS enabled
- explicit restrictive deny policy for `anon` / `authenticated`
- no direct table grants to `anon` / `authenticated`

SECURITY DEFINER review:

- API RPCs use empty `search_path`
- `anon` EXECUTE = false
- only purpose-specific authenticated RPCs are callable by `authenticated`
- internal validation/gate helper functions are not directly executable by `authenticated`

Missing FK index blocker:

- **0**

Every FK on `authz.client_candidate_purpose_access` has a leading covering index.

Performance Advisor:

- no blocking performance lint introduced by Wave 7B
- remaining notices are `unused_index` **INFO** in TEST / low-traffic state
- no index was removed solely because TEST has not yet exercised real workload

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Safety state after closeout

- `part7b_projection_foundation_ready = true`
- `part7b_foundation_closed = true`
- `portal_production_readiness_status = NOT_READY`
- `portal_external_access_enabled = false`
- `portal_candidate_enabled = false`
- `portal_partner_enabled = false`
- `portal_client_enabled = false`
- `province_scale_activation_enabled = false`
- `marketplace_enabled = false`
- enabled Portal feature flags = `0`
- current operational Source of Truth = `GOOGLE_SHEETS_DRIVE`

Therefore:

**Part 7B Read-Projection Foundation = CLOSED / PASS in TEST**

**External Portal Production = NOT_READY / DISABLED**

## Migration history

Wave 7B migrations:

- `20260901023843` — purpose access projection foundation
- `20260901023917` — purpose-specific portal read API
- `20260901024028` — cross-scope projection acceptance smoke
- `20260901024317` — Client Jobs role hardening + deny test
- `20260901024405` — final closeout guard

Supabase total after Wave 7B: **138 migrations**.

## Next architecture boundary

The canonical Part 7 handoff next contains S5 Portal Command/Event and remaining acceptance cases involving controlled writes/admin/support flows.

No real P1A/P1B portal pilot should be opened merely because the read foundation exists. A real pilot still requires a Founder-approved business trigger and the Part 7 Production gates.

Before any next wave implementation, revalidate current Supabase/GitHub state and re-read the canonical Part 7 sources.
