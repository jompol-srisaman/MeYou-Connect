export type DataReadiness = "READY" | "STALE" | "NOT_READY" | "BLOCKED";

export type SourceAuthority = "GOOGLE_SHEETS_DRIVE" | "SUPABASE_TECHNICAL";

export interface ReadEnvelope<T> {
  contractVersion: "v1";
  readiness: DataReadiness;
  source: SourceAuthority;
  updatedAt: string | null;
  data: T | null;
  reason?: string;
}

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
