# Data Hub Formula + Allocator Repair — 2026-10-03

Operational source: `MEYOU_CONNECT_MVP_DATA_HUB_V1`

## Repaired
- `00_งานวันนี้_Inbox`
  - removed `#REF!` spill collision
  - rebuilt Candidate / Follow-up / Invoice sections with bounded query ranges
  - corrected Finance labels to distinguish Canonical Master from evidence
- `11_Dashboard`
  - corrected D30 retention to D30/Started
  - corrected no-show metric to NO_SHOW/Appointed
  - changed finance status formulas to read canonical `08_Revenue` / `10_Commission`
  - added live Cash Evidence/Data Freshness KPIs from `22_Finance_Cashbook`, `01_Candidate`, `19_Raw_Input_Log`
- `98_System_Config`
  - reconciled stale next-ID / preview / last-ID values to actual Data Hub maxima
  - Raw Input caught up through `MYC-RAW-004120`
- Supabase shadow `config.id_allocators`
  - reconciled monotonically upward to Data Hub; no allocator moved backward
- `16_Activity_Log`
  - recorded repair as `MYC-ACT-000032`

## Verified live values after repair
- Candidate Master: 52 rows, latest `MYC-C-000052`
- Raw Input: latest `MYC-RAW-004120`
- Cashbook: 19 rows
- Cash receipts evidenced: THB 3,300
- Partner cash-out evidenced: THB 1,720
- TTB traced funding: THB 980 (not bank-statement balance)
- audited operational formula errors: 0

`05_Placement`, `08_Revenue`, and `10_Commission` remain canonical-empty because protected business Master effects have not been applied. They were not fabricated from Cashbook evidence. Dashboard now displays this distinction explicitly.
