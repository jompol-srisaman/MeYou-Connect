// Reference contract for Engineering. Server-side use only.
// Extends Official Operational Read Contract V1; does not authorize direct browser reads.

export type CandidateReconciliationCategory =
  | "ALREADY_IN_MASTER_LINK_MISSING"
  | "NEW_CANDIDATE_NEEDS_PROMOTION"
  | "DUPLICATE"
  | "CONTEXT_ONLY"
  | "INVALID/NOISE"
  | "NEEDS_DQ";

export type ContextResolutionStatus =
  | "RESOLVED_REPLY"
  | "RESOLVED_RECENT_SENDER_CONTEXT"
  | "NEEDS_DQ";

export type WorkerReadiness = "READY" | "PARTIAL" | "NOT_STARTED" | "BLOCKED";

export type FileCapabilityStatus =
  | "CAPTURE_SUPPORTED"
  | "STORAGE_SUPPORTED"
  | "PARSE_SUPPORTED"
  | "SEMANTIC_AI_NOT_READY"
  | "UNSUPPORTED";

export type B2BResponseOutcome =
  | "ACCEPTED"
  | "REJECTED"
  | "NEED_INFO"
  | "APPOINTMENT"
  | "SLOT_CLOSED"
  | "REQUIREMENT_CHANGED"
  | "WAITING";

export const UNIFIED_INTAKE_V1 = {
  candidateReconciliation: {
    source: "ops.candidate_reconciliation_workbench_v",
    businessAuthority: "GOOGLE_SHEETS_DRIVE",
    directMasterWrite: false,
    masterDependentCategoriesRequireDataHubReadback: true,
  },
  contextResolver: {
    source: "ops.line_context_resolution_v",
    scope: ["source_account_ref", "thread_id", "sender_or_reply", "time"],
    replyConfidence: 100,
    recentSenderWindowSeconds: 120,
    recentSenderConfidence: 80,
    ambiguousFallback: "NEEDS_DQ",
    directMasterWrite: false,
  },
  workerReadiness: {
    source: "ops.unified_worker_readiness_v",
    registryAloneIsRunning: false,
  },
  fileIntelligence: {
    router: "ops.file_intelligence_route_v1",
    evidenceView: "ops.file_intelligence_compatibility_v",
    paidAiActivated: false,
    productionReady: false,
  },
  consent: {
    source: "ops.consent_readiness_v",
    authority: "MEYOU_CONNECT_MVP_DATA_HUB_V1/14_Consent_PDPA",
    failClosed: true,
    autoSubmitUntilVerifiedReadback: false,
  },
  b2bResponse: {
    map: "ops.b2b_response_event_map_v",
    eventKernel: "ops.events/register_event",
    directMasterWrite: false,
  },
} as const;

export const B2B_RESPONSE_EVENT_V1: Record<B2BResponseOutcome, string> = {
  ACCEPTED: "b2b.response.accepted",
  REJECTED: "b2b.response.rejected",
  NEED_INFO: "b2b.response.need_info",
  APPOINTMENT: "b2b.response.appointment",
  SLOT_CLOSED: "b2b.response.slot_closed",
  REQUIREMENT_CHANGED: "b2b.response.requirement_changed",
  WAITING: "b2b.response.waiting",
};
