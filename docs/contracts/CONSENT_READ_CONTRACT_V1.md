# MeYou Connect — Consent Read Contract V1

Status: TEST / READ CONTRACT ONLY  
Operational business authority: `GOOGLE_SHEETS_DRIVE`  
Canonical source: `MEYOU_CONNECT_MVP_DATA_HUB_V1/14_Consent_PDPA`

## Boundary

This contract does not create consent, infer consent, or change the operational Source of Truth. It only defines the evidence required before automation may rely on a consent decision.

Consent MUST NOT be inferred from ordinary chat, job application interest, photo/file submission, prior employment, or a historical relationship with MYC.

Until authoritative Data Hub read-back proves a current consent record, `AUTO_SUBMIT = FALSE`.

## Required consent capabilities

A Candidate consent read must be able to distinguish, without inference:

1. consent for submission to the current job / current opportunity;
2. consent for reuse of the Candidate profile for other jobs;
3. consent for job/news notifications;
4. withdrawal / decline that supersedes an earlier grant.

The exact Data Hub purpose codes must be read from `14_Consent_PDPA`; Engineering must not invent purpose-code values when the authoritative sheet cannot be read.

## Required evidence fields

For any consent relied upon by automation, the authoritative read must provide enough evidence to resolve:

- Candidate canonical ID;
- purpose / scope;
- decision;
- effective date/time;
- consent wording/version or equivalent authoritative version reference;
- evidence reference;
- source Raw reference when available;
- supersedes / withdrawal relationship when applicable.

If wording/version cannot be established from the authoritative source, automated submission remains fail-closed.

## Existing Supabase technical mirror

`privacy.consents` currently supports:

- `candidate_id`
- `purpose_code`
- `decision`
- `effective_at`
- `evidence_id`
- `source_raw_input_id`
- `supersedes_consent_id`

Allowed technical decisions are `GRANTED`, `WITHDRAWN`, and `DECLINED`.

`privacy.current_consents_v` deterministically selects the latest technical row per `(candidate_id, purpose_code)` by effective time / creation order.

The technical mirror does **not** currently contain an explicit consent-form/version field. This must not be fabricated; authoritative Data Hub version/evidence is required before an automated submit decision can be READY.

## Current live gate — 2026-09-19

Authoritative Google Data Hub read-back of `14_Consent_PDPA` succeeded.

- authoritative Data Hub rows: `0`
- `datahub_readback_verified = TRUE`
- read readiness: `READY`
- reason: `AUTHORITATIVE_SOURCE_READ_VERIFIED_EMPTY`
- technical `privacy.consents` rows: `0`
- `AUTO_SUBMIT = FALSE`

This distinction is intentional: an empty authoritative source is a successful read, but it supplies no consent grant. Automation remains fail-closed until a current explicit `GRANTED` record with the required purpose/evidence/version exists.

## Engineering lookup rule

For a requested Candidate + purpose:

1. read authoritative `14_Consent_PDPA` server-side;
2. resolve the current effective record and any supersession/withdrawal chain;
3. require evidence + effective date + version reference;
4. return one of `GRANTED | WITHDRAWN | DECLINED | NOT_FOUND | NOT_READY`;
5. permit auto-submit only for an explicit current `GRANTED` record covering the requested purpose;
6. any ambiguity, missing version/evidence, source read failure, or conflicting current record => `NOT_READY`, `AUTO_SUBMIT = FALSE`, and DQ/review as appropriate.

No browser-direct Data Hub access and no LLM authorization decision are permitted.
