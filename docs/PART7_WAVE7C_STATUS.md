# Part 7 — Wave 7C Status

**Project:** MeYou Connect  
**Environment:** Supabase TEST (`pgjmxdeafzogzsyawejs`)  
**Status:** **CLOSED / PASS (TEST — S5 Portal Command/Event + Candidate Controlled Write Foundation)**  
**Production External Portal:** **NOT_READY / OFF**

## Canonical scope

Wave 7C implements the S5 Portal Command/Event boundary from the Part 7 implementation handoff without opening any external Portal in Production.

Canonical write path preserved:

`Portal Action -> Authenticated Identity -> Candidate/Org validation -> Raw Input -> Event -> Worker/Command validation -> Controlled effect -> Audit`

No arbitrary external Master-table write path was introduced.

## Implemented

- `ops.portal_action_catalog`
- `ops.portal_action_requests`
- explicit Portal action classes and DENY boundaries
- Candidate contact proposal API bound to `authz.current_candidate_id()`
- Candidate placement-outcome report API that cannot mutate verified Placement truth
- Part 3 Raw/Event routing for Portal actions
- dedicated Candidate contact worker contract
- dedicated controlled apply function for `private.candidate_contacts`
- PII whitelist limited to `phone`, `line_id`, `email`
- apply-time revalidation of verified Candidate-user link
- request idempotency and Raw/Event/trace provenance
- Portal feature flags remain OFF after testing

## Acceptance evidence

### Wave 7C

`P7C-001..P7C-008` = **8 / 8 PASS**

Evidence includes:

- Candidate self-bound contact ingress creates Raw Input + Event + Portal action chain
- cross-Candidate mutation denied
- high-risk/non-whitelisted PII rejected before ingress
- Partner cannot set Candidate consent or protected B2B pricing
- Candidate placement outcome remains report/event only
- duplicate request ID does not create duplicate effect
- disabled Candidate-user link blocks new ingress
- full worker apply preserves actor/Candidate/Raw/Event/trace/audit chain

Synthetic Candidate/Client/Partner/Auth/Event/Command/PII test records were cleaned after smoke execution.

### Canonical Portal acceptance

**PASS (11 / 14):**

`PT-001, PT-002, PT-003, PT-004, PT-005, PT-007, PT-008, PT-010, PT-011, PT-012, PT-013`

**NOT_RUN (3 / 14):**

- `PT-006` Client Finance payment-evidence controlled upload/event path
- `PT-009` Partner Admin controlled own-organization member invite
- `PT-014` Authorized internal support access with audit trail

These remain intentionally NOT_RUN until the next implemented controls genuinely support the scenarios.

## Security / performance closeout

- Supabase Security Advisor: **0 lints**
- RLS enabled on all new Wave 7C control/evidence tables
- restrictive external deny policies present
- no direct `anon` / `authenticated` table grants on new internal control tables
- Portal public APIs are `SECURITY DEFINER` with empty `search_path`
- internal helper/apply functions are not executable by `anon` or `authenticated`
- Performance Advisor initially found one missing FK covering index on `ops.portal_action_requests.action_key`
- fixed by `portal_action_requests_action_key_idx`
- post-fix Performance Advisor has no Wave 7C missing-FK finding; remaining notices are TEST `unused_index` INFO only and were not treated as deletion candidates

## Safety state after closeout

- `portal_external_access_enabled=false`
- `portal_candidate_enabled=false`
- `portal_partner_enabled=false`
- `portal_client_enabled=false`
- `province_scale_activation_enabled=false`
- `marketplace_enabled=false`
- `business_master_apply_enabled=false`
- enabled Portal feature flags = `0`
- Operational Source of Truth = `GOOGLE_SHEETS_DRIVE`
- `part7c_foundation_closed=true`
- `portal_production_readiness_status=NOT_READY`

## Supabase migrations

1. `20260901031432_part7_wave7c_portal_command_event_foundation.sql`
2. `20260901031642_part7_wave7c_candidate_contact_worker_apply.sql`
3. `20260901031924_part7_wave7c_candidate_command_acceptance_smoke.sql`
4. `20260901031959_part7_wave7c_fk_index_hardening.sql`
5. `20260901032103_part7_wave7c_final_closeout.sql`

Supabase migration count after Wave 7C: **143**.

## Next canonical boundary

Proceed in TEST to the remaining protected-control scope:

- S7 MFA / step-up foundation
- `PT-006` controlled Client payment evidence path without allowing `COLLECTED`
- `PT-009` step-up protected Partner Admin own-org member invitation
- `PT-014` capability-scoped audited internal support access

Do **not** open P1A/P1B pilot, Production external Portal, marketplace, or province activation merely because the technical controls exist. A real Founder-approved business trigger is still required.