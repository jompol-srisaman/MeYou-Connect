import {
  OFFICIAL_READ_FRESHNESS_SECONDS,
  type CandidateInventoryCompletenessV1,
  type FreshnessV1,
  type ReadEnvelopeV1,
  type ReadRecordV1,
  type Readiness,
  type ReadWarningV1,
  type SourceAuthority,
} from "@/lib/platform/contracts";
import { mapDataHubRows, MissingRequiredHeaderError, type DataHubDomain } from "@/lib/data/header-aliases";
import { readDataHubRange, readSupabaseOps, SourceReadError } from "@/lib/data/source-clients";

const HUB = {
  candidate: ["01_Candidate", "A1:AI5000"],
  job: ["02_งาน_Job", "A1:AD3000"],
  client: ["03_Client", "A1:X1000"],
  partner: ["04_Partner", "A1:T2000"],
  dq: ["21_Data_Quality_Queue", "A1:T5000"],
  founderToday: ["00_งานวันนี้_Inbox", "A2:C1002"],
} as const;

type HubDomain = keyof typeof HUB;
type Row = Record<string, unknown>;
type GapRow = { readiness: string | null; gap_state: string | null; raw_input_id?: string | null; received_at?: string | null };

const now = () => new Date().toISOString();
const str = (v: unknown) => v === null || v === undefined || v === "" ? null : String(v);
const scalar = (v: unknown) => v === null || v === undefined || v === "" ? null : typeof v === "number" ? v : String(v);

function iso(v: unknown) {
  const raw = str(v);
  if (!raw) return null;
  const parsed = Date.parse(/[+-]\d{2}$/.test(raw) ? `${raw}:00` : raw);
  return Number.isNaN(parsed) ? null : new Date(parsed).toISOString();
}

function freshness(observedAt: string | null, maxAgeSeconds: number): FreshnessV1 {
  if (!observedAt) return { state: "UNKNOWN", observed_at: null, age_seconds: null, max_age_seconds: maxAgeSeconds };
  const age = Math.max(0, Math.floor((Date.now() - Date.parse(observedAt)) / 1000));
  return { state: age > maxAgeSeconds ? "STALE" : "FRESH", observed_at: observedAt, age_seconds: age, max_age_seconds: maxAgeSeconds };
}

function envelope<T>(a: {
  interfaceKey: string; canonicalId: string; authority: SourceAuthority; sourceRef: string;
  observedAt: string | null; maxAgeSeconds: number; readiness: Readiness; data: T | null;
  updatedAt?: string | null; reasonCode?: string; warnings?: ReadWarningV1[];
  candidateInventoryCompleteness?: CandidateInventoryCompletenessV1;
}): ReadEnvelopeV1<T> {
  const f = freshness(a.observedAt, a.maxAgeSeconds);
  const readiness = f.state === "STALE" && a.readiness === "READY" ? "STALE" : a.readiness;
  return {
    contract_version: "v1", interface_key: a.interfaceKey, generated_at: now(),
    canonical_id: a.canonicalId, source_authority: a.authority, source_ref: a.sourceRef,
    updated_at: a.updatedAt ?? null, freshness: f, readiness,
    ...(a.reasonCode ? { reason_code: a.reasonCode } : {}), data: a.data,
    ...(a.candidateInventoryCompleteness ? { candidate_inventory_completeness: a.candidateInventoryCompleteness } : {}),
    warnings: a.warnings ?? [],
  };
}

function reason(error: unknown) {
  if (error instanceof SourceReadError) return error.reasonCode;
  if (error instanceof MissingRequiredHeaderError) return "DATA_HUB_REQUIRED_HEADER_MISSING";
  return "READ_SOURCE_FAILED";
}
function safeMessage(error: unknown) {
  if (error instanceof MissingRequiredHeaderError) return error.message;
  if (error instanceof SourceReadError && error.reasonCode.includes("AUTH")) return "Server-side source authorization is not ready for this read surface.";
  if (error instanceof SourceReadError) return `Authoritative source read failed for ${error.sourceRef}.`;
  return "Authoritative source read failed.";
}
function failure<T>(a: { interfaceKey: string; canonicalId: string; authority: SourceAuthority; sourceRef: string; maxAgeSeconds: number; error: unknown }): ReadEnvelopeV1<T> {
  const code = reason(a.error);
  return envelope<T>({ ...a, observedAt: null, readiness: code === "SENSITIVE_READ_BLOCKED" ? "BLOCKED" : "NOT_READY", reasonCode: code, data: null, warnings: [{ code, message: safeMessage(a.error) }] });
}

async function hub(domain: HubDomain) {
  const [sheet, range] = HUB[domain];
  const source = await readDataHubRange(sheet, range);
  return { records: mapDataHubRows(domain as DataHubDomain, source.rows), observedAt: source.observedAt, sourceRef: `MEYOU_CONNECT_MVP_DATA_HUB_V1/${sheet}` };
}

function rec<T>(canonicalId: string, sourceRef: string, observedAt: string, data: T, updatedAt: string | null, readiness: Readiness = "READY", reasonCode?: string): ReadRecordV1<T> {
  return { canonical_id: canonicalId, source_authority: sourceRef.startsWith("ops.") ? "SUPABASE_TECHNICAL" : "GOOGLE_SHEETS_DRIVE", source_ref: sourceRef, updated_at: updatedAt, freshness: freshness(observedAt, sourceRef.startsWith("ops.") ? 300 : 300), readiness, ...(reasonCode ? { reason_code: reasonCode } : {}), data };
}

async function gapGuard() {
  const source = await readSupabaseOps<GapRow[]>("candidate_promotion_gap_v", "select=readiness,gap_state,raw_input_id,received_at&limit=5000");
  const unverified = source.data.filter((x) => x.gap_state === "RAW_CANDIDATE_SHAPE_UNPROMOTED" || x.readiness === "NOT_READY");
  const verified = source.data.filter((x) => x.gap_state === "VERIFIED_MASTER_EFFECT" && x.readiness === "READY");
  return { unverifiedCount: unverified.length, verifiedCount: verified.length, newestUnverifiedAt: unverified.map((x) => x.received_at).filter((x): x is string => Boolean(x)).sort().at(-1) ?? null, observedAt: source.observedAt };
}

export async function readCandidates(candidateId?: string) {
  const interfaceKey = candidateId ? "candidate.detail" : "candidate.list";
  const canonicalId = candidateId ?? "READ:v1:candidate.list";
  const sourceRef = "MEYOU_CONNECT_MVP_DATA_HUB_V1/01_Candidate";
  try {
    const [source, gap] = await Promise.all([hub("candidate"), gapGuard()]);
    const inventoryCompleteness: CandidateInventoryCompletenessV1 = {
      readiness: gap.unverifiedCount > 0 ? "STALE" : "READY",
      ...(gap.unverifiedCount > 0 ? { reason_code: "UNPROMOTED_RAW_GAP" } : {}),
      unverified_count: gap.unverifiedCount,
      verified_count: gap.verifiedCount,
      newest_unverified_at: gap.newestUnverifiedAt,
      observed_at: gap.observedAt,
    };
    const warnings: ReadWarningV1[] = [{
      code: "SENSITIVE_FIELDS_REDACTED",
      message: "Candidate phone/LINE and other sensitive fields stay server-redacted until authenticated permission context is active.",
    }];
    if (gap.unverifiedCount > 0) {
      warnings.unshift({
        code: "UNPROMOTED_RAW_GAP",
        message: "Data Hub rows are readable, but Candidate inventory completeness cannot be claimed while Raw→Master linkage remains unverified.",
        count: gap.unverifiedCount,
      });
    }

    let lifecycleReviewCount = 0;
    const rows = source.records.map((r) => {
      const status = str(r.status);
      const normalizedStatus = status?.toUpperCase() ?? "";
      const lifecycleNeedsEvidenceReview = normalizedStatus === "APPLIED" || normalizedStatus === "NO_SHOW";
      const perRecordReadiness: Readiness = lifecycleNeedsEvidenceReview ? "PARTIAL" : "READY";
      if (lifecycleNeedsEvidenceReview) lifecycleReviewCount += 1;
      return rec(
        str(r.canonical_id) ?? "READ:v1:candidate.unknown",
        source.sourceRef,
        source.observedAt,
        {
          display_name: str(r.display_name), nickname: str(r.nickname), province: str(r.province), current_location: str(r.current_location), age: scalar(r.age), education: str(r.education), experience: str(r.experience), preferred_job: str(r.preferred_job), expected_income: str(r.expected_income), shift_preference: str(r.shift_preference), relocation_ready: str(r.relocation_ready), ready_date: str(r.ready_date), has_vehicle: str(r.has_vehicle), dorm_needed: str(r.dorm_needed), dorm_budget: str(r.dorm_budget), documents_ready: str(r.documents_ready), medical_ready: str(r.medical_ready), source_type: str(r.source_type), partner_id: str(r.partner_id), status, last_contact: str(r.last_contact), next_action: str(r.next_action), consent_status: str(r.consent_status), notes: str(r.notes),
          per_candidate_record_readiness: perRecordReadiness,
          lifecycle_evidence_state: lifecycleNeedsEvidenceReview ? "REVIEW" : "NOT_REQUIRED_BY_CURRENT_STATUS",
          lifecycle_action_unlock_allowed: false,
        },
        iso(r.updated_at),
        perRecordReadiness,
        lifecycleNeedsEvidenceReview ? "LIFECYCLE_EVIDENCE_REVIEW_REQUIRED" : undefined,
      );
    });

    const data = candidateId ? rows.find((r) => r.canonical_id === candidateId) ?? null : rows;
    const selectedLifecycleReviewCount = candidateId
      ? data?.reason_code === "LIFECYCLE_EVIDENCE_REVIEW_REQUIRED" ? 1 : 0
      : lifecycleReviewCount;
    if (selectedLifecycleReviewCount > 0) {
      warnings.push({
        code: "LIFECYCLE_EVIDENCE_REVIEW_REQUIRED",
        message: "APPLIED/NO_SHOW lifecycle labels do not unlock downstream actions until the required evidence gate is verified; treat them as REVIEW/DQ.",
        count: selectedLifecycleReviewCount,
      });
    }

    const notFound = Boolean(candidateId && !data);
    const envelopeReadiness: Readiness = notFound
      ? "NOT_READY"
      : gap.unverifiedCount > 0
        ? "STALE"
        : data && !Array.isArray(data) && data.readiness === "PARTIAL"
          ? "PARTIAL"
          : "READY";
    const reasonCode = notFound
      ? "RECORD_NOT_FOUND"
      : gap.unverifiedCount > 0
        ? "UNPROMOTED_RAW_GAP"
        : data && !Array.isArray(data) && data.reason_code
          ? data.reason_code
          : undefined;

    return envelope({
      interfaceKey,
      canonicalId,
      authority: "GOOGLE_SHEETS_DRIVE",
      sourceRef,
      observedAt: source.observedAt,
      maxAgeSeconds: 300,
      readiness: envelopeReadiness,
      reasonCode,
      data,
      candidateInventoryCompleteness: inventoryCompleteness,
      warnings: notFound
        ? [{ code: "RECORD_NOT_FOUND", message: "Candidate ID is not present in Data Hub." }, ...warnings]
        : warnings,
    });
  } catch (error) {
    return failure({ interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, maxAgeSeconds: 300, error });
  }
}

function safeJob(r: Row) { return { client_id: str(r.client_id), company: str(r.company), province: str(r.province), location: str(r.location), position: str(r.position), headcount: scalar(r.headcount), wage: str(r.wage), ot: str(r.ot), shift: str(r.shift), benefits: str(r.benefits), required_qualification: str(r.required_qualification), documents: str(r.documents), medical_requirement: str(r.medical_requirement), dorm_available: str(r.dorm_available), transport_available: str(r.transport_available), application_date: str(r.application_date), start_date: str(r.start_date), milestone: str(r.milestone), payment_term: str(r.payment_term), contact_person: str(r.contact_person), status: str(r.status) }; }
function safeClient(r: Row) { return { client_type: str(r.client_type), company_name: str(r.company_name), province: str(r.province), area: str(r.area), crm_status: str(r.crm_status), next_action: str(r.next_action), payment_term: str(r.payment_term), billing_cycle: str(r.billing_cycle), verification_status: str(r.verification_status) }; }
function safePartner(r: Row) { return { partner_name: str(r.partner_name), province: str(r.province), partner_type: str(r.partner_type), parent_partner_id: str(r.parent_partner_id), started_at: str(r.started_at), status: str(r.status) }; }

export async function readBusinessList(domain: "job" | "client" | "partner", id?: string) {
  const interfaceKey = id ? `${domain}.detail` : `${domain}.list`;
  const canonicalId = id ?? `READ:v1:${domain}.list`;
  const sourceRef = `MEYOU_CONNECT_MVP_DATA_HUB_V1/${HUB[domain][0]}`;
  try {
    const source = await hub(domain);
    const rows = source.records.map((r) => rec(str(r.canonical_id) ?? `READ:v1:${domain}.unknown`, source.sourceRef, source.observedAt, domain === "job" ? safeJob(r) : domain === "client" ? safeClient(r) : safePartner(r), iso(r.updated_at)));
    const data = id ? rows.find((r) => r.canonical_id === id) ?? null : rows;
    const warnings: ReadWarningV1[] = domain === "client" || domain === "partner" ? [{ code: "SENSITIVE_FIELDS_REDACTED", message: "Phone/LINE contact fields stay redacted in Preview." }] : [];
    if (id && !data) warnings.unshift({ code: "RECORD_NOT_FOUND", message: `${domain} ID is not present in Data Hub.` });
    return envelope({ interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, observedAt: source.observedAt, maxAgeSeconds: 300, readiness: id && !data ? "NOT_READY" : "READY", reasonCode: id && !data ? "RECORD_NOT_FOUND" : undefined, data, warnings });
  } catch (error) { return failure({ interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, maxAgeSeconds: 300, error }); }
}

type InboxRow = { raw_input_id: string; inbox_source: string | null; direction: string | null; occurred_at: string | null; received_at: string | null; thread_display_name: string | null; identity_status: string | null; content_type: string | null; processing_status: string | null; attachment_status: string | null; attachment_filename: string | null; needs_identity_link: boolean | null };
export async function readLineInbox() {
  const sourceRef = "ops.line_inbox_v";
  try {
    const source = await readSupabaseOps<InboxRow[]>("line_inbox_v", "select=raw_input_id,inbox_source,direction,occurred_at,received_at,thread_display_name,identity_status,content_type,processing_status,attachment_status,attachment_filename,needs_identity_link&order=received_at.desc&limit=100");
    const unverified = source.data.filter((r) => r.identity_status === "UNVERIFIED" || r.needs_identity_link).length;
    const data = source.data.map((r) => rec(r.raw_input_id, sourceRef, source.observedAt, { source: r.inbox_source, direction: r.direction, occurred_at: r.occurred_at, thread_name: r.thread_display_name, identity_status: r.identity_status, content_type: r.content_type, processing_status: r.processing_status, attachment_status: r.attachment_status, attachment_filename: r.attachment_filename, needs_identity_link: r.needs_identity_link, sensitive_content_redacted: true }, r.received_at, r.identity_status === "UNVERIFIED" ? "PARTIAL" : "READY", r.identity_status === "UNVERIFIED" ? "IDENTITY_UNVERIFIED" : undefined));
    const warnings: ReadWarningV1[] = [{ code: "SENSITIVE_FIELDS_REDACTED", message: "Sender references and message/raw summary are server-redacted in Preview." }];
    if (unverified) warnings.push({ code: "UNVERIFIED_IDENTITY_ROWS", message: "Inbox contains records without verified entity identity linkage.", count: unverified });
    return envelope({ interfaceKey: "inbox.line", canonicalId: "READ:v1:inbox.line", authority: "SUPABASE_TECHNICAL", sourceRef, observedAt: source.observedAt, maxAgeSeconds: 300, readiness: unverified ? "PARTIAL" : "READY", data, warnings });
  } catch (error) { return failure({ interfaceKey: "inbox.line", canonicalId: "READ:v1:inbox.line", authority: "SUPABASE_TECHNICAL", sourceRef, maxAgeSeconds: 300, error }); }
}

type Worker = { worker_key: string; domain: string | null; enabled: boolean; environment: string | null; version: string | null; effective_status: string | null; last_seen_at: string | null; heartbeat_age_seconds: number | null };
type Backlog = { worker_key: string; ready_count: number; retry_wait_count: number; approval_wait_count: number; dead_letter_count: number };
export async function readSystemHealth() {
  const sourceRef = "ops.operations_health_v+ops.worker_health_v+ops.worker_backlog_v+ops.candidate_promotion_gap_v";
  try {
    const [operations, workers, backlog, gap] = await Promise.all([
      readSupabaseOps<Row[]>("operations_health_v", "select=*&limit=1"),
      readSupabaseOps<Worker[]>("worker_health_v", "select=worker_key,domain,enabled,environment,version,effective_status,last_seen_at,heartbeat_age_seconds&order=worker_key.asc"),
      readSupabaseOps<Backlog[]>("worker_backlog_v", "select=worker_key,ready_count,retry_wait_count,approval_wait_count,dead_letter_count&order=worker_key.asc"),
      gapGuard(),
    ]);
    const notStarted = workers.data.filter((r) => r.effective_status === "NOT_STARTED").length;
    const warnings: ReadWarningV1[] = [];
    if (notStarted) warnings.push({ code: "WORKERS_NOT_STARTED", message: "Registered workers that have not started remain visible and are not represented as healthy.", count: notStarted });
    if (gap.unverifiedCount) warnings.push({ code: "UNPROMOTED_RAW_GAP", message: "Candidate completeness guard has unverified Raw→Master linkage.", count: gap.unverifiedCount });
    return envelope({ interfaceKey: "system.health", canonicalId: "SYSTEM:operations", authority: "SUPABASE_TECHNICAL", sourceRef, observedAt: operations.observedAt, maxAgeSeconds: OFFICIAL_READ_FRESHNESS_SECONDS.systemHealth, readiness: warnings.length ? "PARTIAL" : "READY", data: { operations: operations.data[0] ?? null, workers: workers.data, backlog: backlog.data, candidate_gap: gap }, warnings });
  } catch (error) { return failure({ interfaceKey: "system.health", canonicalId: "SYSTEM:operations", authority: "SUPABASE_TECHNICAL", sourceRef, maxAgeSeconds: 600, error }); }
}

type TechnicalDq = { dq_issue_id: string; entity_type: string | null; entity_id: string | null; issue_type: string | null; severity: string | null; status: string | null; updated_at: string | null };
export async function readDq() {
  const sourceRef = "MEYOU_CONNECT_MVP_DATA_HUB_V1/21_Data_Quality_Queue+ops.data_quality_issues";
  const warnings: ReadWarningV1[] = [];
  let business: Awaited<ReturnType<typeof hub>> | null = null;
  let technical: { data: TechnicalDq[]; observedAt: string } | null = null;
  try { business = await hub("dq"); } catch (error) { warnings.push({ code: reason(error), message: safeMessage(error) }); }
  try { technical = await readSupabaseOps<TechnicalDq[]>("data_quality_issues", "select=dq_issue_id,entity_type,entity_id,issue_type,severity,status,updated_at&order=updated_at.desc&limit=200"); } catch (error) { warnings.push({ code: reason(error), message: safeMessage(error) }); }
  if (!business && !technical) return envelope({ interfaceKey: "dq.list", canonicalId: "READ:v1:dq.list", authority: "COMPOSITE_GOVERNED", sourceRef, observedAt: null, maxAgeSeconds: 300, readiness: "NOT_READY", reasonCode: "DQ_SOURCES_NOT_READY", data: null, warnings });
  const businessRows = business ? business.records.map((r) => rec(str(r.canonical_id) ?? "READ:v1:dq.unknown", business!.sourceRef, business!.observedAt, { entity_type: str(r.entity_type), entity_id: str(r.entity_id), issue_type: str(r.issue_type), severity: str(r.severity), required_action: str(r.required_action), status: str(r.status), resolution: str(r.resolution) }, iso(r.updated_at))) : [];
  const technicalRows = technical ? technical.data.map((r) => rec(r.dq_issue_id, "ops.data_quality_issues", technical!.observedAt, { entity_type: r.entity_type, entity_id: r.entity_id, issue_type: r.issue_type, severity: r.severity, status: r.status }, r.updated_at)) : [];
  return envelope({ interfaceKey: "dq.list", canonicalId: "READ:v1:dq.list", authority: "COMPOSITE_GOVERNED", sourceRef, observedAt: business?.observedAt ?? technical?.observedAt ?? null, maxAgeSeconds: 300, readiness: business && technical ? "READY" : "PARTIAL", reasonCode: business && technical ? undefined : "DQ_SOURCE_PARTIAL", data: { business: businessRows, technical: technicalRows }, warnings });
}

const rank: Record<Readiness, number> = { READY: 0, PARTIAL: 1, STALE: 2, NOT_READY: 3, BLOCKED: 4 };
const worst = (values: Readiness[]) => values.reduce<Readiness>((a, b) => rank[b] > rank[a] ? b : a, "READY");
export async function readFounderToday() {
  const sourceRef = "MEYOU_CONNECT_MVP_DATA_HUB_V1/00_งานวันนี้_Inbox+governed dependencies";
  try {
    const today = await hub("founderToday");
    const [candidate, dq, system] = await Promise.all([readCandidates(), readDq(), readSystemHealth()]);
    const metrics = today.records.map((r) => ({ metric: str(r.metric), value: scalar(r.value), meaning: str(r.meaning) }));
    const dqData = dq.data as { business?: Array<ReadRecordV1<{ severity?: string | null; status?: string | null; required_action?: string | null; issue_type?: string | null }>> } | null;
    const actions = (dqData?.business ?? []).filter((r) => r.data.status === "OPEN" && ["HIGH", "MEDIUM"].includes(r.data.severity ?? "")).slice(0, 8).map((r) => ({ canonical_id: r.canonical_id, severity: r.data.severity, issue_type: r.data.issue_type, next_action: r.data.required_action }));
    const readiness = worst([candidate.readiness, dq.readiness, system.readiness]);
    const warnings = [...candidate.warnings, ...dq.warnings, ...system.warnings];
    return envelope({ interfaceKey: "founder.today", canonicalId: "READ:v1:founder.today", authority: "COMPOSITE_GOVERNED", sourceRef, observedAt: today.observedAt, maxAgeSeconds: 300, readiness, reasonCode: readiness === "READY" ? undefined : "DEPENDENCY_READINESS_PROPAGATED", data: { today: metrics, need_my_action: actions, warning_summary: warnings.slice(0, 12), ai_system_handled: system.data ? { operations: (system.data as { operations?: unknown }).operations ?? null } : null, source_readiness: { candidate: candidate.readiness, dq: dq.readiness, system: system.readiness, data_hub_today: "READY" } }, warnings });
  } catch (error) { return failure({ interfaceKey: "founder.today", canonicalId: "READ:v1:founder.today", authority: "COMPOSITE_GOVERNED", sourceRef, maxAgeSeconds: 300, error }); }
}

export async function dispatchOfficialRead(segments: string[]) {
  if (segments[0] === "inbox" && segments[1] === "line" && segments.length === 2) return readLineInbox();
  if (segments[0] === "system" && segments[1] === "health" && segments.length === 2) return readSystemHealth();
  if (segments[0] === "jobs" && segments.length <= 2) return readBusinessList("job", segments[1]);
  if (segments[0] === "clients" && segments.length <= 2) return readBusinessList("client", segments[1]);
  if (segments[0] === "partners" && segments.length <= 2) return readBusinessList("partner", segments[1]);
  if (segments[0] === "candidates" && segments.length <= 2) return readCandidates(segments[1]);
  if (segments[0] === "dq" && segments.length === 1) return readDq();
  if (segments[0] === "founder" && segments[1] === "today" && segments.length === 2) return readFounderToday();
  return envelope({ interfaceKey: "unknown", canonicalId: "READ:v1:unknown", authority: "COMPOSITE_GOVERNED", sourceRef: "OFFICIAL_READ_V1", observedAt: now(), maxAgeSeconds: 300, readiness: "NOT_READY", reasonCode: "READ_ROUTE_NOT_FOUND", data: null, warnings: [{ code: "READ_ROUTE_NOT_FOUND", message: "Requested path is not part of Official Operational Read Contract V1." }] });
}
