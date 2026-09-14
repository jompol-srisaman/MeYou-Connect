import Link from "next/link";
import { notFound } from "next/navigation";
import { AppShell, ReadinessBadge, SourcePill } from "@/components/app-shell";
import { canonicalSystem, modules, type ModuleKey } from "@/lib/phase0";

const validSections = new Set<ModuleKey>([
  "candidates",
  "jobs",
  "inbox",
  "clients",
  "partners",
  "system",
]);

type WorkspaceKey = Exclude<ModuleKey, "dashboard">;

const workspaceContent: Record<WorkspaceKey, { primary: string[]; secondary: string[] }> = {
  candidates: {
    primary: ["ค้นหา / รายชื่อ Candidate", "Profile + Status + Next Action", "Follow-up / Timeline", "Evidence links"],
    secondary: ["Match proposal ผ่าน command layer เท่านั้น", "Candidate live promotion ต้องผ่าน Data Manager canonical flow"],
  },
  jobs: {
    primary: ["Active / Inactive Jobs", "Requirement / Wage / OT / Shift", "Headcount / Pipeline", "Transport / Dorm"],
    secondary: ["Client/Sub source link", "Match context โดยไม่สร้างข้อมูลสมัครปลอม"],
  },
  inbox: {
    primary: ["LINE Raw feed แยก thread/source", "Text / Image / File evidence", "Verified entity link", "Unknown / DQ state"],
    secondary: ["Read-only first", "การผูก entity หรือเปลี่ยน Master ต้องผ่าน validator/permission"],
  },
  clients: {
    primary: ["Client profile / contact", "Active demand / Job links", "Follow-up / next action", "Payment term reference"],
    secondary: ["Read workspace ก่อน controlled writes", "ไม่มีการแก้ Master ตรงจาก UI"],
  },
  partners: {
    primary: ["Partner profile", "Candidate attribution", "Referral pipeline", "Placement outcome"],
    secondary: ["Evidence first", "Commission visibility แยกจาก payment control"],
  },
  system: {
    primary: ["LINE ingestion health", "Raw / Event / Worker readiness", "DQ queue", "Source freshness"],
    secondary: ["Feature flags / kill-switch boundary", "Production gate ยังปิดใน Preview"],
  },
};

export default async function ModuleWorkspace({ params }: { params: Promise<{ section: string }> }) {
  const { section } = await params;
  if (!validSections.has(section as ModuleKey)) notFound();

  const key = section as WorkspaceKey;
  const item = modules[key];
  const content = workspaceContent[key];

  return (
    <AppShell active={key}>
      <header className="page-header compact-page-header">
        <div>
          <p className="eyebrow">PWA V0.1 WORKSPACE</p>
          <h1>{item.label}</h1>
          <p className="page-subtitle">{item.summary}</p>
        </div>
        <ReadinessBadge readiness={item.readiness} />
      </header>

      <section className="workspace-status-card">
        <div>
          <span className="workspace-status-label">ข้อมูลใช้งานจริง</span>
          <strong>{item.readiness === "READY" ? "READY" : "NOT_READY"}</strong>
          <p>Source เป้าหมาย: {item.source}</p>
        </div>
        <SourcePill>{canonicalSystem.operationalSource.kind}</SourcePill>
      </section>

      <section className="workspace-grid">
        <article className="panel workspace-panel">
          <p className="eyebrow">เมื่อ Data Contract พร้อม</p>
          <h2>Founder จะทำอะไรได้จากหน้านี้</h2>
          <ul className="feature-list">
            {content.primary.map((detail) => <li key={detail}>{detail}</li>)}
          </ul>
        </article>

        <article className="panel workspace-panel boundary-panel">
          <p className="eyebrow">Safety / Boundary</p>
          <h2>ขอบเขตที่ยังล็อกไว้</h2>
          <ul className="feature-list">
            {content.secondary.map((detail) => <li key={detail}>{detail}</li>)}
          </ul>
        </article>
      </section>

      <section className="next-step-card">
        <div>
          <span>Next implementation</span>
          <strong>{item.next}</strong>
        </div>
        <Link href="/" className="secondary-button">กลับหน้า Today</Link>
      </section>

      {key === "candidates" ? (
        <section className="notice notice-danger">
          <div>
            <strong>Candidate data dependency</strong>
            <p>Live Candidate ยังคงขึ้นกับ canonical downstream fix / DQ ของ DATA & AI SYSTEM MANAGER V2 ห้ามสร้าง pipeline คู่ขนาน</p>
          </div>
          <span>DATA LOCK</span>
        </section>
      ) : null}

      {key === "inbox" ? (
        <section className="notice notice-warning">
          <div>
            <strong>Inbox read-only first</strong>
            <p>Raw/Evidence แสดงได้เมื่อ approved read surface พร้อม แต่ action ที่มีผลต่อ Master ต้องผ่าน command + validator + permission ก่อนเสมอ</p>
          </div>
          <span>READ ONLY</span>
        </section>
      ) : null}
    </AppShell>
  );
}
