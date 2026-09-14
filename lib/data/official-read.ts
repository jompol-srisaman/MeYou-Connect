import {
  OFFICIAL_READ_FRESHNESS_SECONDS,
  type FreshnessV1,
  type ReadEnvelopeV1,
  type ReadRecordV1,
  type Readiness,
  type ReadWarningV1,
  type SourceAuthority,
} from "@/lib/platform/contracts";
import { mapDataHubRows, MissingRequiredHeaderError, type DataHubDomain } from "@/lib/data/header-aliases";
import { readDataHubRange, readSupabaseOps, SourceReadError } from "@/lib/data/source-clients";

const NOW = () => new Date().toISOString();

const DATA_HUB_RANGES = {
  candidate: { sheet: "01_Candidate", range: "A1:AI5000" },
  job: { sheet: "02_งาน_Job", range: "A1:AD3000" },
  client: { sheet: "03_Client", range: "A1:X1000" },
  partner: { sheet: "04_Partner", range: "A1:T2000" },
  dq: { sheet: "21_Data_Quality_Queue", range: "A1:T5000" },
  founderToday: { sheet: "00_งานวันนี้_Inbox", range: "A2:C1002" },
} as const;

type BusinessDomain = keyof typeof DATA_HUB_RANGES;

type SafeCandidate = {
  display_name: string | null;
  nickname: string | null;
  province: string | null;
  current_location: string | null;
  age: string | number | null;
  education: string | null;
  experience: string | null;
  preferred_job: string | null;
  expected_income: string | null;
  shift_preference: string | null;
  relocation_ready: string | null;
  ready_date: string | null;
  has_vehicle: string | null;
  dorm_needed: string | null;
  dorm_budget: string | null;
  documents_ready: string | null;
  medical_ready: string | null;
  source_type: string | null;
  partner_id: string | null;
  status: string | null;
  last_contact: string | null;
  next_action: string | null;
  consent_status: string | null;
  notes: string | null;
};

type SafeJob = {
  client_id: string | null;
  company: string | null;
  province: string | null;
  location: string | null;
  position: string | null;
  headcount: string | number | null;
  wage: string | null;
  ot: string | null;
  shift: string | null;
  benefits: string | null;
  required_qualification: string | null;
  documents: string | null;
  medical_requirement: string | null;
  dorm_available: string | null;
  transport_available: string | null;
  application_date: string | null;
  start_date: string | null;
  milestone: string | null;
  payment_term: string | null;
  contact_person: string | null;
  status: string | null;
};

type SafeClient = {
  client_type: string | null;
  company_name: string | null;
  province: string | null;
  area: string | null;
  crm_status: string | null;
  next_action: string | null;
  payment_term: string | null;
  billing_cycle: string | null;
  verification_status: string | null;
};

type SafePartner = {
  partner_name: string | null;
  province: string | null;
  partner_type: string | null;
  parent_partner_id: string | null;
  started_at: string | null;
  status: string | null;
};

type CandidateGapRow = {
  readiness: string | null;
  gap_state: string | null;
  raw_input_id?: string | null;
  received_at?: string | null;
};

function nullable(value: unknown): string | number | null {
  if (value === undefined || value === null || value === "") return null;
  if (typeof value === "number") return value;
  return String(value);
}

function text(value: unknown) {
  const v = nullable(value);
  return v === null ? null : String(v);
}

function sourceDate(value: unknown) {
  const raw = text(value);
  if (!raw) return null;
  const withOffset = /[+-]\d{2}$/.test(raw) ? `${raw}:00` : raw;
  const epoch = Date.parse(withOffset);
  return Number.isNaN(epoch) ? null : new Date(epoch).toISOString();
}

function freshness(observedAt: string | null, maxAgeSeconds: number, explicitReason?: string): FreshnessV1 {
  if (!observedAt) return { state: "UNKNOWN", observed_at: null, age_seconds: null, max_age_seconds: maxAgeSeconds, reason: explicitReason };
  const age = Math.max(0, Math.floor((Date.now() - Date.parse(observedAt)) / 1000));
  return {
    state: age > maxAgeSeconds ? "STALE" : "FRESH",
    observed_at: observedAt,
    age_seconds: age,
    max_age_seconds: maxAgeSeconds,
    ...(explicitReason ? { reason: explicitReason } : {}),
  };
}

function makeEnvelope<T>(args: {
  interfaceKey: string;
  canonicalId: string;
  authority: SourceAuthority;
  sourceRef: string;
  updatedAt?: string | null;
  observedAt?: string | null;
  maxAgeSeconds: number;
  readiness: Readiness;
  data: T | null;
  reasonCode?: string;
  warnings?: ReadWarningV1[];
}): ReadEnvelopeV1<T> {
  const sourceFreshness = freshness(args.observedAt ?? null, args.maxAgeSeconds);
  const readiness = sourceFreshness.state === "STALE" && args.readiness === "READY" ? "STALE" : args.readiness;
  return {
    contract_version: "v1",
    interface_key: args.interfaceKey,
    canonical_id: args.canonicalId,
    source_authority: args.authority,
    source_ref: args.sourceRef,
    updated_at: args.updatedAt ?? null,
    freshness: sourceFreshness,
    readiness,
    ...(args.reasonCode ? { reason_code: args.reasonCode } : {}),
    generated_at: NOW(),
    data: args.data,
    warnings: args.warnings ?? [],
  };
}

function sourceFailure<T>(args: {
  interfaceKey: string;
  canonicalId: string;
  authority: SourceAuthority;
  sourceRef: string;
  maxAgeSeconds: number;
  error: unknown;
}): ReadEnvelopeV1<T> {
  const reasonCode = errorReason(args.error);
  return makeEnvelope({
    ...args,
    observedAt: null,
    readiness: reasonCode === "SENSITIVE_READ_BLOCKED" ? "BLOCKED" : "NOT_READY",
    reasonCode,
    data: null,
    warnings: [{ code: reasonCode, message: safeErrorMessage(args.error) }],
  });
}

function errorReason(error: unknown) {
  if (error instanceof SourceReadError) return error.reasonCode;
  if (error instanceof MissingRequiredHeaderError) return "DATA_HUB_REQUIRED_HEADER_MISSING";
  return "READ_SOURCE_FAILED";
}

function safeErrorMessage(error: unknown) {
  if (error instanceof MissingRequiredHeaderError) return error.message;
  if (error instanceof SourceReadError) {
    if (error.reasonCode.includes("AUTH")) return "Server-side source authorization is not ready for this read surface.";
    return `Authoritative source read failed for ${error.sourceRef}.`;
  }
  return "Authoritative source read failed.";
}

async function readBusinessDomain(domain: BusinessDomain) {
  const spec = DATA_HUB_RANGES[domain];
  const { rows, observedAt } = await readDataHubRange(spec.sheet, spec.range);
  return { records: mapDataHubRows(domain as DataHubDomain, rows), observedAt, sourceRef: `MEYOU_CONNECT_MVP_DATA_HUB_V1/${spec.sheet}` };
}

function record<T>(args: {
  canonicalId: string;
  authority: SourceAuthority;
  sourceRef: string;
  updatedAt: string | null;
  observedAt: string;
  maxAgeSeconds: number;
  readiness?: Readiness;
  reasonCode?: string;
  data: T;
}): ReadRecordV1<T> {
  return {
    canonical_id: args.canonicalId,
    source_authority: args.authority,
    source_ref: args.sourceRef,
    updated_at: args.updatedAt,
    freshness: freshness(args.observedAt, args.maxAgeSeconds),
    readiness: args.readiness ?? "READY",
    ...(args.reasonCode ? { reason_code: args.reasonCode } : {}),
    data: args.data,
  };
}

async function candidateGap() {
  const result = await readSupabaseOps<CandidateGapRow[]>(
    "candidate_promotion_gap_v",
    "select=readiness,gap_state,raw_input_id,received_at&limit=5000",
  );
  const unverified = result.data.filter((row) => row.gap_state === "RAW_CANDIDATE_SHAPE_UNPROMOTED" || row.readiness === "NOT_READY");
  const verified = result.data.filter((row) => row.gap_state === "VERIFIED_MASTER_EFFECT" && row.readiness === "READY");
  return {
    unverifiedCount: unverified.length,
    verifiedCount: verified.length,
    newestUnverifiedAt: unverified.map((row) => row.received_at).filter(Boolean).sort().at(-1) ?? null,
    observedAt: result.observedAt,
  };
}

export async function readCandidates(candidateId?: string) {
  const interfaceKey = candidateId ? "candidate.detail" : "candidate.list";
  const canonicalId = candidateId ?? "READ:v1:candidate.list";
  const sourceRef = "MEYOU_CONNECT_MVP_DATA_HUB_V1/01_Candidate";
  try {
    const [hub, gap] = await Promise.all([readBusinessDomain("candidate"), candidateGap()]);
    const warnings: ReadWarningV1[] = [{
      code: "SENSITIVE_FIELDS_REDACTED",
      message: "Phone/LINE and other sensitive Candidate fields are not exposed until an authenticated server permission context is active.",
    }];
    let readiness: Readiness = "READY";
    let reasonCode: string | undefined;
    if (gap.unverifiedCount > 0) {
      readiness = "STALE";
      reasonCode = "UNPROMOTED_RAW_GAP";
      warnings.unshift({
        code: "UNPROMOTED_RAW_GAP",
        message: "Candidate records are readable from Data Hub, but completeness cannot be claimed while unverified Raw→Master linkage exists.",
        count: gap.unverifiedCount,
      });
    }

    const mapped = hub.records.map((row) => record<SafeCandidate>({
      canonicalId: text(row.canonical_id) ?? "READ:v1:candidate.unknown",
      authority: "GOOGLE_SHEETS_DRIVE",
      sourceRef: hub.sourceRef,
      updatedAt: sourceDate(row.updated_at),
      observedAt: hub.observedAt,
      maxAgeSeconds: OFFICIAL_READ_FRESHNESS_SECONDS.googleDataHub,
      readiness,
      reasonCode,
      data: {
        display_name: text(row.display_name), nickname: text(row.nickname), province: text(row.province),
        current_location: text(row.current_location), age: nullable(row.age), education: text(row.education),
        experience: text(row.experience), preferred_job: text(row.preferred_job), expected_income: text(row.expected_income),
        shift_preference: text(row.shift_preference), relocation_ready: text(row.relocation_ready), ready_date: text(row.ready_date),
        has_vehicle: text(row.has_vehicle), dorm_needed: text(row.dorm_needed), dorm_budget: text(row.dorm_budget),
        documents_ready: text(row.documents_ready), medical_ready: text(row.medical_ready), source_type: text(row.source_type),
        partner_id: text(row.partner_id), status: text(row.status), last_contact: text(row.last_contact), next_action: text(row.next_action),
        consent_status: text(row.consent_status), notes: text(row.notes),
      },
    }));

    const data = candidateId ? mapped.find((item) => item.canonical_id === candidateId) ?? null : mapped;
    if (candidateId && !data) return makeEnvelope({
      interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, observedAt: hub.observedAt,
      maxAgeSeconds: 300, readiness: "NOT_READY", reasonCode: "RECORD_NOT_FOUND", data: null,
      warnings: [{ code: "RECORD_NOT_FOUND", message: "Candidate ID is not present in the authoritative Data Hub read." }],
    });

    return makeEnvelope({
      interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, observedAt: hub.observedAt,
      maxAgeSeconds: 300, readiness, reasonCode, data, warnings,
    });
  } catch (error) {
    return sourceFailure({ interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, maxAgeSeconds: 300, error });
  }
}

function mapJob(row: Record<string, unknown>): SafeJob {
  return {
    client_id: text(row.client_id), company: text(row.company), province: text(row.province), location: text(row.location),
    position: text(row.position), headcount: nullable(row.headcount), wage: text(row.wage), ot: text(row.ot), shift: text(row.shift),
    benefits: text(row.benefits), required_qualification: text(row.required_qualification), documents: text(row.documents),
    medical_requirement: text(row.medical_requirement), dorm_available: text(row.dorm_available), transport_available: text(row.transport_available),
    application_date: text(row.application_date), start_date: text(row.start_date), milestone: text(row.milestone), payment_term: text(row.payment_term),
    contact_person: text(row.contact_person), status: text(row.status),
  };
}

export async function readBusinessList(domain: "job" | "client" | "partner", id?: string) {
  const names = { job: "job", client: "client", partner: "partner" } as const;
  const entity = names[domain];
  const interfaceKey = id ? `${entity}.detail` : `${entity}.list`;
  const canonicalId = id ?? `READ:v1:${entity}.list`;
  const sourceRef = `MEYOU_CONNECT_MVP_DATA_HUB_V1/${DATA_HUB_RANGES[domain].sheet}`;
  try {
    const hub = await readBusinessDomain(domain);
    const items = hub.records.map((row) => {
      const rowId = text(row.canonical_id) ?? `READ:v1:${entity}.unknown`;
      const data = domain === "job" ? mapJob(row) : domain === "client" ? {
        client_type: text(row.client_type), company_name: text(row.company_name), province: text(row.province), area: text(row.area),
        crm_status: text(row.crm_status), next_action: text(row.next_action), payment_term: text(row.payment_term), billing_cycle: text(row.billing_cycle),
        verification_status: text(row.verification_status),
      } satisfies SafeClient : {
        partner_name: text(row.partner_name), province: text(row.province), partner_type: text(row.partner_type),
        parent_partner_id: text(row.parent_partner_id), started_at: text(row.started_at), status: text(row.status),
      } satisfies SafePartner;
      return record({
        canonicalId: rowId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef: hub.sourceRef, updatedAt: sourceDate(row.updated_at),
        observedAt: hub.observedAt, maxAgeSeconds: 300, data,
      });
    });
    const data = id ? items.find((item) => item.canonical_id === id) ?? null : items;
    const warnings: ReadWarningV1[] = domain === "client" || domain === "partner" ? [{
      code: "SENSITIVE_FIELDS_REDACTED",
      message: "Contact phone/LINE fields remain server-redacted in Preview until authenticated permission context is active.",
    }] : [];
    if (id && !data) warnings.unshift({ code: "RECORD_NOT_FOUND", message: `${entity} ID is not present in Data Hub.` });
    return makeEnvelope({
      interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, observedAt: hub.observedAt, maxAgeSeconds: 300,
      readiness: id && !data ? "NOT_READY" : "READY", reasonCode: id && !data ? "RECORD_NOT_FOUND" : undefined, data, warnings,
    });
  } catch (error) {
    return sourceFailure({ interfaceKey, canonicalId, authority: "GOOGLE_SHEETS_DRIVE", sourceRef, maxAgeSeconds: 300, error });
  }
}

type InboxRow = {
  raw_input_id: string;
  inbox_source: string | null;
  direction: string | null;
  occurred_at: string | null;
  received_at: string | null;
  thread_display_name: string | null;
  identity_status: string | null;
  content_type: string | null;
  processing_status: string | null;
  attachment_status: string | null;
  attachment_filename: string | null;
  needs_identity_link: boolean | null;
  sensitive: boolean | null;
};

export async function readLineInbox() {
  const sourceRef = "ops.line_inbox_v";
  try {
    const source = await readSupabaseOps<InboxRow[]>(sourceRef.replace("ops.", ""),
      "select=raw_input_id,inbox_source,direction,occurred_at,received_at,thread_display_name,identity_status,content_type,processing_status,attachment_status,attachment_filename,needs_identity_link,sensitive&order=received_at.desc&limit=100");
    const unverified = source.data.filter((row) => row.identity_status === "UNVERIFIED" || row.needs_identity_link).length;
    const data = source.data.map((row) => record({
      canonicalId: row.raw_input_id,
      authority: "SUPABASE_TECHNICAL",
      sourceRef,
      updatedAt: row.received_at,
      observedAt: source.observedAt,
      maxAgeSeconds: 300,
      readiness: row.identity_status === "UNVERIFIED" ? "PARTIAL" : "READY",
      reasonCode: row.identity_status === "UNVERIFIED" ? "IDENTITY_UNVERIFIED" : undefined,
      data: {
        source: row.inbox_source, direction: row.direction, occurred_at: row.occurred_at, thread_name: row.thread_display_name,
        identity_status: row.identity_status, content_type: row.content_type, processing_status: row.processing_status,
        attachment_status: row.attachment_status, attachment_filename: row.attachment_filename, needs_identity_link: row.needs_identity_link,
        sensitive_content_redacted: true,
      },
    }));
    const warnings: ReadWarningV1[] = [
      { code: "SENSITIVE_FIELDS_REDACTED", message: "Sender references and message/raw summary are server-redacted in Preview." },
    ];
    if (unverified) warnings.push({ code: "UNVERIFIED_IDENTITY_ROWS", message: "Inbox contains records without verified entity identity linkage.", count: unverified });
    return makeEnvelope({
      interfaceKey: "inbox.line", canonicalId: "READ:v1:inbox.line", authority: "SUPABASE_TECHNICAL", sourceRef,
      observedAt: source.observedAt, maxAgeSeconds: 300, readiness: unverified ? "PARTIAL" : "READY", data, warnings,
    });
  } catch (error) {
    return sourceFailure({ interfaceKey: "inbox.line", canonicalId: "READ:v1:inbox.line", authority: "SUPABASE_TECHNICAL", sourceRef, maxAgeSeconds: 300, error });
  }
}

type OperationsRow = Record<string, string | number | null>;
type WorkerRow = { worker_key: string; domain: string | null; enabled: boolean; environment: string | null; version: string | null; effective_status: string | null; last_seen_at: string | null; heartbeat_age_seconds: number | null };
type BacklogRow = { worker_key: string; ready_count: number; retry_wait_count: number; approval_wait_count: number; dead_letter_count: number };

export async function readSystemHealth() {
  const sourceRef = "ops.operations_health_v+ops.worker_health_v+ops.worker_backlog_v+ops.candidate_promotion_gap_v";
  try {
    const [operations, workers, backlog, gap] = await Promise.all([
      readSupabaseOps<OperationsRow[]>("operations_health_v", "select=*&limit=1"),
      readSupabaseOps<WorkerRow[]>("worker_health_v", "select=worker_key,domain,enabled,environment,version,effective_status,last_seen_at,heartbeat_age_seconds&order=worker_key.asc"),
      readSupabaseOps<BacklogRow[]>("worker_backlog_v", "select=worker_key,ready_count,retry_wait_count,approval_wait_count,dead_letter_count&order=worker_key.asc"),
      candidateGap(),
    ]);
    const notStarted = workers.data.filter((row) => row.effective_status === "NOT_STARTED").length;
    const warnings: ReadWarningV1[] = [];
    if (notStarted) warnings.push({ code: "WORKERS_NOT_STARTED", message: "Registered workers that have not started are kept visible and are not represented as healthy.", count: notStarted });
    if (gap.unverifiedCount) warnings.push({ code: "UNPROMOTED_RAW_GAP", message: "Candidate completeness guard currently has unverified Raw→Master linkage.", count: gap.unverifiedCount });
    return makeEnvelope({
      interfaceKey: "system.health", canonicalId: "SYSTEM:operations", authority: "SUPABASE_TECHNICAL", sourceRef,
      observedAt: operations.observedAt, maxAgeSeconds: 600, readiness: warnings.length ? "PARTIAL" : "READY",
      data: { operations: operations.data[0] ?? null, workers: workers.data, backlog: backlog.data, candidate_gap: gap }, warnings,
    });
  } catch (error) {
    return sourceFailure({ interfaceKey: "system.health", canonicalId: "SYSTEM:operations", authority: "SUPABASE_TECHNICAL", sourceRef, maxAgeSeconds: 600, error });
  }
}

type TechnicalDqRow = { dq_issue_id: string; entity_type: string | null; entity_id: string | null; issue_type: string | null; severity: string | null; status: string | null; updated_at: string | null };

export async function readDq() {
  const warnings: ReadWarningV1[] = [];
  let hub: Awaited<ReturnType<typeof readBusinessDomain>> | null = null;
  let technical: { data: TechnicalDqRow[]; observedAt: string } | null = null;
  try { hub = await readBusinessDomain("dq"); } catch (error) { warnings.push({ code: errorReason(error), message: safeErrorMessage(error) }); }
  try { technical = await readSupabaseOps<TechnicalDqRow[]>("data_quality_issues", "select=dq_issue_id,entity_type,entity_id,issue_type,severity,status,updated_at&order=updated_at.desc&limit=200"); }
  catch (error) { warnings.push({ code: errorReason(error), message: safeErrorMessage(error) }); }

  if (!hub && !technical) return makeEnvelope({
    interfaceKey: "dq.list", canonicalId: "READ:v1:dq.list", authority: "COMPOSITE_GOVERNED", sourceRef: "MEYOU_CONNECT_MVP_DATA_HUB_V1/21_Data_Quality_Queue+ops.data_quality_issues",
    observedAt: null, maxAgeSeconds: 300, readiness: "NOT_READY", reasonCode: "DQ_SOURCES_NOT_READY", data: null, warnings,
  });

  const business = hub ? hub.records.map((row) => record({
    canonicalId: text(row.canonical_id) ?? "READ:v1:dq.unknown", authority: "GOOGLE_SHEETS_DRIVE", sourceRef: hub!.sourceRef,
    updatedAt: sourceDate(row.updated_at), observedAt: hub!.observedAt, maxAgeSeconds: 300,
    data: { entity_type: text(row.entity_type), entity_id: text(row.entity_id), issue_type: text(row.issue_type), severity: text(row.severity), required_action: text(row.required_action), status: text(row.status), resolution: text(row.resolution) },
  })) : [];
  const technicalRows = technical ? technical.data.map((row) => record({
    canonicalId: row.dq_issue_id, authority: "SUPABASE_TECHNICAL", sourceRef: "ops.data_quality_issues", updatedAt: row.updated_at,
    observedAt: technical!.observedAt, maxAgeSeconds: 300,
    data: { entity_type: row.entity_type, entity_id: row.entity_id, issue_type: row.issue_type, severity: row.severity, status: row.status },
  })) : [];
  return makeEnvelope({
    interfaceKey: "dq.list", canonicalId: "READ:v1:dq.list", authority: "COMPOSITE_GOVERNED", sourceRef: "MEYOU_CONNECT_MVP_DATA_HUB_V1/21_Data_Quality_Queue+ops.data_quality_issues",
    observedAt: hub?.observedAt ?? technical?.observedAt ?? null, maxAgeSeconds: 300, readiness: hub && technical ? "READY" : "PARTIAL",
    reasonCode: hub && technical ? undefined : "DQ_SOURCE_PARTIAL", data: { business, technical: technicalRows }, warnings,
  });
}

const readinessRank: Record<Readiness, number> = { READY: 0, PARTIAL: 1, STALE: 2, NOT_READY: 3, BLOCKED: 4 };
function worstReadiness(values: Readiness[]) {
  return values.reduce<Readiness>((worst, current) => readinessRank[current] > readinessRank[worst] ? current : worst, "READY");
}

export async function readFounderToday() {
  const sourceRef = "MEYOU_CONNECT_MVP_DATA_HUB_V1/00_งานวันนี้_Inbox+governed dependencies";
  try {
    const hub = await readBusinessDomain("founderToday");
    const [candidate, dq, system] = await Promise.all([readCandidates(), readDq(), readSystemHealth()]);
    const metrics = hub.records.map((row) => ({ metric: text(row.metric), value: nullable(row.value), meaning: text(row.meaning) }));
    const businessDq = dq.data && "business" in dq.data ? dq.data.business : [];
    const urgent = Array.isArray(businessDq) ? businessDq.filter((item) => {
      const row = item as ReadRecordV1<{ severity?: string | null; status?: string | null; required_action?: string | null }>;
      return row.data.status === "OPEN" && ["HIGH", "MEDIUM"].includes(row.data.severity ?? "");
    }).slice(0, 8).map((item) => {
      const row = item as ReadRecordV1<{ severity?: string | null; required_action?: string | null; issue_type?: string | null }>;
      return { canonical_id: row.canonical_id, severity: row.data.severity, issue_type: row.data.issue_type, next_action: row.data.required_action };
    }) : [];
    const overall = worstReadiness([candidate.readiness, dq.readiness, system.readiness]);
    const warnings: ReadWarningV1[] = [...candidate.warnings, ...dq.warnings, ...system.warnings];
    return makeEnvelope({
      interfaceKey: "founder.today", canonicalId: "READ:v1:founder.today", authority: "COMPOSITE_GOVERNED", sourceRef,
      observedAt: hub.observedAt, maxAgeSeconds: 300, readiness: overall,
      reasonCode: overall === "READY" ? undefined : "DEPENDENCY_READINESS_PROPAGATED",
      data: {
        today: metrics,
        need_my_action: urgent,
        warning_summary: warnings.slice(0, 12),
        ai_system_handled: system.data ? { operations: (system.data as { operations?: unknown }).operations ?? null } : null,
        source_readiness: {
          candidate: candidate.readiness,
          dq: dq.readiness,
          system: system.readiness,
          data_hub_today: "READY",
        },
      },
      warnings,
    });
  } catch (error) {
    return sourceFailure({ interfaceKey: "founder.today", canonicalId: "READ:v1:founder.today", authority: "COMPOSITE_GOVERNED", sourceRef, maxAgeSeconds: 300, error });
  }
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
  return makeEnvelope({
    interfaceKey: "unknown", canonicalId: "READ:v1:unknown", authority: "COMPOSITE_GOVERNED", sourceRef: "OFFICIAL_READ_V1",
    observedAt: NOW(), maxAgeSeconds: 300, readiness: "NOT_READY", reasonCode: "READ_ROUTE_NOT_FOUND", data: null,
    warnings: [{ code: "READ_ROUTE_NOT_FOUND", message: "Requested path is not part of Official Operational Read Contract V1." }],
  });
}
