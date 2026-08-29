# Part 4 Wave 4E — Finance / Accounting Foundation

Status: **CLOSED / PASS**
Date: 2026-08-30 (Asia/Bangkok)
Environment: Supabase TEST (`pgjmxdeafzogzsyawejs`)

## Source basis

Part 4E was implemented from the existing approved/current operating sources rather than inventing a new finance model:

- `MEYOU_CONNECT_ACCOUNTING_LEDGER_V1`
- Data Hub `08_Revenue`
- Data Hub `09_Expense`
- Data Hub `10_Commission`
- Data Hub `98_System_Config`
- Data Hub `99_Lists`
- Part 4 Full-stack Target Schema
- Founder Master / AI Permission controls

Accounting principle preserved:

`Raw Input → File/Evidence → Business Record → Journal → Bank/AR/AP`

A Journal Batch is not `POSTED` unless Debit = Credit.

## Candidate ID source conflict — RESOLVED

The latest live `98_System_Config` now explicitly defines:

- Candidate prefix: `WC-C-`
- next Candidate ID: `WC-C-000001`
- rule: MeYou Connect brand migration does not alter `WC-*` business IDs

This matches Founder Master / Control architecture.

Part 4E therefore safely:

- changed the stale Supabase allocator snapshot from `MYC-C-*` to `WC-C-*`
- set `allocation_enabled = true`
- set `conflict_status = NONE`
- restored the database constraint `^WC-C-[0-9]{6}$`

No Candidate ID had been allocated while the stale conflict block existed.

## Finance schema foundation

Implemented:

- `finance.accounts`
- `finance.revenue`
- `finance.expenses`
- `finance.commissions`
- `finance.journal_batches`
- `finance.journal_lines`
- `finance.accounts_receivable`
- `finance.accounts_payable`
- `finance.bank_transactions`
- `finance.tax_documents`
- `finance.monthly_close_checks`
- `finance.financial_state_history`
- `finance.state_transition_rules`

Derived/read models:

- `finance.accounts_receivable_v`
- `finance.accounts_payable_v`
- `finance.trial_balance_v`
- `finance.pnl_internal_v`
- `finance.commission_payable_candidates_v`

The Chart of Accounts from Accounting Ledger V1 was seeded without replacing its source terminology.

## Revenue state contract

Preserved canonical lifecycle:

`EXPECTED → EARNED → INVOICED → COLLECTED`

`COLLECTED` requires all of the following in the controlled server path:

- Finance write/collection gates enabled
- collection Evidence
- reconciled incoming Bank Transaction
- Bank amount equals Revenue net received
- Bank Transaction Evidence matches collection Evidence

Collection updates the related AR record and records financial state history.

## Journal contract

Server-only functions:

- `finance.create_journal_batch(...)`
- `finance.add_journal_line(...)`
- `finance.post_journal_batch(...)`

Controls:

- finance write gate required
- posting gate required
- at least two journal lines
- Debit must equal Credit
- duplicate posting is idempotent
- posted batches cannot have lines modified through the controlled function

## Commission boundary

Canonical Commission states are preserved in the schema:

`PENDING → EARNED → WAITING_COLLECTION → PAYABLE → PAID`

Part 4E implements **read-only PAYABLE eligibility**:

- a Commission waiting for collection becomes PAYABLE-eligible only when its linked Revenue is `COLLECTED`
- `finance.commission_transition_allowed(...)` explicitly does not expose `PAID`

Part 4E intentionally does **not** expose a callable `PAYABLE → PAID` transition and does not execute any external payment/bank transfer.

A later protected payment-recording workflow must remain separately approval-controlled.

## Stable finance IDs

Existing live allocators are used for:

- `WC-JRN-*` — Journal Batch
- `WC-AR-*` — AR
- `WC-AP-*` — AP
- `WC-BANK-*` — Bank Transaction
- `WC-TAX-*` — Tax Document

The live `98_System_Config` does not currently define allocator prefixes for:

- Revenue
- Expense
- Commission

Therefore Part 4E does **not invent prefixes** for these three entities. Their PostgreSQL tables accept the stable IDs supplied by the operational Source of Truth until the source defines an official allocator rule.

## RLS / role-scoped API

Direct `anon` / `authenticated` access to Finance tables is denied.

Capabilities added:

- Founder: `finance_read`, `finance_accounting_read`
- Secretary: `finance_read`
- Finance Control: `finance_read`, `finance_accounting_read`
- Data Audit: `finance_read`, `finance_accounting_read`

Read-only API surface:

- `api.finance_revenue_overview(...)`
- `api.finance_ar_aging()`
- `api.finance_commission_overview()`
- `api.finance_trial_balance()`
- `api.finance_pnl_internal()`
- `api.finance_monthly_close(...)`

No frontend Finance write RPC was exposed.

## Acceptance — PASS

The transactional smoke test validated:

1. Candidate allocator is now canonical `WC-C-*` with no source conflict.
2. Persistent Finance gates are OFF by default.
3. Finance write operation is blocked when the gate is OFF.
4. Unbalanced Journal cannot be posted.
5. Balanced Journal posts and duplicate post is idempotent.
6. Posted Revenue appears correctly in internal P&L.
7. Revenue completed `EXPECTED → EARNED → INVOICED → COLLECTED` using matched Evidence + reconciled incoming Bank Transaction.
8. Related AR reconciled to derived `PAID` after collection.
9. Commission PAYABLE eligibility became true only after linked Revenue was `COLLECTED`.
10. Commission `PAID` remained unavailable through the Part 4E transition contract.
11. AP outstanding derivation worked.
12. Tax document register worked while tax-filing gate remained OFF.
13. All six Accounting Ledger monthly-close checks were represented.
14. `finance_control` could access Finance read APIs.
15. `content_studio` could not access Finance APIs.
16. Authenticated clients had no direct Finance table SELECT.
17. Journal/AR/AP/Tax allocators were exercised inside the test transaction.
18. Smoke transaction rolled back completely and consumed no real IDs.

## Post-test state

Business/test rows after rollback:

- Revenue: 0
- Expense: 0
- Commission: 0
- Journal Batch/Line: 0
- AR: 0
- AP: 0
- Bank Transaction: 0
- Tax Document: 0
- Monthly Close: 0
- synthetic Auth users: 0

Allocator values remain unchanged after the test.

## Safety gates — remain OFF

- `finance_write_enabled = false`
- `finance_posting_enabled = false`
- `finance_collection_state_enabled = false`
- `finance_commission_state_enabled = false`
- `finance_external_payment_execution_enabled = false`
- `finance_tax_filing_enabled = false`
- `business_master_apply_enabled = false`
- `production_cutover_approved = false`
- `current_operational_source = GOOGLE_SHEETS_DRIVE`

## Security / Performance validation

- Supabase Security Advisor: **PASS / 0 lint**
- all missing-FK-index findings introduced by the Finance schema were fixed
- remaining Performance notices are `unused_index` INFO only in the low/no-traffic TEST environment

## Boundary after 4E

The Finance/Accounting data model and controlled collection/ledger foundations are implemented, but PostgreSQL is still not the operational Source of Truth and no real payment execution is enabled.

Next safe implementation track: **Part 4F — Migration / Reconciliation Harness + Shadow Import/Compare from Google Sheets/Drive snapshots into PostgreSQL TEST**, without live writer cutover.
