# MeYou Connect — Business Event / Data Mapping V1

Status: TEST contract mapping; no operational Source-of-Truth cutover  
Event kernel: existing `ops.events` / existing Command-Event-Worker architecture  
Operational business Source of Truth: `GOOGLE_SHEETS_DRIVE / MEYOU_CONNECT_MVP_DATA_HUB_V1`

## Governing rule

This document maps accepted business semantics onto the existing architecture. It does not create a second event kernel, does not direct-write protected Master, and does not authorize an LLM effect.

## Candidate / matching semantics

Canonical Candidate Operations V1.1 separates:

- trusted per-record readiness;
- global Candidate inventory completeness/promotion guard;
- historical Source Partner attribution;
- current active submission route;
- stale dated-fact warnings;
- DQ/evidence state;
- Consent readiness.

Matching outcomes are canonical business outcomes:

- `MATCH`
- `POSSIBLE`
- `BLOCKED`
- `NEED_INFO`

They remain proposal/evaluation outcomes. No new event-type string is invented here because the current canonical material does not provide a locked event-name taxonomy for these four matching outcomes. Engineering must bind them to versioned event names only after the canonical event naming is approved. `Auto Matching != Auto Reject`.

Completeness-dependent actions remain blocked while `ops.candidate_promotion_gap_v` is nonzero. Trusted individual Data Hub Candidate records may still be evaluated per record, subject to verified Job requirements and Consent/action gates.

## Candidate lifecycle safety boundaries

From Candidate Operations V1.1:

- a stale Ready Date means reconfirm / `ACTION_DUE`, not automatic negative eligibility;
- an APPOINTED Candidate without current Placement/outcome evidence remains REVIEW; no inferred outcome;
- aggregate start reports without named Candidate/Placement evidence cannot mark a Candidate STARTED;
- pause evidence may produce a HOLD proposal only; it is not a direct status rewrite;
- inactive historical Source Partner does not rewrite lineage and does not globally block a Candidate.

Lifecycle proposals must continue through existing Command → Validate → Permission → Event → Controlled Effect / DQ.

## B2B response outcomes — existing implemented mapping

The existing `ops.b2b_response_event_map_v` is the canonical data-side mapping and is reused unchanged:

| Business outcome | Existing Event Kernel type |
| --- | --- |
| ACCEPTED | `b2b.response.accepted` |
| REJECTED | `b2b.response.rejected` |
| NEED_INFO | `b2b.response.need_info` |
| APPOINTMENT | `b2b.response.appointment` |
| SLOT_CLOSED | `b2b.response.slot_closed` |
| REQUIREMENT_CHANGED | `b2b.response.requirement_changed` |
| WAITING | `b2b.response.waiting` |

These are semantic mappings; they do not by themselves create a Client/Job/Placement Master effect.

## Finance state contracts — existing implemented mapping

Revenue uses the existing `finance.state_transition_rules` chain:

`EXPECTED → EARNED → INVOICED → COLLECTED`

Hard rule: **Only `COLLECTED` is cash.**

Commission uses the existing chain:

`PENDING → EARNED → WAITING_COLLECTION → PAYABLE → PAID`

Existing protected guards remain authoritative, including evidence/reconciliation requirements for protected collection/payment transitions. `PAID` records a payment that already occurred and was reconciled; it never executes a transfer.

Accepted Finance V1.0.1 additions are implemented in TEST as supporting contracts only:

- many-to-many inbound payment allocation bridge (`finance.payment_allocations`);
- Partner `ADVANCE | DEDUCTION | REIMBURSEMENT` evidence ledger (`finance.partner_adjustments` + applications);
- derived balance/allocation views;
- duplicate bank-reference detection view.

No Finance business fact was seeded by these schema changes. `finance_write_enabled = false` and `finance_external_payment_execution_enabled = false` remain unchanged.

## Placement → Finance event interpretation

Accepted Finance V1.0.1 semantics remain:

- `placement.submitted`: EXPECTED only if the approved deal/rate can resolve a priced amount;
- `placement.started`: evaluate approved deal milestones;
- `placement.milestone.observed`: may earn Revenue only when the specific approved deal maps that milestone;
- `placement.dropout`: reevaluate unearned EXPECTED only; never delete collected history;
- protected-state reversal: DQ/review.

Milestone labels such as D1/D3/D5/D7/D30 are event labels, not universal earning rules.

## Consent/action dependency

Any candidate submission/action contract must query authoritative `14_Consent_PDPA` through the server-side Consent Read Contract. Until a current evidence-backed consent is readable for the requested purpose:

`AUTO_SUBMIT = FALSE`

Ordinary conversation, application interest, image/file delivery, or past employment is not consent.

## Current implementation boundary

Safe Actions V0.2 remains **NOT ACTIVATED** because the Data Read Gate is still PARTIAL. The existing controlled command/event/effect architecture may be reused when the gate passes; no high-impact employment decision is authorized automatically by this document.
