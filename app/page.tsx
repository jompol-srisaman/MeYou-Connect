import Link from "next/link";
import { AppShell, ReadinessBadge, SourcePill } from "@/components/app-shell";
import { LiveReadPanel } from "@/components/live-read-panel";
import { canonicalSystem, modules } from "@/lib/phase0";

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
          <p className="eyebrow">FOUNDER TODAY · OFFICIAL READ V1</p>
          <h1>วันนี้ต้องทำอะไรบ้าง</h1>
          <p className="page-subtitle">
            อ่านข้อมูลผ่าน server-side governed contract เท่านั้น หาก Source หรือความครบถ้วนยังไม่พร้อม ระบบจะแสดง STALE / PARTIAL / NOT_READY แทนการเดา
          </p>
        </div>
        <SourcePill>COMPOSITE_GOVERNED</SourcePill>
      </header>

      <section className="quick-grid" aria-label="ทางลัดหลัก">
        {quickLinks.map(([label, href, readiness]) => (
          <Link className="quick-link" href={href} key={href}>
            <strong>{label}</strong><ReadinessBadge readiness={readiness} />
          </Link>
        ))}
      </section>

      <LiveReadPanel endpoint="/api/v1/read/founder/today" kind="founder" title="Founder operational view" />

      <section className="two-column home-lower-grid">
        <div className="panel">
          <p className="eyebrow">SOURCE CONTROL</p>
          <h2>Business authority</h2>
          <p className="safe-note">{canonicalSystem.operationalSource.name} remains the operational business Source of Truth. Supabase is technical authority only for approved P0 surfaces.</p>
        </div>
        <div className="panel safe-boundary-panel">
          <p className="eyebrow">SAFE BOUNDARY</p>
          <h2>สิ่งที่ PWA V0.1 จะไม่ทำ</h2>
          <ul className="compact-list">
            <li>ไม่ Direct-write protected Master</li>
            <li>ไม่ Cache `/api/**`</li>
            <li>Offline ไม่แก้ Master</li>
            <li>ไม่ใช้ Supabase business tables เป็น fallback</li>
            <li>Production cutover ยังเป็น Founder Gate</li>
          </ul>
        </div>
      </section>
    </AppShell>
  );
}
