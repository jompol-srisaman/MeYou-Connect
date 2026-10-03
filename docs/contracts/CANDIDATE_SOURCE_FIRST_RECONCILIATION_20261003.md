# Candidate Source-First Reconciliation — Live Closeout 2026-10-03

Status: LIVE TEST / CONTINUE STATE  
Operational SoT: `MEYOU_CONNECT_MVP_DATA_HUB_V1`  
Supabase: `pgjmxdeafzogzsyawejs`  
Branch: `data/unified-intake-readiness`

## Canonical ownership rule

Candidate ownership follows the first valid submitter/recommender evidenced in the primary LINE operational groups after identity/dedupe checks.

Founder-name / forwarding labels are routing context only. They must never assign Candidate ownership, direct commission, or overwrite an earlier valid Partner source.

Raw history is preserved for audit; operational attribution is derived from the first valid source evidence.

## Live state observed

Google Data Hub `01_Candidate`:
- 216 materialized rows
- highest Candidate ID: `MYC-C-000217`
- one historical reserved-ID gap is intentionally preserved rather than reused
- no duplicate phone was observed in the canonical materialized rows during the latest audit

Tracking `24_Candidate_Tracking`:
- 185 operational tracking rows
- 167 `MASTER_LINKED`
- 16 `SYNCED`
- 1 `DUPLICATE_LINKED`
- 1 `HOLD_NAME_MISSING`

Finance-related canonical rows now present:
- `05_Placement`: 10
- `10_Commission`: 16

Supabase shadow allocators were reconciled upward to:
- Candidate next = 218; last = `MYC-C-000217`
- Activity next = 37; last = `MYC-ACT-000036`
- conflict status = NONE

## Parser / source attribution acceptance

Representative live parser checks now resolve:
- explicit Yoke source -> `MYC-P-0003`
- explicit Eve source -> `MYC-P-0002`
- explicit Best source -> `MYC-P-0008`
- explicit Mint source -> `MYC-P-0001`
- Founder-routing-only source -> Partner NULL / HOLD
- Inaba forms -> Job `MYC-J-000017`
- candidate names are normalized so form labels do not become names
- common phone formatting is normalized
- source-first rules do not convert routing aliases into Mint ownership

Important live migrations include the source-first/parser/allocator series from:
- `20261003053904_fix_line_candidate_source_first_alias_attribution_v2`
through
- `20261003075608_link_c211_c217_source_first_raws_v1`

## Active Data Hub defect — C211..C217 column alignment

Seven rows currently have a one-column shift beginning at Source/Partner fields.

Observed current layout:
- Source = blank
- Partner ID = `Sourcing Partner`
- Status = `MYC-P-0001`
- Last Contact = `SCREENING`
- Next Action = blank
- Consent Job contains the intended Next Action
- Created At contains the intended Notes

This is a storage/layout defect, not a source-attribution decision.

Expected correction for `MYC-C-000211..000217`:
- Source = `Sourcing Partner`
- Partner ID = `MYC-P-0001`
- Status = `SCREENING`
- Last Contact = tracking/source timestamp
- Next Action = current operational next action
- Consent fields remain blank unless authoritative consent exists
- Notes = source-first provenance note
- Created At = original source/tracking timestamp
- Primary contact channel = `โทรศัพท์`
- C211 / C217 retain phone-quality DQ; do not guess the missing digit

If corrected, logical Partner distribution for the current 216 Candidate rows becomes:
- Mint `MYC-P-0001`: 95
- Eve `MYC-P-0002`: 26
- Yoke `MYC-P-0003`: 44
- Phae `MYC-P-0004`: 12
- Best `MYC-P-0008`: 36
- Wine `MYC-P-0009`: 3
- no operational Candidate owner should equal literal `Sourcing Partner`

## Remaining DQ

Keep evidence-based HOLD where identity is not provable:
- source record with missing Candidate name remains unresolved
- two materialized Candidate records retain 9-digit source phones and require correction from source evidence
- same-name / conflicting-phone identity history must not create a duplicate Candidate without evidence

## Tool boundary encountered

A direct Google Sheets administrative repair of the seven shifted rows was attempted through the connected Drive action, but the action was blocked by the platform safety gate. No bypass was attempted.

Engineering must perform the exact row-alignment repair through the approved writer/runtime or an authorized human edit. Do not use a second Raw→Master path and do not change ownership semantics during the correction.

## Acceptance after row repair

Re-read:
1. `01_Candidate` columns Source/Partner/Status/Consent/Notes for C211..C217
2. Partner formula counts
3. Tracking Candidate IDs/source ownership
4. Placement/Commission Candidate→Partner consistency
5. Supabase allocator parity
6. DQ31 phone/name holds
7. authoritative consent remains fail-closed unless evidence exists
