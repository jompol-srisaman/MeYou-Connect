import type { Readiness } from "@/lib/platform/contracts";

export type ModuleKey =
  | "dashboard"
  | "candidates"
  | "jobs"
  | "inbox"
  | "clients"
  | "partners"
  | "system";

export const canonicalSystem = {
  brand: "MeYou Connect",
  shortName: "MYC",
  concept: "เชื่อมไปสู่โอกาสใหม่",
  operationalSource: {
    name: "MEYOU_CONNECT_MVP_DATA_HUB_V1",
    kind: "GOOGLE_SHEETS_DRIVE",
    spreadsheetId: "1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc",
    authority: "CURRENT_OPERATIONAL_SOURCE_OF_TRUTH",
  },
  supabase: {
    projectRef: "pgjmxdeafzogzsyawejs",
    role: "TECHNICAL_AUTHORITY_ONLY_IN_P0",
  },
  vercel: {
    projectName: "me-you-connect",
    projectId: "prj_KacHevpOexcBtcMtfrrSzz2QiGLR",
  },
  canonicalFlow:
    "Channel → Raw → Parse / Validate → Deduplicate → Route → Master Effect → Audit",
} as const;

export const modules: Record<
  ModuleKey,
  {
    label: string;
    shortLabel: string;
    readiness: Readiness;
    summary: string;
    source: string;
    next: string;
  }
> = {
  dashboard: {
    label: "Founder Dashboard",
    shortLabel: "ภาพรวม",
    readiness: "PARTIAL",
    summary: "Official Read V1 binding ทำงานแบบ governed composition; readiness จริงมาจาก endpoint",
    source: "COMPOSITE_GOVERNED",
    next: "ใช้ live readiness จาก /api/v1/read/founder/today",
  },
  candidates: {
    label: "Candidate Operations",
    shortLabel: "Candidate",
    readiness: "STALE",
    summary: "Data Hub อ่านได้ แต่ต้องแสดง STALE เมื่อ promotion guard ยังพบ unverified Raw linkage",
    source: "Data Hub Candidate Master + ops.candidate_promotion_gap_v guard",
    next: "ห้าม claim completeness จน UNPROMOTED_RAW_GAP เป็นศูนย์",
  },
  jobs: {
    label: "Job / Factory",
    shortLabel: "งาน",
    readiness: "PARTIAL",
    summary: "Canonical Job Master ผูกผ่าน server-side Official Read V1",
    source: "Data Hub Job Master",
    next: "ใช้ runtime readiness; missing header/auth ต้อง NOT_READY",
  },
  inbox: {
    label: "Unified Inbox",
    shortLabel: "Inbox",
    readiness: "PARTIAL",
    summary: "LINE Inbox ใช้ Supabase technical authority แบบ read-only และ redacted",
    source: "ops.line_inbox_v",
    next: "Data Manager ต้องยืนยัน read projection/grant ให้ตรง Contract V1",
  },
  clients: {
    label: "Client / B2B",
    shortLabel: "Client",
    readiness: "PARTIAL",
    summary: "Client Master อ่านผ่าน Data Hub server adapter; contact PII ถูก redacted",
    source: "Data Hub Client Master",
    next: "เปิด sensitive detail หลัง authenticated permission context เท่านั้น",
  },
  partners: {
    label: "Partner Management",
    shortLabel: "Partner",
    readiness: "PARTIAL",
    summary: "Partner Master อ่านผ่าน Data Hub server adapter; phone/LINE ไม่ออก browser ใน Preview",
    source: "Data Hub Partner Master",
    next: "คง evidence/attribution trace โดยไม่เปิด write action",
  },
  system: {
    label: "AI / System Health",
    shortLabel: "ระบบ",
    readiness: "PARTIAL",
    summary: "Operations/worker/backlog/promotion guard อ่านจาก Supabase technical surfaces",
    source: "SUPABASE_TECHNICAL",
    next: "แสดง NOT_STARTED ตามจริงและไม่ตีความเป็น healthy",
  },
};

export const navOrder: ModuleKey[] = [
  "dashboard",
  "candidates",
  "jobs",
  "inbox",
  "clients",
  "partners",
  "system",
];
