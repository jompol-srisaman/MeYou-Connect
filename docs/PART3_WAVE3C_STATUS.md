# Part 3 Wave 3C — Scheduler Foundation Status

Status: **CLOSED / PASS**

Implemented in Supabase TEST:
- `ops.scheduled_signals`
- `ops.scheduler_runs`
- `ops.schedule_signal`
- `ops.cancel_schedule`
- Follow-up Due scheduler wrapper
- Invoice Due scheduler wrapper
- Notification scheduler wrapper
- Retry-due synchronization from `ops.events`
- idempotent scheduled event emission
- event context lookup for worker payload
- `finance.invoice.due` routing rule
- pg_cron scheduler tick every 5 minutes
- service-role-only scheduler grants

Smoke acceptance:
- duplicate Follow-up schedule resolves to one schedule
- Follow-up Due emitted once
- Invoice Due emitted once
- Retry Due emitted once
- future Notification does not emit early
- repeated scheduler tick does not duplicate events
- future Notification emits when eligible
- scheduled-event context preserves payload
- smoke data removed after test

Security:
- Supabase Security Advisor: PASS / no lint after Wave 3C
- anon/authenticated/public have no scheduler table/function access

Performance:
- covering FK index added for `scheduled_signals.event_type`
- remaining advisor notices are only expected `unused_index` INFO on a new no-traffic system

Important:
- This wave emits due/control events only. It does not send real notifications, create Finance Master records, or execute payments.
- Google Sheets + Google Drive remain current operational Source of Truth until approved cutover.
