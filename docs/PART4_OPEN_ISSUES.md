# Part 4 — Open Issues / Production-only Evidence

Status: TEST IMPLEMENTATION CLOSED ONLY AFTER PART 4H FINAL EVALUATION

This file intentionally lists what remains **not proven** by the Part 4 TEST implementation. These items are not architecture redesign requests; they are Production-readiness evidence or operational execution tasks.

## Production blockers / evidence still required

1. **Founder Production cutover approval** — not granted by Part 4 implementation alone.
2. **Architect final review** — must review the actual Production cutover package and live source state.
3. **Fresh Part 2 backup** — must be created immediately before a real cutover.
4. **Persisted cutover rehearsal** — Part 4G smoke tests roll back; a real rehearsal record with source revisions/freeze/final backup must be retained before Production.
5. **Live reconciliation** — current Data Hub snapshot/delta must reconcile against the intended target at cutover time.
6. **File/object migration verification** — actual object copies require checksum/mapping evidence. Provider-neutral schema exists, but live bytes are not declared migrated by Part 4.
7. **Production-like RLS acceptance** — use named accounts and real role assignments, not only synthetic transactional users.
8. **Part 3 Production-like acceptance** — idempotency/retry/DLQ/approval behavior must be rerun in the deployment environment.
9. **Rollback rehearsal evidence** — prove the operational writer can return safely to Sheets/Drive while preserving DB-only effects for reconciliation.
10. **Named privileged identities + MFA/step-up** — configure where supported before privileged Production operations.
11. **Writer switch plan** — approve exact endpoint switch, freeze window, smoke-test owner and Sheets read-only fallback.
12. **Live external webhooks** — Facebook/LINE/other channels remain outside Part 4 TEST activation and need authenticated ingress controls before enabling.

## Deliberately deferred / trigger-based

- Cloudflare R2 migration is optional; Supabase Storage remains the default target unless scale/cost triggers justify R2.
- External portals and multi-province rollout follow Part 7 gates and are not prerequisites for Founder-stage internal operation.
- Analytics/data-mart optimization follows real data and measured query needs; it is not a reason to delay client/revenue operations.

## Non-issue: canonical business IDs

Current authority is aligned on `MYC-*` stable business IDs. Part 4G realigned the empty TEST database, allocator, constraints and migration map to that namespace. Old `WC-*` implementation references are stale and must not be reintroduced.

## Business priority reminder

Engineering closeout must not block Saraburi pilot/client acquisition. Production migration is a separate readiness decision, not a prerequisite for continuing to use the existing Google Sheets/Drive operating system.
