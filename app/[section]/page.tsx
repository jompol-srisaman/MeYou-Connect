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

const moduleDetails: Record<Exclude<ModuleKey, "dashboard">, string[]> = {
  candidates: [
    "Candidate Profile / readiness",
    "Missing Data / Next Action",
    "Documents & Evidence links",
    "Contact Timeline / Follow-up",
    "Job interest / Match context",
  ],
  jobs: [
    "Active Job / Position / Headcount",
    "Requirement / Wage / OT / Shift",
    "Transport / Dorm",
    "Client / Subcontractor link",
    "Candidate pipeline",
  ],
  inbox: [
    "LINE Raw feed แยกตามกลุ่ม / thread",
    "Sender / เวลา / Source",
    "Text / Image / File entry",
    "Verified Candidate / Job link เมื่อมีหลักฐาน",
    "Unknown / DQ เมื่อความสัมพันธ์ยังไม่ชัด",
  ],
  clients: [
    "Client profile / contact",
    "Active demand / Job link",
    "Pipeline / next action",
    "Payment term reference",
    "Demand review status",
  ],
  partners: [
    "Partner profile",
    "Attribution evidence",
    "Referral pipeline",
    "Placement outcome",
    "Commission visibility boundary",
  ],
  system: [
    "LINE ingestion health",
    "Raw / Event / Worker health",
    "Data Quality queue",
    "Source freshness / readiness",
    "Production gate status",
  ],
};

export default async function ModuleWorkspace({
  params,
}: {
  params: Promise<{ section: string }>;
}) {
  const { section } = await params;
  if (!validSections.has(section as ModuleKey)) notFound();

  const key = section as Exclude<ModuleKey, "dashboard">;
  const item = modules[key];

  return (
    <AppShell active={key}>
      <header className="page-header">
        <div>
          <p className="eyebrow">PWA V0.1 WORKSPACE</p>
          <h1>{item.label}</h1>
          <p className="page-subtitle">{item.summary}</p>
        </div>
        <ReadinessBadge readiness={item.readiness} />
      </header>

      <section className="notice">
        <div>
          <strong>Canonical source</strong>
          <p>{item.source}</p>
        </div>
        <SourcePill>{canonicalSystem.operationalSource.kind}</SourcePill>
      </section>

      <section className="two-column">
        <div className="panel">
          <p className="eyebrow">TARGET VIEW</p>
          <h2>ข้อมูลที่หน้านี้จะรวม</h2>
          <ul className="feature-list">
            {moduleDetails[key].map((detail) => (
              <li key={detail}>{detail}</li>
            ))}
          </ul>
        </div>

        <div className="panel">
          <p className="eyebrow">NEXT IMPLEMENTATION</p>
          <h2>งานถัดไป</h2>
          <p className="large-copy">{item.next}</p>
          <div className="divider" />
          <p className="safe-note">
            ไม่มีการเขียน Master โดยตรงจากหน้า UI ใน V0.1 และไม่มีการใช้ TEST shadow เป็น Operational Source
          </p>
        </div>
      </section>

      {key === "candidates" ? (
        <section className="notice notice-danger">
          <div>
            <strong>Data dependency boundary</strong>
            <p>
              Candidate live promotion ถูกถือเป็นงานของ DATA & AI SYSTEM MANAGER V2; Web App จะไม่สร้าง downstream pipeline ใหม่แข่งกับระบบเดิม
            </p>
          </div>
          <span>DQ BOUNDARY</span>
        </section>
      ) : null}

      {key === "inbox" ? (
        <section className="notice notice-warning">
          <div>
            <strong>Inbox safety boundary</strong>
            <p>
              V0.1 จะแสดง Raw/Evidence แบบ read-only ก่อน การผูก Entity หรือแก้ Master ต้องผ่าน verified relation + command/validator layer
            </p>
          </div>
          <span>READ ONLY FIRST</span>
        </section>
      ) : null}
    </AppShell>
  );
}
