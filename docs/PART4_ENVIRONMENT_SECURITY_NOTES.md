# Part 4 — Environment & Security Notes

Status: TEST IMPLEMENTATION

## Environment boundary

- Supabase project used by Part 4 is a TEST implementation target.
- Current operational Source of Truth remains Google Sheets + Google Drive.
- Production cutover is not approved by this repository or by Part 4 closeout alone.

## Secrets

- Never commit database passwords, service-role keys, API keys, JWT signing secrets or provider credentials.
- Repository `.gitignore` excludes local `.env*` files and Supabase local state.
- Frontend code must never contain service-role or privileged secrets.
- Production secrets must live in approved environment/secret stores.

## Database access

- Business/private/finance/authz tables use RLS/default-deny controls.
- Administrative write functions are service-role controlled.
- API projections are role-scoped and intentionally narrower than internal tables.
- Auth users/Founder identity are not invented automatically by migrations.

## Storage

TEST buckets:

- `raw-inbox-private`
- `evidence-private`
- `business-private`
- `content-public`

All remain private during TEST, including `content-public`; any future public exposure requires a separate decision and policy review.

## Safety gates

The following must remain OFF until their specific acceptance/approval path is satisfied:

- `business_master_apply_enabled`
- `postgres_private_write_enabled`
- `postgres_docs_write_enabled`
- `postgres_consent_write_enabled`
- `finance_write_enabled`
- `finance_external_payment_execution_enabled`
- `migration_target_apply_enabled`
- `migration_cutover_enabled`
- `production_cutover_approved`
- `external_channel_webhooks_enabled`

## Stable identity

Canonical business namespace is `MYC-*`, aligned with the current Founder Master and Data Hub. Legacy/stale `WC-*` implementation patterns must not be reintroduced from old snapshots.

## Production-specific controls still required

Part 4 TEST closeout does not prove the following Production controls:

- named privileged identities
- MFA/step-up where supported
- live webhook authentication/signature verification
- Production secret rotation/storage
- Production backup freshness and restore evidence
- Production-like RLS acceptance with real roles
- live object/file checksum migration
- live finance reconciliation
- incident/alert ownership in the actual runtime

These remain Production-readiness evidence items rather than assumed PASS conditions.
