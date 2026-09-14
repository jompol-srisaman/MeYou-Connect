import Link from "next/link";
import { AppShell, ReadinessBadge, SourcePill } from "@/components/app-shell";
import { canonicalSystem, modules } from "@/lib/phase0";

const founderLanes = [
  {
    title: "Need My Action",
    tone: "danger",
    description: "งานที่ต้องให้ Founder ตัดสินใจหรือดำเนินการเอง",
    items: ["รอ Official Read Contract เพื่อคำนวณรายการจริง", "ไม่มีการสร้างรายการจำลอง"],
  },
  {
    title: "Today / Follow-up",
    tone: "brand",
    description: "นัดหมายและ Follow-up ที่ต้องทำวันนี้",
    items: ["สถานะข้อมูล: NOT_READY", "Source เป้าหมาย: Data Hub / approved read adapter"],
  },
  {
    title: "Urgent / Warning",
    tone: "warning",
    description: "ข้อผิดพลาด, DQ, deadline และความเสี่ยงที่ต้องเห็นก่อน",
    items: ["Candidate live readiness ยังติด Data dependency", "ระบบจะไม่ใช้ TEST shadow แทน Operational truth"],
  },
  {
    title: "AI / System Handled",
    tone: "success",
    description: "งานที่ระบบจัดการได้เองโดยไม่ต้องรบกวน Founder",
    items: ["PWA shell + safe update พร้อมใน Preview", "API caching ถูกปิดตาม policy"],
  },
] as const;

const quickLinks = [
  ["ผู้สมัคร", "/candidates", modules.candidates.readiness],
  ["งาน", "/jobs", modules.jobs.readiness],
  ["กล่องเข้า", "/inbox", modules.inbox.readiness],
  ["เพิ่มเติม", "/more", "PARTIAL"],
] as const;

export default function FounderDashboard() {
  return (
    <AppShell active="dashboard">
      <header className="page-header founder-header">
        <div>
          <p className="eyebrow">FOUNDER TODAY</p>
          <h1>วันนี้ต้องทำอะไรบ้าง</h1>
          <p className="page-subtitle">
            MYC แสดงสิ่งที่ต้องตัดสินใจและข้อยกเว้นก่อน ส่วนข้อมูลที่ยังไม่ผ่าน Official Contract จะแสดง NOT_READY แทนการเดา
          </p>
        </div>
        <SourcePill>{canonicalSystem.operationalSource.kind}</SourcePill>
      </header>

      <section className="quick-grid" aria-label="ทางลัดหลัก">
        {quickLinks.map(([label, href, readiness]) => (
          <Link className="quick-link" href={href} key={href}>
            <strong>{label}</strong>
            <ReadinessBadge readiness={readiness} />
          </Link>
        ))}
      </section>

      <section className="notice notice-warning">
        <div>
          <strong>Live Operational Read ยัง NOT_READY</strong>
          <p>
            Issue #2 ยังไม่ได้ส่ง canonical read interface กลับมา จึงยังไม่แสดงจำนวน Candidate, Follow-up, Revenue หรือ Inbox เป็นตัวเลขจริง
          </p>
        </div>
        <span>NO FAKE DATA</span>
      </section>

      <section className="founder-lane-grid" aria-label="Founder work lanes">
        {founderLanes.map((lane) => (
          <article className={`action-lane action-lane-${lane.tone}`} key={lane.title}>
            <div className="action-lane-head">
              <div>
                <p className="eyebrow">{lane.title}</p>
                <h2>{lane.description}</h2>
              </div>
              <span className="state-chip">NOT_READY</span>
            </div>
            <ul className="compact-list">
              {lane.items.map((item) => <li key={item}>{item}</li>)}
            </ul>
          </article>
        ))}
      </section>

      <section className="two-column home-lower-grid">
        <div className="panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">DATA READINESS</p>
              <h2>ความพร้อมของข้อมูลใช้งานจริง</h2>
            </div>
          </div>
          <div className="module-list">
            {["candidates", "jobs", "inbox", "clients", "partners", "system"].map((key) => {
              const item = modules[key as keyof typeof modules];
              return (
                <div className="module-row" key={key}>
                  <div>
                    <strong>{item.shortLabel}</strong>
                    <p>{item.summary}</p>
                  </div>
                  <ReadinessBadge readiness={item.readiness} />
                </div>
              );
            })}
          </div>
        </div>

        <div className="panel safe-boundary-panel">
          <p className="eyebrow">SAFE BOUNDARY</p>
          <h2>สิ่งที่ PWA V0.1 จะไม่ทำ</h2>
          <ul className="compact-list">
            <li>ไม่ Direct-write protected Master</li>
            <li>ไม่ Cache `/api/**`</li>
            <li>Offline ไม่แก้ Master</li>
            <li>ไม่ใช้ Supabase TEST shadow เป็นข้อมูลธุรกิจจริง</li>
            <li>Production cutover ยังเป็น Founder Gate</li>
          </ul>
        </div>
      </section>
    </AppShell>
  );
}
