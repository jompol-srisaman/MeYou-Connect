import Link from "next/link";
import { notFound } from "next/navigation";
import { AppShell, ReadinessBadge, SourcePill } from "@/components/app-shell";
import { LiveReadPanel } from "@/components/live-read-panel";
import { modules, type ModuleKey } from "@/lib/phase0";

const validSections = new Set<ModuleKey>(["candidates", "jobs", "inbox", "clients", "partners", "system"]);
type WorkspaceKey = Exclude<ModuleKey, "dashboard">;

const liveConfig: Record<WorkspaceKey, { endpoint: string; kind: "candidate" | "job" | "inbox" | "client" | "partner" | "system" }> = {
  candidates: { endpoint: "/api/v1/read/candidates", kind: "candidate" },
  jobs: { endpoint: "/api/v1/read/jobs", kind: "job" },
  inbox: { endpoint: "/api/v1/read/inbox/line", kind: "inbox" },
  clients: { endpoint: "/api/v1/read/clients", kind: "client" },
  partners: { endpoint: "/api/v1/read/partners", kind: "partner" },
  system: { endpoint: "/api/v1/read/system/health", kind: "system" },
};

export default async function ModuleWorkspace({ params }: { params: Promise<{ section: string }> }) {
  const { section } = await params;
  if (!validSections.has(section as ModuleKey)) notFound();
  const key = section as WorkspaceKey;
  const item = modules[key];
  const live = liveConfig[key];

  return (
    <AppShell active={key}>
      <header className="page-header compact-page-header">
        <div>
          <p className="eyebrow">OFFICIAL READ V1</p>
          <h1>{item.label}</h1>
          <p className="page-subtitle">{item.summary}</p>
        </div>
        <ReadinessBadge readiness={item.readiness} />
      </header>

      <section className="workspace-status-card">
        <div><span className="workspace-status-label">Canonical source</span><strong>{item.source}</strong><p>Runtime readiness จะแสดงจาก server endpoint ด้านล่าง</p></div>
        <SourcePill>{key === "system" || key === "inbox" ? "SUPABASE_TECHNICAL" : "GOOGLE_SHEETS_DRIVE"}</SourcePill>
      </section>

      <LiveReadPanel endpoint={live.endpoint} kind={live.kind} title="ข้อมูลใช้งานจริง" />

      <section className="next-step-card">
        <div><span>Safety boundary</span><strong>Read-only Preview · no protected Master writes</strong></div>
        <Link href="/" className="secondary-button">กลับหน้า Today</Link>
      </section>

      {key === "candidates" ? (
        <section className="notice notice-warning"><div><strong>Candidate completeness guard</strong><p>ถ้า `ops.candidate_promotion_gap_v` ยังมี unverified linkage หน้านี้ต้องเป็น STALE + UNPROMOTED_RAW_GAP และห้ามใช้จำนวนเป็น authoritative</p></div><span>GUARDED</span></section>
      ) : null}
      {key === "inbox" ? (
        <section className="notice notice-warning"><div><strong>Inbox sensitive data</strong><p>Preview แสดงเฉพาะ metadata ที่ลดความอ่อนไหว; sender reference และ message/raw summary ไม่ออกสู่ browser จน permission context พร้อม</p></div><span>REDACTED</span></section>
      ) : null}
    </AppShell>
  );
}
