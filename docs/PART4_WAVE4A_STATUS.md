# Part 4 Wave 4A — Core Master Schema + Atomic Work Connect IDs

Status: **CLOSED / PASS WITH CONTROLLED SOURCE CONFLICT**
Date: 2026-08-29
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Architecture basis

- Part 4 Full-stack / Supabase / Storage Blueprint
- Part 4 PostgreSQL Target Schema Skeleton
- Part 4 Implementation Handoff
- Control Index V3.6
- Founder Master V1.1
- Live Data Hub `98_System_Config`

## Implemented

Schemas created/reserved:

`core / private / privacy / docs / finance / authz / config / api`

Core master foundation:

- `core.clients`
- `core.partners`
- `core.jobs`
- `core.candidates`
- `core.dorms`
- `core.transport_providers`
- `core.placements`
- `core.followups`

Atomic ID foundation:

- `config.id_allocators`
- `config.id_allocation_audit`
- `config.peek_business_id(...)`
- `config.allocate_business_id(...)`
- row-lock allocation (`SELECT ... FOR UPDATE`)
- allocation audit prevents reuse of an allocated number/ID
- allocator starting values initialized from live Data Hub `98_System_Config`

Safety gates:

- `business_master_apply_enabled = false`
- `production_cutover_approved = false`
- `external_channel_webhooks_enabled = false`
- `current_operational_source = GOOGLE_SHEETS_DRIVE`

## Candidate ID controlled conflict

Live `98_System_Config` currently says:

`MYC-C-000001`

and notes Founder approval dated 2026-08-29.

Founder Master V1.1 and Control Index V3.6 still preserve the Candidate business identity as:

`WC-C-000001`

Therefore Part 4A intentionally sets:

- Candidate allocator prefix snapshot = `MYC-C-`
- `allocation_enabled = false`
- `conflict_status = SOURCE_CONFLICT`
- no Candidate prefix CHECK constraint on `core.candidates` yet

This prevents mixed Candidate IDs until Founder authority resolves the conflict. Other non-conflicting allocators remain enabled.

## Acceptance — PASS

1. Synthetic atomic allocator returned `WC-TST-0001` then `WC-TST-0002`
2. Allocation audit contained exactly 2 rows and allocator advanced to 3
3. Partner next ID remained `WC-P-0003` from live Data Hub; no real Partner ID was consumed
4. Candidate allocator correctly rejected allocation while source conflict is active
5. Invalid Client business ID was rejected by database constraint
6. Client → Job and Partner → Candidate → Placement → Follow-up FK chain succeeded
7. Synthetic records fully cleaned after test
8. Core master tables remain empty after acceptance test
9. Supabase Security Advisor: PASS / 0 lint
10. Performance Advisor: no blocker; unused-index INFO only in low/no-traffic TEST

## Boundary after 4A

Core tables exist, but Domain Commands are still not allowed to mutate them automatically.

The next safe implementation track is **Part 4B — PII split / Private tables + Consent + File/Evidence abstraction**.
