# Part 4 Wave 4C — Controlled Domain Command Apply Layer

Status: **CLOSED / PASS**
Date: 2026-08-29
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Implemented

- `ops.master_apply_contracts`
- `ops.domain_command_apply_audit`
- `ops.domain_command_apply_backlog_v`
- `ops.open_apply_conflict(...)`
- `ops.apply_domain_command(...)`
- Domain Command `apply_status` expanded with `APPLYING` and `BLOCKED`
- Service-role-only apply functions
- direct anon/authenticated Core mutations revoked

## Controlled apply contracts

Eight active Part 3E command types are mapped to controlled Part 4 handlers:

1. `candidate.upsert_proposal`
2. `candidate.update_proposal`
3. `client_job.upsert_proposal`
4. `job.update_proposal`
5. `partner_attribution.proposal`
6. `evidence.register_proposal`
7. `evidence.route_proposal`
8. `consent.record_proposal`

## Safety gates

The apply layer reads the existing Part 4 gates and remains OFF by default:

- `business_master_apply_enabled = false`
- `postgres_docs_write_enabled = false`
- `postgres_consent_write_enabled = false`
- `production_cutover_approved = false`
- `current_operational_source = GOOGLE_SHEETS_DRIVE`

A command with a disabled gate becomes `BLOCKED` and does not mutate Master data.

## Candidate ID conflict

Candidate creation remains blocked while the Part 4A source conflict is unresolved:

- live System Config snapshot: `MYC-C-*`
- Founder Master / Control architecture: `WC-C-*`

Existing Candidate records can be updated by `candidate.update_proposal`, but new Candidate allocation is rejected with `CANDIDATE_ID_SOURCE_CONFLICT` until Founder authority resolves the standard.

## No silent overwrite / DQ

Protected existing Client/Job terms are not silently overwritten.

Conflicting values for material fields such as:

- Client `payment_term`
- Job `wage`
- Job `shift`
- Job `start_date`
- Job `milestone_deal`
- Job `payment_term`
- Candidate `partner_id` attribution

create/reuse an `ops.data_quality_issues` record with `DOMAIN_APPLY_CONFLICT` and leave the command `BLOCKED`.

## Idempotency

- one `domain_command_apply_audit` row per Domain Command
- repeated apply of an already-applied command returns the prior result
- Master effect key: `master_apply|<command_key>`
- `ops.event_effects` prevents duplicate logical Master effects

## Docs / Evidence / Consent integration

4C uses the protected Part 4B server functions rather than bypassing them:

- File Intake can become provider-neutral `docs.files`
- Evidence is registered through `docs.register_evidence_record(...)`
- Evidence links use `docs.link_evidence(...)`
- Consent uses `privacy.record_consent(...)`
- `SOURCE_NOT_MIRRORED` is preserved when original bytes are not mirrored
- Consent remains evidence-backed

## Acceptance — PASS

1. Disabled business gate blocked Candidate update with no mutation
2. Same command applied successfully after temporary TEST gate enablement
3. Partner attribution applied to an existing Candidate/Partner
4. Candidate create remained blocked by Candidate ID source conflict
5. Client + Job creation used atomic allocators
6. Re-applying the Client/Job command created no duplicate Master effect
7. Conflicting Job wage opened exactly one DQ issue and did not overwrite the existing wage
8. File Intake → File Registry → Evidence → Candidate profile-photo link succeeded
9. `SOURCE_NOT_MIRRORED` remained truthful through the apply layer
10. Consent creation required and linked Evidence
11. Apply audit covered all tested commands
12. Smoke test used a transaction and rolled back completely

## Post-test state

- Core Master test rows: 0
- Docs/Evidence test rows: 0
- Consent test rows: 0
- Apply-conflict DQ test rows: 0
- Apply audit test rows: 0
- Client next number: unchanged at 1
- Job next number: unchanged at 1
- File Registry next number: unchanged at 3 (`WC-FILE-000003` next)
- Evidence next number: unchanged at 1
- Consent next number: unchanged at 1
- DQ Issue next number: unchanged at 1
- Candidate allocator: still blocked by `SOURCE_CONFLICT`

## Validation

- Supabase Security Advisor: **PASS / 0 lint**
- Performance Advisor: no blocker; unused-index INFO only while TEST has little/no production traffic

## Boundary after 4C

The apply machinery is implemented and tested, but all persistent write gates remain OFF. Supabase is still not the operational Source of Truth.

Next safe track: **Part 4D — AuthZ / RLS API Surface + role-scoped RPC/views**, still TEST-first and without Production cutover.
