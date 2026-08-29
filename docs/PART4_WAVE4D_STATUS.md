# Part 4 Wave 4D — AuthZ + RLS + API Surface

Status: **CLOSED / PASS**
Date: 2026-08-30 (Asia/Bangkok)
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Implemented

### AuthZ model

- `authz.role_catalog`
- `authz.user_profiles`
- `authz.user_roles`
- `authz.role_capabilities`
- `authz.role_assignment_audit`
- automatic blank profile creation after a real Supabase Auth user is created
- role assignment/revocation is service-role/server only
- role assignment history is preserved
- expiring role assignments are supported

Canonical roles seeded:

1. `founder`
2. `secretary`
3. `candidate_ops`
4. `client_sales`
5. `finance_control`
6. `content_studio`
7. `data_audit`
8. `automation_worker`

No real Auth user or Founder account was created automatically in this wave.

### Capability layer

Server-side helpers:

- `authz.current_roles()`
- `authz.has_role(...)`
- `authz.has_any_role(...)`
- `authz.current_capabilities()`
- `authz.has_capability(...)`
- `authz.require_capability(...)`
- `authz.assign_role(...)`
- `authz.revoke_role(...)`

Founder alone receives `protected_action_approve` in this wave.

### Direct-table protection

Core tables now have RLS enabled and explicit authenticated/anon deny policies.

Authenticated clients do not receive direct read/write access to:

- `core`
- `private`
- `privacy`
- `docs`

Private/Privacy/Docs remain protected by the Part 4B default-deny model.

### Curated API surface

Role-scoped RPCs:

- `api.current_access_context()`
- `api.list_job_catalog(...)`
- `api.get_candidate_summary(...)`
- `api.get_candidate_contact(...)`
- `api.get_client_record(...)`
- `api.list_placement_status(...)`
- `api.get_consent_status(...)`

Security-invoker convenience views:

- `api.my_access_v`
- `api.job_catalog_v`

No frontend Master-write RPC is exposed in 4D.

### Field minimization / masking

- Candidate contact PII is available only to Founder / Secretary / Candidate Ops / Data Audit through the dedicated contact RPC.
- Client Sales can read Client contact projection, but not Candidate contact PII.
- Finance Control can see Client payment terms and Candidate ID/status projection, while contact fields and Candidate operational detail are masked.
- Content Studio can read only the curated job catalog and cannot query Candidate data.
- Candidate national ID, DOB and emergency-contact fields are not exposed by the general Candidate contact RPC.

## Acceptance — PASS

The smoke migration created six synthetic Supabase Auth users inside a transaction and impersonated the real PostgreSQL `authenticated` role with JWT subject context.

Validated:

1. Candidate Ops received Candidate summary/contact/consent/job access.
2. Candidate Ops direct `core.candidates` SELECT was denied.
3. Candidate Ops could not self-assign Founder role.
4. Client Sales received Client contact projection and limited Candidate summary.
5. Client Sales could not access Candidate contact PII.
6. Finance Control received payment terms while Client contact fields were masked.
7. Finance Control Candidate projection exposed status but masked operational detail.
8. Content Studio could read the OPEN Job Catalog and could not read Candidate summary.
9. Founder access context included `protected_action_approve`.
10. Authenticated no-role identity received no business API access.
11. `anon` could not execute authenticated API RPCs.
12. Smoke transaction rolled back completely.

## Post-test state

- `auth.users`: 0
- `authz.user_profiles`: 0
- `authz.user_roles`: 0
- `authz.role_assignment_audit`: 0
- Core synthetic rows: 0
- Docs synthetic rows: 0
- Consent synthetic rows: 0

Only role definitions and capability configuration remain, as intended.

## Security / Performance validation

- Supabase Security Advisor: **PASS / 0 lint**
- Missing FK indexes found after 4D were added.
- RLS `auth.uid()` init-plan warnings were fixed using `(select auth.uid())`.
- Remaining Performance notices are unused-index INFO only while TEST has little/no real traffic.

## Existing safety gates remain unchanged

- `business_master_apply_enabled = false`
- `postgres_private_write_enabled = false`
- `postgres_docs_write_enabled = false`
- `postgres_consent_write_enabled = false`
- `production_cutover_approved = false`
- `external_channel_webhooks_enabled = false`
- `current_operational_source = GOOGLE_SHEETS_DRIVE`

Candidate creation remains blocked by the unresolved Candidate ID source conflict (`MYC-C-*` live System Config vs `WC-C-*` Founder Master/Control).

## Boundary after 4D

Authentication and authorization foundations are now ready for real named users, but no real Auth account is created and no Production API/cutover is enabled automatically.

Next safe implementation track: **Part 4E — Finance / Accounting schema foundation + controlled financial state contracts**, TEST-first and with real payment actions still protected.
