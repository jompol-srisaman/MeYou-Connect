import Link from "next/link";
import { AppShell, ReadinessBadge, SourcePill } from "@/components/app-shell";
import { LiveReadPanel } from "@/components/live-read-panel";
import { modules } from "@/lib/phase0";

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
          <p className="eyebrow">ข้อมูลล่าสุด</p>
          <h1>วันนี้ต้องทำอะไรบ้าง</h1>
          <p className="page-subtitle">
            ระบบจะแสดงเฉพาะข้อมูลที่อ่านได้อย่างปลอดภัย พร้อมบอกให้ชัดเมื่อข้อมูลยังไม่ครบ ไม่ล่าสุด หรือยังใช้งานไม่ได้
          </p>
        </div>
        <SourcePill>แหล่งข้อมูลรวม</SourcePill>
      </header>

      <section className="quick-grid" aria-label="ทางลัดหลัก">
        {quickLinks.map(([label, href, readiness]) => (
          <Link className="quick-link" href={href} key={href}>
            <strong>{label}</strong><ReadinessBadge readiness={readiness} />
          </Link>
        ))}
      </section>

      <LiveReadPanel endpoint="/api/v1/read/founder/today" kind="founder" title="ภาพรวมวันนี้" />

      <section className="two-column home-lower-grid">
        <div className="panel">
          <p className="eyebrow">แหล่งข้อมูล</p>
          <h2>ข้อมูลที่ใช้ในหน้านี้</h2>
          <p className="safe-note">
            ข้อมูลธุรกิจมาจากฐานข้อมูลกลางของ MYC ส่วนสถานะการทำงานของระบบมาจากข้อมูลตรวจสอบระบบ รายละเอียดเชิงเทคนิคดูได้ที่เมนู “ระบบ”
          </p>
        </div>
        <div className="panel safe-boundary-panel">
          <p className="eyebrow">ขอบเขตรอบทดสอบ</p>
          <h2>สิ่งที่ยังไม่เปิดในรอบนี้</h2>
          <ul className="compact-list">
            <li>ยังแก้ไขข้อมูลหลักจากหน้านี้ไม่ได้</li>
            <li>เมื่อออฟไลน์จะดูข้อมูลได้อย่างเดียว</li>
            <li>ข้อมูลที่ยังตรวจสอบไม่ครบจะมีคำเตือนชัดเจน</li>
            <li>ยังไม่เปิดใช้งานระบบจริงสำหรับ Production</li>
          </ul>
        </div>
      </section>
    </AppShell>
  );
}
