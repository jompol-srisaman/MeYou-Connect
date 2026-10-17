# MYC storage authority and capacity

Authority remains the existing MYC architecture. These controls do not promote PostgreSQL business masters or create an independent finance/partner authority.

| Data | Authority / live use | External storage and retention |
|---|---|---|
| Candidate, Partner, Job, Placement and designated business/finance fields | Existing designated Google Sheets; source-first partner attribution. PostgreSQL shadow is a derived searchable projection. | Existing business Sheet/version history and verified restricted exports. Conflicting or removed source rows require review. |
| Deduplicated channel intake, event identity, retry/DLQ, sync ledger, compact references | Existing Supabase operational contracts; channel/account/provider ID scopes the event. | Verified encrypted cold exports before any approved historical purge. Never turn a promise/emoji into finance evidence. |
| Financial evidence and lifecycle | Existing evidence-linked EXPECTED→EARNED→INVOICED→COLLECTED controls; no automatic entitlement/master cutover. | Separate finance/evidence retention, restricted originals and audited links. Do not apply disposable staging retention to finance. |
| Original images/files/evidence | Existing File Registry→Evidence→private object pointer and SHA256. MYC Drive can hold controlled large originals; existing private object storage remains supported. | Owner-restricted MYC Drive/private object store, checksum/readback and source reconciliation. No public links or deletion of unarchived/disputed evidence. Storage metadata alone is not an object backup. |
| Shadow snapshots/deltas | Supabase derived metadata; per-source baseline with only changed rows admitted. | Protect at least2 recent successful snapshots and7days of change history. Require verified archive before any separately scoped purge. Current20-hashed-session admission hold prevents uncontrolled accumulation; it does not authorize deleting the retained36,818rows. |
| Capacity metrics / operational alerts | Existing Supabase observability and recovery-monitor contracts; aggregate values only. | Planned15-minute samples, maximum2,016rows (21days). Stop optional sample append and alert for archive at the cap; no automatic evidence deletion. Alert occurrences throttle to six hours unless conditions change. |
| Disaster backup | Full consistent PostgreSQL snapshot plus separately accounted object bytes. | Client-side-encrypted archive outside affected Supabase, independent readback/restore; key recovery separately controlled from the archive account. |

## Measured footprint and projections

Live aggregate measurement17October01:58UTC: database149,482,643bytes (142.6MiB), Shadow61,054,976bytes (58.2MiB), Raw4,749rows. Raw relation including indexes13,885,440bytes; sync ledger3,252,224; events3,768,320; ingress log5,382,144. Raw mean stored row2,029bytes, mean summary114bytes. These are observed existing footprints, not a benchmark of newly arriving traffic.

Normalizing those four live relation footprints by4,749 Raw messages gives approximately5.3MiB per1,000messages /52.8MiB per10,000messages. This remains a planning extrapolation: historical events/logs are not exactly one row per message; compression, indexes, retries, message sizes and media rates change the result. Do not treat it as measured incremental growth or unlimited Free capacity.

### Isolated structured-row growth measurement

A bounded physical benchmark on 17 October used a fresh PostgreSQL 17.6 `template0` database inside the local restore container, with Docker network mode `none` and no published ports. It recreated only the actual `ops.raw_inputs`, `ops.events`, and `ops.raw_datahub_sync_ledger` definitions from a schema-only dump, including their six indexes, six primary/unique constraints, two foreign keys, four RLS policies, and `ops.event_processing_state` enum. No restored rows or business schemas were copied. Synthetic pairs had a random 2,048-byte payload in `metadata` and an exactly 114-byte ASCII summary; the harness directly inserted Raw, Event and sync-ledger rows and ran no workers or routing logic.

| Synthetic message pairs | PostgreSQL database growth | Raw relation growth | Events relation growth | Sync-ledger growth | Database growth per pair |
|---:|---:|---:|---:|---:|---:|
| 1,000 | 5,316,608 bytes | 4,005,888 bytes | 794,624 bytes | 516,096 bytes | 5,316.61 bytes (5.32 decimal kB; 5.19 KiB) |
| 10,000 | 51,019,776 bytes | 39,354,368 bytes | 7,102,464 bytes | 4,562,944 bytes | 5,101.98 bytes (5.10 decimal kB; 4.98 KiB) |

The 10,000-pair database delta is 48.66 MiB and includes table, index, TOAST, and per-database catalog allocation for this minimal three-table model. The result gives a measured storage estimate for the stated synthetic shape, not a forecast for production event mixes. It excludes WAL, worker/retry side effects, external media bytes, network/provider accounting, and business master tables. The marked benchmark database was dropped without `FORCE` or `CASCADE`; no recovered database data was changed. Aggregate evidence is stored privately at `C:\Users\HP\MYC-Recovery-Private\benchmark-result.json`.

File intake171items includes165 checksum-bearing mirrored objects and6 unresolved mirrors; known size metadata totals35,235,411bytes and the largest known file3,642,662bytes. Historical known media bytes normalize to about7.1MiB per1,000messages /70.8MiB per10,000messages, stored outside PostgreSQL. This uses historical size metadata; object bytes were not remeasured in the structured-row benchmark. Missing/unknown object sizes make this a lower-confidence estimate. Original object bytes were not exported by the logical PostgreSQL backup.

Controls use explicit binary units: database warning250MiB (262,144,000bytes), optional Shadow stop400MiB (419,430,400), Shadow relation stop75MiB (78,643,200). The75MiB cap leaves about16.8MiB above the measured retained Shadow baseline; the old50MiB cap could never admit that baseline. Provider quota uses its own accounting/units; stay conservatively below it rather than treating500MB as500MiB.

At the warning, inspect growth/backlog, stop unnecessary copies, verify external archives and prepare exact retention scope. At either stop, optional Shadow imports halt; preserve LINE capture and retry state where possible. Restore headroom before retrying. Reassess before another10,000messages or a media/channel expansion; use actual24-hour growth observations, not these extrapolations, for forecasts. A future capacity/plan migration requires a concrete Founder decision; no new project, paid API or architecture change is part of this recovery.
