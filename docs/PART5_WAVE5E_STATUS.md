# Part 5 Wave 5E — Secrets / Credential Separation / Environment Isolation

Status: **CLOSED / PASS (TEST FOUNDATION)**  
Production Readiness: **NOT_READY**  
Date: 2026-08-30 (Asia/Bangkok)  
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Implemented from:

- `MEYOU_CONNECT_SECURITY_RELIABILITY_OBSERVABILITY_BLUEPRINT_V1.md`
- Part 5 Security Control Matrix / Production Gates
- Part 5A security control plane

Operational Source of Truth remains Google Sheets + Google Drive.

## Canonical rules preserved

- Default Deny / Least Privilege
- TEST and PROD must use separate verified credentials
- secrets must not be stored in Drive docs/sheets, prompt text, committed source, frontend bundles or screenshots
- allowed secret locations are approved environment/deployment/provider/CI credential stores
- service/privileged credentials remain server-only
- exposed or suspected-exposed credentials require rotation/revocation evidence

No secret value is stored by Part 5E tables, GitHub migration files or security evidence records.

## Implemented

### Environment and credential control plane

New objects include:

- `ops.security_environments`
- `ops.credential_requirements`
- `ops.credential_bindings`
- `ops.credential_separation_v`

Current environment state:

- TEST Supabase project exists and is verified for TEST control-plane purposes
- PROD remains `NOT_CREATED` / unverified

A credential binding cannot become `VERIFIED` unless its environment is `ACTIVE` and verified.

The credential binding registry stores references/metadata only. Metadata keys commonly associated with raw secrets are rejected.

### Secret scan evidence registry

- `ops.secret_scan_runs`
- `ops.secret_scan_findings`
- `ops.secret_scan_readiness_v`

Required current scopes represented:

- GitHub repository
- Google Drive
- Prompt history
- Frontend build is not currently required because no production frontend build is active

Connected targeted searches performed during Part 5E:

- GitHub: no hits for tested high-risk token markers; result recorded as `PARTIAL`
- Google Drive: no hits for tested high-risk token markers; result recorded as `PARTIAL`
- Prompt history: one known prior sensitive-credential exposure is represented as a redacted `KNOWN_EXPOSURE`; rotation/revocation evidence is not yet verified

The connected GitHub/Drive searches are not represented as complete provider-native secret scans or DLP scans.

### Credential rotation evidence

- `ops.credential_rotation_events`
- `ops.rotation_readiness_v`

Supported control events:

- `EXPOSURE_DECLARED`
- `ROTATED`
- `REVOKED`
- `VERIFIED`

Rotation timing uses statement-time timestamps so exposure followed by remediation can be ordered correctly.

### Read-only security API

- `api.security_scan_readiness()`
- `api.environment_separation_readiness()`
- `api.part5e_readiness_status()`

The client API exposes only readiness state / coverage, not credential references, secret-store references or secret material.

### RLS / default deny

Part 5E operational tables use RLS plus explicit restrictive DENY policies for `anon` and `authenticated`.
Service-role execution remains server-only.

## Acceptance smoke — PASS

Transactional acceptance validated:

1. current real Supabase credential separation remains `NOT_READY`
2. known prompt-history exposure is visible to the readiness model
3. targeted GitHub scan remains `NOT_READY` rather than being overclaimed as complete
4. an unverified PROD environment cannot receive a `VERIFIED` credential binding
5. metadata attempting to contain secret-style keys is rejected
6. distinct synthetic TEST and PROD credential references pass separation
7. reusing the same secret-store reference across TEST and PROD fails separation
8. exposure is detected as `ROTATION_REQUIRED`
9. later synthetic rotation changes readiness to `REMEDIATED`
10. synthetic credential, rotation and scan records are fully removed

Synthetic residue after smoke:

- credential bindings: 0
- rotation events: 0
- smoke scan runs: 0

## Current Production Gate state

`PG-004 — No secret/service key in frontend/repo/Drive/prompts` = **NOT_READY**

Reasons:

- GitHub/Drive connected scans are targeted/partial rather than exhaustive
- a known prior prompt-history exposure still requires verified rotation/revocation evidence

`PG-005 — TEST and PROD credentials separated` = **NOT_READY**

Reason:

- PROD environment/credential does not yet exist and has not been verified

Part 5E deliberately does not invent PROD credentials or mark these gates PASS from synthetic smoke data.

Latest Security Gate snapshot:

- TEST: **9 PASS / 0 FAIL / 6 NOT_READY**
- PROD: **3 PASS / 0 FAIL / 12 NOT_READY**

## Safety state

- `security_secret_environment_foundation_ready = true`
- `part5e_foundation_closed = true`
- `security_secret_scan_review_complete = false`
- `security_test_prod_credentials_separated = false`
- `production_cutover_approved = false`
- PROD environment remains uncreated/unverified

## Security / performance

- Supabase Security Advisor: **PASS / 0 lint**
- missing-FK-index finding introduced by Part 5E was corrected
- remaining performance notices are only `unused_index` INFO in the low/no-traffic TEST environment

Reference: https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index

## Migration history

Part 5E migrations:

- `20260830060044` — secret / environment foundation
- `20260830060211` — secret-scan / isolation engine
- `20260830060307` — role-scoped security read API
- `20260830060347` — connected scan evidence
- `20260830060427` — rotation / environment hardening
- `20260830060527` — rotation clock hardening
- `20260830060551` — acceptance smoke
- `20260830060715` — final evidence + Security Gate snapshot
- `20260830060859` — explicit-deny RLS hardening
- `20260830060930` — FK index hardening

Supabase total after Part 5E: **100 migrations**.

## Boundary after 5E

Part 5E provides the metadata-only secret/credential/environment-isolation control plane and validates its enforcement in TEST.

It does not perform provider credential creation, credential rotation, exhaustive secret scanning or Production environment activation.

Next safe implementation track: **Part 5F — Production-Gate / Change-Reliability / Part 5 End-to-End Closeout**, while Production cutover remains blocked.