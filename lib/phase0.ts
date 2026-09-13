export type Readiness = "READY" | "PARTIAL" | "MISSING" | "BLOCKED";

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
    role: "TEST_SHADOW_AND_TECHNICAL_INTEGRATION",
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
    summary: "UI foundation พร้อมเริ่ม แต่ยังไม่ผูก Operational Source แบบ live",
    source: "Data Hub (official) + Supabase technical health",
    next: "ต่อ approved read adapter และแสดง freshness ทุก metric",
  },
  candidates: {
    label: "Candidate Operations",
    shortLabel: "Candidate",
    readiness: "BLOCKED",
    summary: "หน้าใช้งานสร้างได้ แต่ live candidate promotion มี downstream DQ ที่ทีม Data เป็นเจ้าของ",
    source: "Data Hub Candidate Master",
    next: "รอ canonical downstream fix; ห้ามสร้าง pipeline คู่ขนาน",
  },
  jobs: {
    label: "Job / Factory",
    shortLabel: "งาน",
    readiness: "PARTIAL",
    summary: "มี canonical Job Master และ Supabase read API foundation แล้ว",
    source: "Data Hub Job Master",
    next: "ต่อ official read adapter และใช้ Part 4 API contract เมื่อเหมาะสม",
  },
  inbox: {
    label: "Unified Inbox",
    shortLabel: "Inbox",
    readiness: "PARTIAL",
    summary: "LINE Raw/Event มีอยู่จริง แต่หน้า Inbox ยังต้องต่อ approved read surface และ verified entity links",
    source: "Supabase Raw/Event technical surface + Data Hub entity authority",
    next: "แสดง thread/source/text/image/file/DQ แบบ read-only ก่อนเปิด controlled actions",
  },
  clients: {
    label: "Client / B2B",
    shortLabel: "Client",
    readiness: "PARTIAL",
    summary: "มี Client Master, authz และ Client Demand Lite technical foundation",
    source: "Data Hub Client Master",
    next: "ทำ read workspace ก่อนเปิด controlled writes",
  },
  partners: {
    label: "Partner Management",
    shortLabel: "Partner",
    readiness: "PARTIAL",
    summary: "มี Partner Master, attribution model และ purpose-scoped portal projection foundation",
    source: "Data Hub Partner Master",
    next: "ทำ read workspace และ attribution evidence view",
  },
  system: {
    label: "AI / System Health",
    shortLabel: "ระบบ",
    readiness: "PARTIAL",
    summary: "Supabase มี event/worker/observability/LINE foundations แต่ Web UI ยังไม่มี",
    source: "Supabase technical surfaces + Data Hub DQ",
    next: "ต่อ health/readiness read APIs โดยไม่เปิด production gates",
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
