# MeYou Connect — Official Operational Read Contract V1

Status: `P0 / TEST / READY_FOR_ENGINEERING_BIND_WITH_BLOCKERS`

Owner: DATA & AI SYSTEM MANAGER  
Related: #2, #14, #18, #19  
Operational business Source of Truth: `GOOGLE_SHEETS_DRIVE` / `MEYOU_CONNECT_MVP_DATA_HUB_V1` (`1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc`)  
Technical Raw/Event/Health source: Supabase TEST `pgjmxdeafzogzsyawejs`

## 1. Non-negotiable boundary

This contract is a read composition boundary. It does not create a new business Master, does not create a second Raw→Master path, and does not cut over Source of Truth.

Business master domains remain authoritative in Google Data Hub until a separately approved migration/reconciliation/cutover:
- Candidate → `01_Candidate`
- Job → `02_งาน_Job`
- Client → `03_Client`
- Partner → `04_Partner`
- Founder Today / Need My Action → `00_งานวันนี้_Inbox` plus approved business-domain reads and follow-up/DQ signals
- Business DQ → `21_Data_Quality_Queue`

Supabase is authoritative only for its technical surfaces in this phase:
- LINE Raw / Inbox projection
- Event / command / retry state
- technical DQ records
- worker/scheduler/operations health
- verified cross-system master-effect evidence

PWA/UI MUST NOT fall back to `core.candidates`, `core.jobs`, `core.clients`, or `core.partners` as business truth. During the 2026-09-14 audit all four tables contained 0 rows.

## 2. Exact server-side interfaces

PWA calls one versioned server boundary only. Browser components must not call Sheets or Supabase tables/views directly.

| Interface | HTTP route | Authority | Canonical source |
|---|---|---|---|
| Founder Today / Need My Action | `GET /api/v1/read/founder/today` | `COMPOSITE_GOVERNED` | Data Hub operational tabs + approved technical warnings |
| Candidate list | `GET /api/v1/read/candidates` | `GOOGLE_SHEETS_DRIVE` | `01_Candidate`, guarded by `ops.candidate_promotion_gap_v` |
| Candidate detail | `GET /api/v1/read/candidates/:candidateId` | `GOOGLE_SHEETS_DRIVE` | `01_Candidate` |
| Job list/detail | `GET /api/v1/read/jobs[/:jobId]` | `GOOGLE_SHEETS_DRIVE` | `02_งาน_Job` |
| Client list/detail | `GET /api/v1/read/clients[/:clientId]` | `GOOGLE_SHEETS_DRIVE` | `03_Client` |
| Partner list/detail | `GET /api/v1/read/partners[/:partnerId]` | `GOOGLE_SHEETS_DRIVE` | `04_Partner` |
| LINE / Inbox Raw | `GET /api/v1/read/inbox/line` | `SUPABASE_TECHNICAL` | `ops.line_inbox_v` |
| DQ | `GET /api/v1/read/dq` | `COMPOSITE_GOVERNED` | Data Hub `21_Data_Quality_Queue` + `ops.data_quality_issues` |
| System / Freshness / Worker Health | `GET /api/v1/read/system/health` | `SUPABASE_TECHNICAL` | `ops.operations_health_v`, `ops.worker_health_v`, `ops.worker_backlog_v`, promotion-gap guard |

`COMPOSITE_GOVERNED` means the composition is fixed by this contract. It does not permit a caller to choose arbitrary sources.

## 3. Common envelope

Every interface response and every record must carry provenance/readiness metadata.

```ts
export type Readiness =
  | "READY"
  | "PARTIAL"
  | "STALE"
  | "NOT_READY"
  | "BLOCKED";

export type FreshnessState = "FRESH" | "STALE" | "UNKNOWN";

export type SourceAuthority =
  | "GOOGLE_SHEETS_DRIVE"
  | "SUPABASE_TECHNICAL"
  | "COMPOSITE_GOVERNED";

export interface FreshnessV1 {
  state: FreshnessState;
  observed_at: string | null;
  age_seconds: number | null;
  max_age_seconds: number;
  reason?: string;
}

export interface ReadMetaV1 {
  canonical_id: string;
  source_authority: SourceAuthority;
  source_ref: string;
  updated_at: string | null;
  freshness: FreshnessV1;
  readiness: Readiness;
  reason_code?: string;
}

export interface ReadRecordV1<T> extends ReadMetaV1 {
  data: T;
}

export interface ReadEnvelopeV1<T> extends ReadMetaV1 {
  contract_version: "v1";
  interface_key: string;
  generated_at: string;
  data: T | null;
  warnings: Array<{
    code: string;
    message: string;
    canonical_id?: string;
    count?: number;
  }>;
}
```

For persisted business/technical records, `canonical_id` is the real MYC ID (`MYC-C-*`, `MYC-J-*`, `MYC-B2B-*`, `MYC-P-*`, `MYC-RAW-*`, `MYC-DQ-*`, etc.).

For aggregate/read-interface envelopes, use a non-persisted read key such as `READ:v1:founder.today` or `SYSTEM:operations`. These keys are NOT business IDs and must never enter the ID allocator.

## 4. Readiness semantics

- `READY`: authoritative source read succeeded, source freshness is inside the contract window, and no known completeness guard blocks the result.
- `PARTIAL`: aggregate interface can safely return a useful subset, but at least one governed dependency is unavailable/not ready. The missing dependency must be named in `warnings`.
- `STALE`: source read succeeded but the result cannot be claimed complete/current because the freshness window is exceeded or a known downstream verification gap exists. Data may be displayed with a visible stale warning; completeness-dependent actions must be blocked.
- `NOT_READY`: required authoritative source cannot be read, required provenance is unresolved, or the result would otherwise create a false impression of completeness. `data=null` or an explicitly partial safe object; never convert this to an empty list/zero silently.
- `BLOCKED`: policy, permission, consent, or security boundary forbids the read.

No interface may silently convert `NOT_READY` to `[]`, `{}`, `0`, or a Supabase business-master fallback.

## 5. Freshness rules

Freshness is based on last successful source observation, not merely on how old a legitimate unchanged business record is.

| Surface | `max_age_seconds` | Rule |
|---|---:|---|
| Google Data Hub business reads | 300 | Last successful server-side Sheets read must be <=5 min old; record `updated_at` is separately reported when the source provides it. |
| LINE Inbox Raw | 300 | Latest successful Supabase read <=5 min. |
| Operations/worker health | 600 | <=10 min because canonical scheduler runs every 5 min; >10 min => `STALE`. |
| Technical DQ/gap guard | 300 | <=5 min. |
| Founder Today aggregate | 300 | Overall readiness is the worst safe state of required dependencies; optional sections may produce `PARTIAL`. |

If a Data Hub row/tab lacks a trustworthy update timestamp, `updated_at=null` and source observation still determines freshness. The adapter must not invent an update time.

## 6. Candidate completeness guard

Candidate reads have an additional safety rule because `MYC-DQ-000011` identified Raw→Candidate/Data Hub promotion/reconciliation gaps.

Supabase migration `20260914062852_p0_official_read_candidate_promotion_gap_v1` adds read-only `ops.candidate_promotion_gap_v`.

The view identifies LINE text records that either:
- are classified `CANDIDATE_LEAD`, or
- contain parsed Candidate shape with at least full name + phone,

and reports whether there is verified `operational_master_effect` / Candidate linkage.

PWA Candidate rule:

```text
Drive source unavailable
  => Candidate = NOT_READY

Drive source readable AND unverified candidate-shaped Raw count > 0
  => Candidate = STALE
  => warning code UNPROMOTED_RAW_GAP
  => show Data Hub records only with visible completeness warning
  => block completeness-dependent actions/count claims

Drive source readable AND unverified count = 0
  => Candidate = READY (subject to normal freshness)
```

This guard does not assert that every unverified Raw record is absent from Data Hub. It asserts that the system lacks verified linkage and therefore cannot claim completeness.

Audit snapshot 2026-09-14:
- candidate-shaped LINE Raw: 70
- verified operational Master Effect linkage: 3
- no verified linkage: 67
- newest unverified candidate-shaped Raw: `2026-09-14T06:08:22.403777Z`

Latest examples include `MYC-RAW-000912` and `MYC-RAW-000911`, both parsed with candidate shape but classified `CONTEXT_OR_OTHER`, no candidate command, and no verified operational Candidate linkage.

## 7. Field mapping V1

Header resolution MUST be centralized in the Data Hub adapter and MUST use header names/approved aliases, not hard-coded column positions. Current Drive runtime access was unavailable during this audit, so headers not directly verified on 2026-09-14 must remain alias-mapped and fail `NOT_READY` when a required header is missing rather than guessing.

### Candidate — `01_Candidate`

| Contract field | Canonical business field |
|---|---|
| `canonical_id` | Candidate ID |
| `display_name` | Name / Nickname |
| `province` | Province |
| `current_location` | Current Location |
| `age` | Age |
| `education` | Education |
| `experience` | Experience |
| `preferred_job` | Preferred Job |
| `expected_income` | Expected Income |
| `shift_preference` | Shift Preference |
| `relocation_ready` | Ready to Relocate? |
| `ready_date` | Ready Date |
| `has_vehicle` | Has Vehicle? |
| `dorm_needed` | Needs Dorm? |
| `dorm_budget` | Dorm Budget |
| `documents_ready` | Documents Ready? |
| `medical_ready` | Medical Ready? |
| `source_type` | Source |
| `partner_id` | Sourcing Partner ID |
| `status` | Current Status |
| `last_contact` | Last Contact |
| `next_action` | Next Action |
| `consent_status` | Consent Status |
| `notes` | Notes |
| `updated_at` | Updated At when present, otherwise null |

PII such as phone/LINE should be detail-only and permission-scoped, not required for the default list surface.

### Job — `02_งาน_Job`

| Contract field | Canonical business field |
|---|---|
| `canonical_id` | Job ID |
| `client_id` / `client` | Client |
| `company` | Company |
| `location` | Location |
| `position` | Position |
| `headcount` | Headcount |
| `wage` | Wage |
| `ot` | OT |
| `shift` | Shift |
| `benefits` | Benefits |
| `required_qualification` | Required Qualification |
| `documents` | Documents |
| `medical_requirement` | Medical Requirement |
| `dorm_available` | Dorm Available? |
| `transport_available` | Transport Available? |
| `start_date` | Start Date |
| `application_date` | Application Date |
| `rate_card` | Rate Card |
| `milestone` | Milestone |
| `payment_term` | Payment Term |
| `contact_person` | Contact Person |
| `status` | Active/Closed or canonical Job status |
| `updated_at` | Updated At when present, otherwise null |

### Client — `03_Client`

V1 PWA surface uses the canonical Client identifiers/operational fields already represented by the system model: `canonical_id`, `client_type`, `company_name`, `province`, `area`, `crm_status`, `payment_term`, `billing_cycle`, `verification_status`, `updated_at`. Data Hub remains authority; Supabase `core.clients` is not a fallback.

### Partner — `04_Partner`

V1 PWA surface: `canonical_id`, `partner_name`, `partner_type`, `province`, `parent_partner_id`, `status`, `started_at`, `updated_at`. Attribution/evidence detail must remain traceable and permission-scoped.

### LINE Inbox — `ops.line_inbox_v`

| Contract field | Source column |
|---|---|
| `canonical_id` | `raw_input_id` |
| `source` | `inbox_source` |
| `direction` | `direction` |
| `occurred_at` | `occurred_at` |
| `received_at` | `received_at` |
| `thread_id` | `thread_id` |
| `thread_name` | `thread_display_name` |
| `sender_ref` | `sender_ref` |
| `sender_name` | `sender_display_name` |
| `linked_entity_type` | `linked_entity_type` |
| `linked_entity_id` | `linked_entity_id` |
| `identity_status` | `identity_status` |
| `content_type` | `content_type` |
| `processing_status` | `processing_status` |
| `attachment_status` | `attachment_status` |
| `attachment_filename` | `attachment_filename` |
| `needs_identity_link` | `needs_identity_link` |
| `updated_at` | `received_at` for envelope record observation; Raw table `updated_at` may be used in detail adapter |

`raw_summary` is permission-sensitive. Founder internal detail may return it; list views should minimize/redact where possible.

### DQ

Business DQ records from Data Hub `21_Data_Quality_Queue` keep their `MYC-DQ-*` canonical ID and `GOOGLE_SHEETS_DRIVE` authority. Supabase `ops.data_quality_issues` records keep their own `MYC-DQ-*` ID and `SUPABASE_TECHNICAL` authority. The endpoint may return both, but every row names its authority; one source never overwrites the other.

### System health

- operations record: `canonical_id = SYSTEM:operations`
- worker record: `canonical_id = SYSTEM:worker:<worker_key>`
- backlog record: `canonical_id = SYSTEM:backlog:<worker_key>`
- promotion guard record: canonical `MYC-RAW-*`

These `SYSTEM:*` values are non-persisted read keys, not business IDs.

## 8. LINE / Raw / Inbox audit result

Observed 2026-09-14 in Supabase TEST:
- Raw rows: 906
- latest Raw observed: `MYC-RAW-000915` at `2026-09-14T06:20:56.304819Z`
- thread/source/sender linkage is populated in `ops.line_inbox_v`
- latest records commonly have `identity_status=UNVERIFIED`, `linked_entity_id=null`, `needs_identity_link=true`
- image Raw `MYC-RAW-000888` has `attachment_status=MIRRORED` and a mirrored attachment filename
- current recent Raw processing is `RAW_STORED`
- candidate parser/routing is active but recent candidate-shaped records can remain `CONTEXT_OR_OTHER`; this is exposed by the promotion-gap guard rather than hidden

Inbox is therefore safe to bind read-only now, provided UI surfaces identity/link readiness per record and does not imply unverified entity attribution.

## 9. Worker / retry / health audit result

Observed operations health:
- total events: 909
- completed events: 909
- ready events: 0
- retry-wait events: 0
- approval-required events: 0
- DQ-hold events: 0
- dead-letter events: 0
- ready domain commands: 3
- heartbeat instances: 1
- stale heartbeat instances: 0
- scheduler: active every 5 minutes (`*/5 * * * *`)

`candidate_intake` heartbeat was `HEALTHY` in TEST (`db_scheduler`, version `line-ingestion-v1`). Most other registered workers currently report `NOT_STARTED`; PWA must show `NOT_STARTED`, not green/healthy.

## 10. Sample read results

### Candidate list guard during current audit

```json
{
  "contract_version": "v1",
  "interface_key": "candidate.list",
  "canonical_id": "READ:v1:candidate.list",
  "source_authority": "GOOGLE_SHEETS_DRIVE",
  "source_ref": "MEYOU_CONNECT_MVP_DATA_HUB_V1/01_Candidate",
  "updated_at": null,
  "freshness": {
    "state": "UNKNOWN",
    "observed_at": null,
    "age_seconds": null,
    "max_age_seconds": 300,
    "reason": "Google Drive runtime unavailable during audit"
  },
  "readiness": "NOT_READY",
  "reason_code": "AUTHORITATIVE_SOURCE_UNAVAILABLE",
  "generated_at": "2026-09-14T06:29:00Z",
  "data": null,
  "warnings": [
    {
      "code": "UNPROMOTED_RAW_GAP",
      "message": "Candidate completeness cannot be verified against 67 candidate-shaped LINE Raw records without verified operational Master Effect linkage.",
      "count": 67
    }
  ]
}
```

Once server-side Sheets auth is connected and the Data Hub read succeeds, this interface may return Data Hub rows but remains `STALE` while the unverified gap count is non-zero.

### LINE Inbox record

```json
{
  "canonical_id": "MYC-RAW-000915",
  "source_authority": "SUPABASE_TECHNICAL",
  "source_ref": "ops.line_inbox_v",
  "updated_at": "2026-09-14T06:20:56.304819Z",
  "freshness": { "state": "FRESH", "observed_at": "2026-09-14T06:24:27Z", "age_seconds": 211, "max_age_seconds": 300 },
  "readiness": "PARTIAL",
  "reason_code": "ENTITY_IDENTITY_UNVERIFIED",
  "data": {
    "source": "DATA_BOT",
    "direction": "INBOUND",
    "thread_name": "กลุ่มสรรหา",
    "sender_name": "ปลายทาง",
    "content_type": "LINE_TEXT",
    "processing_status": "RAW_STORED",
    "linked_entity_id": null,
    "identity_status": "UNVERIFIED",
    "needs_identity_link": true
  }
}
```

### System operations health

```json
{
  "canonical_id": "SYSTEM:operations",
  "source_authority": "SUPABASE_TECHNICAL",
  "source_ref": "ops.operations_health_v",
  "updated_at": "2026-09-14T06:24:27.230892Z",
  "readiness": "READY",
  "data": {
    "total_events": 909,
    "completed_events": 909,
    "ready_events": 0,
    "retry_wait_events": 0,
    "dead_letter_events": 0,
    "ready_domain_commands": 3,
    "heartbeat_instances": 1,
    "stale_heartbeat_instances": 0
  }
}
```

## 11. PWA server adapter contract

Reference implementation boundary:

```ts
export interface OfficialReadProviderV1<TQuery, TResult> {
  readonly version: "v1";
  readonly interfaceKey: string;
  readonly authority: SourceAuthority;
  read(query: TQuery, context: ReadContextV1): Promise<ReadEnvelopeV1<TResult>>;
}

export interface ReadContextV1 {
  actor_id: string;
  roles: string[];
  request_id: string;
  now: string;
}
```

Engineering implementation recommendation:

```text
app/api/v1/read/...          Next.js server routes only
lib/data/v1/contracts.ts     exact envelope types
lib/data/v1/registry.ts      interfaceKey -> approved provider
lib/data/v1/google-datahub.ts authoritative business adapter
lib/data/v1/supabase-tech.ts technical adapter
lib/data/v1/readiness.ts     freshness / readiness / gap rules
```

Module code requests interface keys; it does not import another module's tables or source adapter directly. Future modules (Finance, Transport, Dorm, Payroll, Accounting, Content, AI) register new V1/V2 providers behind the same boundary.

Version rules:
- additive optional fields are backward-compatible within V1;
- removing/renaming/changing meaning of required fields requires V2;
- V1 routes remain available during V2 migration until dependent modules are moved;
- source swaps are implementation changes only after an approved SoT cutover and must preserve contract semantics.

## 12. Safe write boundary

This contract is read-only. Future PWA writes MUST use:

```text
UI Command
→ Server Command Endpoint
→ Validate
→ Permission / Step-up / Consent check
→ Canonical Event
→ Existing Worker / Domain Command
→ Controlled Master Effect
→ Evidence / Audit
```

No UI direct write to Data Hub Master, Supabase protected Master, or technical Raw tables. Offline PWA may queue proposals only; it must revalidate online before any material effect.

## 13. Engineering integration prerequisites

1. Server-side Google Sheets credentials for the private Data Hub. Preferred: dedicated Google service account / workload identity, Data Hub shared read-only to that identity. Do not expose credentials to browser code.
2. Vercel server environment must contain Google read credentials and Supabase server credentials; secrets must not be committed.
3. Live Data Hub headers for required V1 tabs must be read once and locked into central header aliases. Missing required headers => `NOT_READY`, never positional guessing.
4. PWA must call `/api/v1/read/**` only; no direct Sheets/Supabase business reads from components.
5. Service worker must continue to exclude `/api/**` from cache in PWA V0.1.
6. Candidate adapter must query `ops.candidate_promotion_gap_v` and apply the completeness guard.
7. Inbox adapter must expose identity/link readiness and attachment status without guessing entity identity.
8. System page must distinguish `HEALTHY`, `STALE`, and `NOT_STARTED` worker states.
9. Authentication/authorization must run server-side before sensitive Candidate/Inbox detail fields are returned.
10. No Production cutover is authorized by this document.

## 14. Dispatcher bind status

- `LINE / Inbox Raw`: **READY_TO_BIND_READ_ONLY**
- `System / Freshness / Worker Health`: **READY_TO_BIND_READ_ONLY**
- `Candidate`: **CONTRACT_READY / DATA_COMPLETENESS_GUARDED**; Data Hub server auth required and 67 unverified Raw→Master linkages currently prevent a complete/READY claim
- `Job`: **CONTRACT_READY / NEEDS_DATAHUB_SERVER_ADAPTER**
- `Client`: **CONTRACT_READY / NEEDS_DATAHUB_SERVER_ADAPTER**
- `Partner`: **CONTRACT_READY / NEEDS_DATAHUB_SERVER_ADAPTER**
- `DQ`: **CONTRACT_READY / PARTIAL_BIND**; Supabase technical DQ can bind now, Data Hub business DQ requires Data Hub server adapter
- `Founder Today / Need My Action`: **CONTRACT_READY / PARTIAL_BIND**; technical alerts can bind now, complete operational view waits on Data Hub server adapter

## 15. Current blockers

1. Google Drive MCP/runtime was unavailable during the 2026-09-14 audit, so current live Data Hub row/header reconciliation could not be completed from this session. This does not authorize a Supabase fallback.
2. 67 candidate-shaped LINE Raw records currently lack verified operational Master Effect linkage in Supabase control/audit state. They may represent true promotion gaps, unreconciled Data Hub effects, or both; they require Data Hub reconciliation, not guessing.
3. Recent candidate-shaped Raw can remain `CONTEXT_OR_OTHER` because the current v1.1 parser is still narrow/job-specific. This is a Unified AI Intake follow-up under #14; the read contract guards against silent omission now.
4. Most worker contracts remain `NOT_STARTED`; only actually heartbeating workers may be presented as healthy.

## 16. Acceptance / safety evidence

- migration applied in TEST only: `20260914062852 p0_official_read_candidate_promotion_gap_v1`
- security advisor after DDL: 0 findings
- performance advisor: informational pre-existing unused-index notices only; no new blocking finding from this read view
- view grants: `service_role` SELECT only; `anon` / `authenticated` revoked
- no business Master write performed
- no Raw→Master pipeline added
- no SoT change
- no Production cutover
