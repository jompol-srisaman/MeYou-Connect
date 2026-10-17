# MYC capacity monitor operations — 17 October 2026

This runbook describes the existing source-side capacity collector, the native `myc-recovery` heartbeat, and the private offline HTML renderer. It does not authorize a new project, paid service, source-data purge, Cron #11 activation, or recovery PASS.

## Collection and observation window

The existing source Cron #3 job, `meyou-connect-observability-refresh`, runs its collector every five minutes. Capacity snapshot capture is rate-limited to one real sample per 15 minutes and reads numeric database and Shadow relation sizes plus aggregate alert/backlog state. Cron #11 (`myc_datahub_shadow_import_5min`) is separate and must remain inactive. Do not change either schedule to make the dashboard look fresher.

The native `myc-recovery` heartbeat initially ran every15minutes. A current configuration read found it changed at17October03:49UTC to daily09:00Bangkok; preserve the current configuration unless a schedule change is authorized. This is separate from sourceCron3's unchanged five-minute collector and does not establish continuous email delivery. On each actual run, read current aggregates and ordered source samples, refresh the privateJSON, render the dashboard and report meaningful action/completion. Do not reuse previousJSON as a current read. Failed/stale reads leave the observation incomplete; oldHTML is not current health evidence. A daily09:00check on18October is before the earliest24h boundary; never markPASS from that check without a later sufficiently fresh sample.

The first recorded capacity sample is **2026-10-17T02:13:59.664052Z** (**17 October 09:13:59 Bangkok time**). A complete 24-hour observation cannot be claimed before **18 October 09:14 Bangkok time**, and then only if real samples span at least 24 hours and the latest sample is fresh. The fifteen-minute minimum capture interval plus the five-minute collector cadence can produce actual gaps around twenty minutes; do not assert exactly97 points or a strict fifteen-minute maximum. Report actual first/last timestamps, sample count, every gap and maximum observed sizes; investigate gaps above25minutes or a latest sample older than25minutes before considering the window complete. Never interpolate, backfill, repeat a value, or create synthetic timestamps to fill missing samples. The dashboard draws only supplied real samples.

A 24-hour window is one acceptance gate, not a recovery PASS by itself. Preserve `recovery_status: "INCOMPLETE"` until the current source read and all independent recovery, delivery, media, finance, and guard gates meet their own acceptance criteria. Do not infer quota stability from PostgreSQL byte totals: provider accounting may use different units and retained objects.

## Input contract

Before rendering, refresh the JSON from current authorized, read-only source reads. Use the aggregate health RPC for the `metrics` object and separately approved aggregate queries for Raw/DataHub synchronization, unresolved media count, read-only setting, and actual monitor history. Do not include event text, row identifiers, addresses, email recipients, credentials, object URLs, provider destinations, or any other person-level data.

The private input file must have this exact top-level shape:

| Field | Required contents |
|---|---|
| `metrics` | The current `ops.capacity_guard_metrics()` aggregate object. The renderer uses `sampled_at`, `database_bytes`, `shadow_relation_bytes`, `open_shadow_sessions`, `staged_shadow_sessions`, `open_alerts`, `active_capacity_alerts`, `held_deliveries`, `ready_deliveries`, `verified_active_external_routes`, `external_delivery_enabled`, `migration_shadow_write_enabled`, `business_master_apply_enabled`, `migration_target_apply_enabled`, `production_cutover_approved`, `cron11_active`, `capacity_samples_24h`, `capacity_samples_retained`, `capacity_sample_limit`, and `capacity_history_full`. Include only values read from source. |
| `samples` | An ascending array of actual source samples, each with `sampled_at`, `database_bytes`, and `shadow_relation_bytes`. Use `[]` only when the source has no samples. Do not generate a chart series locally. |
| `raw_sync` | Numeric aggregate counts with exactly these keys: `raw`, `ledger`, `synced`, `pending`, `retry`, `dead_letter`, `in_flight`. |
| `media_missing` | Current aggregate count of unresolved media mirrors; last verified count is 6, but re-read it for every current report. |
| `readonly` | The current source setting as the exact string `"on"` or `"off"`. |
| `recovery_status` | Current recovery decision, `"INCOMPLETE"` unless all required current gates pass. |

The renderer validates nonnegative numeric counts/bytes, timestamps, state enums, and all required fields. If validation or rendering fails, do not treat an older HTML file as a current report. The renderer ignores unapproved payload fields and writes no source data to stdout; stdout contains only the output path and aggregate sample/field counts.

## Render the private dashboard

On the authorized local Windows workstation, save the freshly collected aggregate JSON under the private recovery directory. Then run:

```powershell
$inputPath = 'C:\Users\HP\MYC-Recovery-Private\capacity-health-latest.json'
$outputPath = 'C:\Users\HP\MYC-Recovery-Private\capacity-health.html'
node .\scripts\render-capacity-dashboard.mjs --input $inputPath --output $outputPath
```

Open the generated HTML locally in Codex or a browser. It is self-contained and uses inline CSS/SVG; it makes no network request and has no action buttons. The database bars show binary MiB warning250 and stop400 thresholds plus the provider's separate decimal500MB reference. Shadow stops at75MiB. The sample graph shows only the supplied real points. The page links to draft PR #29 for the active recovery work.

Never put the private JSON or rendered HTML in the repository, commit, issue, or public share. The aggregate renderer does not encrypt the private files; keep them in the existing access-restricted recovery directory and follow its local retention rules.

## Alert delivery and escalation

The dashboard reports queue state; it does not send mail. Current delivery still depends on the approved local application/worker and its existing authorization. If that app is offline, processing or mail delivery may wait until it is running again; a queued row is not a delivered alert. When validating the Gmail queue, use only the owner's own address as recipient and require the sent/receipt readback before recording delivery PASS. Do not add other recipients or include Raw content, media links, credentials, or provider destinations in the alert.

At database warning250MiB, inspect real growth, queues, external backup status, and the current provider quota. At database stop400MiB or Shadow stop75MiB, optional Shadow import must halt under the existing guard. Preserve intake, retry and dead-letter state. Escalate with the exact source sample time and aggregate values; do not delete evidence or treat a private restore/benchmark as a source change.

## Evidence and current status

- Capacity history began at **2026-10-17T02:13:59.664052Z**. Earliest possible complete 24-hour window: **18 October 2026, 09:14 Bangkok time**, subject to real cadence, freshness, and gap checks.
- Current media mirror gap is **6** and must be re-read before each status report.
- The recovery dashboard should currently show **INCOMPLETE** until current source evidence and every required independent gate establish otherwise.
- The structured-row benchmark is documented in [MYC storage authority and capacity](MYC_STORAGE_AUTHORITY_CAPACITY_20261017.md). It uses a private isolated synthetic model and is not a source database measurement or production event forecast.
