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

export interface ReadWarningV1 {
  code: string;
  message: string;
  canonical_id?: string;
  count?: number;
}

export interface CandidateInventoryCompletenessV1 {
  readiness: Extract<Readiness, "READY" | "STALE">;
  reason_code?: string;
  unverified_count: number;
  verified_count: number;
  newest_unverified_at: string | null;
  observed_at: string | null;
}

export interface ReadEnvelopeV1<T> extends ReadMetaV1 {
  contract_version: "v1";
  interface_key: string;
  generated_at: string;
  data: T | null;
  candidate_inventory_completeness?: CandidateInventoryCompletenessV1;
  warnings: ReadWarningV1[];
}

export interface ReadContextV1 {
  actor_id: string;
  roles: string[];
  request_id: string;
  now: string;
}

export const OFFICIAL_READ_V1 = {
  founderToday: {
    key: "founder.today",
    route: "/api/v1/read/founder/today",
    authority: "COMPOSITE_GOVERNED",
  },
  candidates: {
    key: "candidate.list",
    route: "/api/v1/read/candidates",
    authority: "GOOGLE_SHEETS_DRIVE",
    sourceRef: "MEYOU_CONNECT_MVP_DATA_HUB_V1/01_Candidate",
    guard: "ops.candidate_promotion_gap_v",
  },
  jobs: {
    key: "job.list",
    route: "/api/v1/read/jobs",
    authority: "GOOGLE_SHEETS_DRIVE",
    sourceRef: "MEYOU_CONNECT_MVP_DATA_HUB_V1/02_งาน_Job",
  },
  clients: {
    key: "client.list",
    route: "/api/v1/read/clients",
    authority: "GOOGLE_SHEETS_DRIVE",
    sourceRef: "MEYOU_CONNECT_MVP_DATA_HUB_V1/03_Client",
  },
  partners: {
    key: "partner.list",
    route: "/api/v1/read/partners",
    authority: "GOOGLE_SHEETS_DRIVE",
    sourceRef: "MEYOU_CONNECT_MVP_DATA_HUB_V1/04_Partner",
  },
  lineInbox: {
    key: "inbox.line",
    route: "/api/v1/read/inbox/line",
    authority: "SUPABASE_TECHNICAL",
    sourceRef: "ops.line_inbox_v",
  },
  dq: {
    key: "dq.list",
    route: "/api/v1/read/dq",
    authority: "COMPOSITE_GOVERNED",
  },
  systemHealth: {
    key: "system.health",
    route: "/api/v1/read/system/health",
    authority: "SUPABASE_TECHNICAL",
    sourceRefs: [
      "ops.operations_health_v",
      "ops.worker_health_v",
      "ops.worker_backlog_v",
      "ops.candidate_promotion_gap_v",
    ],
  },
} as const;

export const OFFICIAL_READ_FRESHNESS_SECONDS = {
  googleDataHub: 300,
  lineInbox: 300,
  technicalDq: 300,
  systemHealth: 600,
  founderToday: 300,
} as const;

export const SAFE_WRITE_BOUNDARY =
  "Command -> Validate -> Permission -> Event -> Master Effect -> Audit" as const;

export const DIRECT_MASTER_WRITE_ALLOWED = false as const;

export type QueueableActionKind = "NOTE_PROPOSAL" | "FOLLOW_UP_PROPOSAL" | "MATCH_PROPOSAL";

export interface QueuedActionProposal {
  id: string;
  kind: QueueableActionKind;
  entityId: string;
  createdAt: string;
  requiresOnlineRevalidation: true;
  directMasterWrite: false;
}

export const OFFLINE_POLICY = {
  mode: "READ_ONLY_OR_QUEUED_PROPOSAL",
  directMasterWrite: false,
  revalidateQueuedActionsOnline: true,
  cacheApiResponses: false,
} as const;
