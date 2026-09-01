# Part 7 Wave 7A — Geography / Organization / Portal Access Foundation

Status: **CLOSED / PASS (TEST FOUNDATION)**  
External Portal Production: **NOT_READY**  
Date: 2026-09-01 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Implemented from:

- `MEYOU_CONNECT_SCALE_MULTI_PROVINCE_PORTAL_BLUEPRINT_V1.md`
- `MEYOU_CONNECT_PORTAL_SCALE_CONTROL_MATRIX_V1.xlsx`
- `MEYOU_CONNECT_SCALE_ROLLOUT_PLAYBOOK_V1.md`
- `MEYOU_CONNECT_PORTAL_SCALE_SQL_SKELETON_V1.sql`
- `MEYOU_CONNECT_CLAUDE_CODEX_IMPLEMENTATION_HANDOFF_PART7_V1.md`

Canonical decisions preserved:

- ONE MeYou Connect platform / ONE canonical business model.
- Province and Service Area are geography/operating dimensions, not tenant/database boundaries.
- Client/Partner external identity is organization-scoped membership.
- Candidate external identity uses a verified Candidate ↔ Auth user link and is not an organization tenant.
- Database membership/link records are authorization truth; a client-supplied org_id is never trusted alone.
- External portal feature flags do not replace RLS/authorization.
- No arbitrary Portal write to Master tables.
- Portal/Province rollout is trigger-based, not big-bang.
- Marketplace is not authorized by Part 7.

## Implemented

### Geography

Created:

- `geo.provinces`
- `geo.service_areas`
- `core.job_service_areas`
- `core.partner_service_areas`
- `core.dorm_service_areas`
- `core.transport_service_areas`
- `ops.region_assignments`

The live schema uses `core.transport_providers`, so the transport service-area mapping was reconciled to that actual Part 4 table rather than copying the reference skeleton literally.

No separate province-specific Candidate/Client/Partner IDs or databases were introduced.

### Province code boundary

The Part 7 sources require a canonical Thai province master but do not specify whether `province_code` must use DOPA, ISO, or an internal code convention.

Part 7A therefore creates the province master contract but intentionally does **not** seed 77 production province rows with an invented code convention.

Synthetic province rows used in acceptance were removed after the test.

### Organization model

Created:

- `authz.organizations`
- `authz.organization_members`

Organization types:

- CLIENT → existing `MYC-B2B-*`
- PARTNER → existing `MYC-P-*`

Database trigger validation rejects an organization that points to a nonexistent or wrong business party.

Portal membership lifecycle:

- INVITED
- ACTIVE
- SUSPENDED
- EXPIRED
- REMOVED

Portal roles implemented:

- client_admin
- client_recruiter
- client_finance
- partner_admin
- partner_member

Role/org-type mismatch is rejected.

### Candidate account link

Created:

- `authz.candidate_user_links`

Verification states:

- PENDING
- VERIFIED
- REJECTED

Default rule implemented: only one VERIFIED, non-disabled portal user link can exist for a Candidate at a time.

### Authorization predicates

Implemented:

- `authz.is_active_org_member(org_id)`
- `authz.has_portal_role(org_id, role)`
- `authz.is_verified_candidate_user(candidate_id)`
- `authz.current_candidate_id()`

Active membership requires:

- organization ACTIVE
- membership ACTIVE
- matching `auth.uid()`
- membership within active/expiry window
- no removed timestamp

A stale JWT subject does not bypass a removed membership because membership is resolved from the database on each predicate evaluation.

### Scale gate control plane

Seeded canonical scale gates:

- SG-01 Demand
- SG-02 Supply
- SG-03 Unit Economics
- SG-04 Collection
- SG-05 Relocation Support
- SG-06 Owner/Capacity
- SG-07 Data Quality
- SG-08 Compliance
- SG-09 Exit Plan

Created:

- `ops.scale_gate_catalog`
- `ops.province_scale_state`
- `ops.province_scale_gate_results`
- `ops.province_scale_readiness(...)`
- `ops.set_province_lifecycle(...)`

Province lifecycle:

`RESEARCH → DEMAND_VALIDATION → PILOT → ACTIVE → PAUSED/CLOSED`

Lifecycle transition guard prevents direct RESEARCH → ACTIVE jumps.

PILOT requires the documented demand/supply/local-support/owner prerequisites.

ACTIVE requires:

- all SG-01…09 READY with evidence
- Founder approval metadata
- `province_scale_activation_enabled = true`

The real activation master switch remains OFF.

### Portal feature flags

Created `ops.portal_feature_flags` and seeded TEST feature definitions disabled by default:

- partner_referral_submit
- partner_commission_view
- client_demand_submit
- client_candidate_status
- client_invoice_view
- candidate_profile_edit
- candidate_consent
- candidate_file_upload
- candidate_followup
- region_console

Feature flag scope supports environment plus optional organization/service area.

No feature is enabled after 7A.

### Canonical Portal acceptance catalog

Seeded `PT-001…PT-014` from the Part 7 Control Matrix into `ops.portal_acceptance_catalog`.

Important: **all 14 remain NOT_RUN in Part 7A**.

Part 7A does not claim that cross-client/cross-partner portal projections pass before those projections actually exist.

### 7A foundation acceptance

Added and passed 8 foundation-only tests:

- P7A-001 Geography is not tenancy
- P7A-002 Organization ↔ business-party validation
- P7A-003 Active membership is database authorization truth
- P7A-004 Removed member denied despite stale JWT subject
- P7A-005 Multi-org user cannot spoof an unowned org
- P7A-006 Candidate verified-link isolation / one-active-link default
- P7A-007 Portal feature flags fail safe OFF
- P7A-008 Province ACTIVE scale gate

Result: **8 / 8 PASS**.

Synthetic residue after acceptance:

- synthetic province: 0
- synthetic Auth users: 0
- synthetic organizations: 0
- synthetic Candidate links: 0

### Internal status API

Added capability `portal_scale_read` to:

- Founder
- Secretary
- Data Audit

Read-only internal API:

- `api.part7a_foundation_status()`
- `api.portal_feature_flag_status()`
- `api.portal_acceptance_status()`
- `api.province_scale_status(province_code)`

No external Client/Partner/Candidate business-data projection API was opened in 7A.

### RLS / direct access

All new Part 7A base/control tables have RLS enabled with explicit restrictive DENY policy for `anon` and `authenticated` direct-table access.

Only controlled Auth predicates are executable by authenticated users. Internal control/status APIs require the internal `portal_scale_read` capability.

## Safety state

- `portal_scale_foundation_ready = true`
- `part7a_foundation_closed = true`
- `portal_production_readiness_status = NOT_READY`
- `portal_external_access_enabled = false`
- `portal_candidate_enabled = false`
- `portal_partner_enabled = false`
- `portal_client_enabled = false`
- `province_scale_activation_enabled = false`
- `marketplace_enabled = false`

Therefore:

**Part 7A Foundation = CLOSED / PASS**

**External Portal / Real Province Activation = NOT_READY / DISABLED**

## Security / performance

- Supabase Security Advisor: **PASS / 0 lint**
- missing-FK-index blocker: **0** after index hardening
- remaining performance notices are `unused_index` INFO in TEST
- no external portal feature was enabled

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Migration history

Part 7A migrations:

- `20260901021817` — geography / organization / portal-access foundation
- `20260901021910` — scale gates / feature flags / identity controls
- `20260901021952` — internal status API + RLS hardening
- `20260901022018` — province lifecycle transition hardening
- `20260901022112` — foundation acceptance smoke
- `20260901022207` — FK index hardening
- `20260901022230` — final closeout

Supabase total after Part 7A: **133 migrations**.

## Boundary after 7A

Part 7A completes implementation-handoff S1 Geography, S2 Organizations and S3 Candidate Account Link foundations, plus fail-safe feature-flag/scale-gate groundwork.

It does not implement S4 Portal API Projection, S5 Portal Command/Event, or the full PT-001…014 RLS acceptance yet.

Next implementation track: **Part 7B — Purpose-specific Candidate / Partner / Client portal read projections + cross-scope RLS acceptance**, still TEST-only and with every external master switch OFF.
