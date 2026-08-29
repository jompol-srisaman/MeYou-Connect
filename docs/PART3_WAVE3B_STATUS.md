# Part 3 / Wave 3B — Founder / ChatGPT / File Ingestion

Status: IMPLEMENTED IN SUPABASE TEST

Implemented:
- Material-event ingestion with Raw Input provenance
- Deterministic event routing catalog
- Founder/ChatGPT source metadata fields
- File intake metadata + duplicate protection
- Manual replay request control
- Service-role-only execution boundary for ops functions/tables
- Ingestion/replay/file idempotency smoke test

Not implemented in Wave 3B:
- Candidate/Client/Finance master tables in Supabase
- Facebook/LINE production webhooks
- File bytes migration into final Evidence storage
- Production cutover from Google Sheets/Drive

Supabase migrations:
- part3_wave3b_ingestion_foundation
- part3_wave3b_ingestion_smoke

Security Advisor: PASS
Performance Advisor: only expected unused-index INFO on new/no-traffic indexes.
