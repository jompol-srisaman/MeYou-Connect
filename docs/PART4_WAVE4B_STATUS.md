# Part 4 Wave 4B — PII Split + Consent + File/Evidence Abstraction

Status: **CLOSED / PASS**
Date: 2026-08-29
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Architecture basis

- `MEYOU_CONNECT_FULLSTACK_TARGET_SCHEMA_V1`
- `MEYOU_CONNECT_RAW_INPUT_EVIDENCE_SOP_V1`
- Control Index V3.6
- Part 4A Core Master / Atomic ID foundation

## Implemented

### PII split

- `private.candidate_contacts`
- `private.client_contacts`
- `private.partner_contacts`

Candidate/Client/Partner contact and sensitive fields are kept outside the `core` schema.

### Consent history

- `privacy.consents`
- `privacy.current_consents_v`
- evidence-backed consent required
- withdrawals are preserved as new records and link to the record they supersede
- withdrawal cannot silently overwrite a prior grant

### File / Evidence abstraction

- `docs.storage_profiles`
- `docs.files`
- `docs.evidence`
- `docs.evidence_links`
- provider-neutral file metadata (`GOOGLE_DRIVE`, `SUPABASE_STORAGE`, `CLOUDFLARE_R2`, `OTHER`)
- Drive/provider references remain provenance, not business identity
- `SOURCE_NOT_MIRRORED` is explicitly supported
- stored/mirrored evidence object identity cannot be silently overwritten; create a new File Registry ID/version instead

### Candidate photo support

Candidate photos are represented as controlled File/Evidence records and linked to Candidate through `docs.evidence_links` with role such as `PROFILE_PHOTO`. This avoids placing raw image URLs/bytes in Candidate Core Master.

### Storage profiles

Target profiles:

- `raw-inbox-private`
- `evidence-private`
- `business-private`
- `content-public`
- `backup-private` (external/separate backup target)

Supabase TEST provisioned these buckets locally:

- `raw-inbox-private`
- `evidence-private`
- `business-private`
- `content-public`

All four remain **private** in TEST. `content-public` is only a desired future public scope and is locked private until an approved production/public-access gate.

### Safety gates — remain OFF

- `postgres_private_write_enabled = false`
- `postgres_docs_write_enabled = false`
- `postgres_consent_write_enabled = false`
- `supabase_storage_external_access_enabled = false`
- Part 4A `business_master_apply_enabled = false` remains unchanged
- Part 4A `production_cutover_approved = false` remains unchanged

## Security

- RLS enabled on private/privacy/docs tables
- explicit restrictive deny policies for `anon` and `authenticated`
- no direct client-side API table access
- service-role/server path only at this stage
- Supabase Security Advisor: **PASS / 0 lint** after explicit deny policies

## Acceptance — PASS

1. Candidate PII stored in `private.candidate_contacts`, not Candidate Core
2. Client and Partner contact split works
3. `SOURCE_NOT_MIRRORED` preserves source URL/provider reference honestly
4. Candidate profile photo can be linked as Evidence without embedding the image in Core Master
5. Supabase stored-object identity becomes immutable after `STORED/MIRRORED/ARCHIVED`
6. Consent GRANTED → WITHDRAWN preserves two evidence-backed history rows
7. `current_consents_v` resolves the latest decision as WITHDRAWN
8. anon/authenticated direct table privileges are absent
9. RLS is active on Candidate PII, Consent and File Registry tables
10. Smoke transaction rolled back fully; no real IDs were consumed
11. File Registry allocator remains next `WC-FILE-000003`
12. Evidence allocator remains next `WC-EV-000001`
13. Consent allocator remains next `WC-CN-000001`
14. All TEST storage buckets remain private
15. Performance Advisor has no missing-FK-index issue after follow-up migration; remaining notices are unused-index INFO only in low/no-traffic TEST

## Data residue after test

- candidate_contacts: 0
- client_contacts: 0
- partner_contacts: 0
- docs.files: 0
- docs.evidence: 0
- docs.evidence_links: 0
- privacy.consents: 0

## Candidate ID conflict

Part 4A Candidate ID conflict remains intentionally unresolved/blocked (`MYC-C-*` in live System Config vs `WC-C-*` in Founder Master/Control). Part 4B does not change or consume the Candidate allocator.

## Boundary after 4B

Part 4B builds protected PII/Privacy/Document structures only. PostgreSQL is still not the operational Source of Truth and Domain Commands still cannot automatically mutate business master data.

Next safe implementation track: **Part 4C — Controlled Domain Command Apply Layer + Master write contracts (still TEST-gated).**
