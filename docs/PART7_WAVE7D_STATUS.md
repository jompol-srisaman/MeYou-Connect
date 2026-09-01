# Part 7 — Wave 7D Status

**Project:** MeYou Connect  
**Environment:** Supabase TEST (`pgjmxdeafzogzsyawejs`)  
**Status:** **CLOSED / PASS (TEST — S7 Step-up + Protected Portal Controls)**  
**Production External Portal:** **NOT_READY / OFF**

## Canonical scope

Wave 7D completes the S7 MFA / step-up foundation and closes the remaining canonical Portal acceptance scenarios without opening any external Portal in Production.

Protected control paths remain event-driven and capability scoped. External Portal business access remains disabled after testing.

## Implemented

### Step-up / identity

- `authz.require_step_up_aal2()`
- AAL2 required for Partner membership administration
- AAL2 required for internal Portal support access
- internal support capability `portal_support_access`
- apply-time capability / membership revalidation for protected workers

### Client Finance payment evidence

- `api.portal_client_submit_payment_evidence(...)`
- own Client organization / own AR validation
- controlled Raw Input + File Intake + `finance.payment_evidence.received` Event
- evidence metadata points to private evidence storage profile
- upload/report path never sets AR `collected` or Revenue `COLLECTED`
- cross-client AR evidence submission denied
- direct authenticated finance-table mutation denied

### Partner membership

- `api.portal_partner_invite_member(...)`
- only `partner_admin`
- only own active Partner organization
- AAL2 required
- worker creates only `partner_member` with `INVITED` status
- worker revalidates Partner Admin membership at apply time
- revoked/stale Partner Admin is blocked before membership effect

### Internal support

- `api.request_portal_support_access(...)`
- `api.portal_support_action_request(...)`
- capability + AAL2 required
- read denied until worker creates an audited grant
- grant is scoped to one Portal action request
- grant validity is 15 minutes
- support access produces `ops.portal_support_access_audit`
- support grant also creates a Security Event audit record

## Acceptance evidence

### Wave 7D

`P7D-001..P7D-008` = **8 / 8 PASS**

Verified scenarios include:

- AAL1 denied for protected Partner membership command
- AAL2 Partner Admin own-org invite accepted
- cross-org Partner invite denied
- worker creates INVITED membership only
- apply-time revoked Partner Admin denied
- own Client AR payment evidence accepted as Raw/File/Event
- cross-client payment evidence denied
- Client cannot mark finance truth `COLLECTED`
- AAL1 internal support denied
- unauthorized AAL2 internal support denied
- AAL2 authorized support requires audited grant before scoped read

Synthetic Client, Partner, AR, Revenue, Auth, Event, Command, File Intake, membership and support-access records were cleaned after smoke execution.

### Canonical Portal acceptance

`PT-001..PT-014` = **14 / 14 PASS in TEST**

Wave 7D closed the final three scenarios:

- `PT-006` Upload payment evidence — ALLOW controlled event/upload; cannot mark COLLECTED
- `PT-009` Invite member to own org — ALLOW controlled membership command
- `PT-014` Access case with audit trail — ALLOW within internal permission

Canonical TEST acceptance completion does **not** authorize a Production pilot or Production external Portal.

## Security / performance closeout

- Supabase Security Advisor: **0 lints**
- all new Wave 7D tables use RLS
- restrictive deny policies for `anon` / `authenticated`
- no direct external table grants on Wave 7D internal control/evidence tables
- public Portal RPCs are `SECURITY DEFINER` with empty `search_path`
- internal step-up/capability helpers and worker apply functions are not executable by `anon` / `authenticated`
- all Wave 7D / Portal support Foreign Keys have leading covering indexes
- Performance Advisor has no missing-FK blocker for Wave 7D
- remaining Performance Advisor notices are `unused_index` INFO in TEST and are not treated as automatic deletion candidates

Supabase linter reference: https://supabase.com/docs/guides/database/database-linter

## Safety state after closeout

- `portal_external_access_enabled=false`
- `portal_candidate_enabled=false`
- `portal_partner_enabled=false`
- `portal_client_enabled=false`
- `province_scale_activation_enabled=false`
- `marketplace_enabled=false`
- enabled Portal feature flags = `0`
- Operational Source of Truth = `GOOGLE_SHEETS_DRIVE`
- `part7d_foundation_closed=true`
- `portal_production_readiness_status=NOT_READY`

## Supabase migrations

1. `20260901032941_part7_wave7d_step_up_protected_controls_foundation.sql`
2. `20260901033030_part7_wave7d_protected_worker_apply.sql`
3. `20260901035907_part7_wave7d_protected_controls_acceptance_smoke.sql`
4. `20260901040055_part7_wave7d_final_closeout.sql`

Supabase migration count after Wave 7D: **147**.

## Issue resolved during acceptance

The first local attempt at the 7D smoke conflicted with an automatically created `authz.user_profiles` row for synthetic `auth.users`. That attempt rolled back and was not recorded as a migration. The accepted smoke uses an upsert for the synthetic support profiles, then completed all acceptance tests successfully with full synthetic cleanup.

## Next boundary

Part 7 technical TEST acceptance is complete. Do not automatically open P1A/P1B, Production external Portal, marketplace, or province activation.

The next legitimate step is a Founder-approved real pilot selection based on a real business bottleneck and the canonical rollout playbook, followed by Production-specific gates/evidence. Until then, Production remains NOT_READY.