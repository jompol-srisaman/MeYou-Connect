import Link from "next/link";
import { AppShell, ReadinessBadge } from "@/components/app-shell";
import { modules } from "@/lib/phase0";
import { featureFlags } from "@/lib/platform/feature-flags";
import { moduleRegistry } from "@/lib/platform/module-registry";

const operations = [
  ["ลูกค้า", "/clients", modules.clients.readiness],
  ["พาร์ตเนอร์", "/partners", modules.partners.readiness],
  ["ระบบ", "/system", modules.system.readiness],
] as const;

const plannedLabels: Record<string, string> = {
  finance: "การเงิน",
  payroll: "ค่าตอบแทนทีม",
  accounting: "บัญชี",
  "ai-matching": "จับคู่งานด้วย AI",
  "partner-portal": "พื้นที่พาร์ตเนอร์",
  "candidate-portal": "พื้นที่ผู้สมัคร",
};

export default function MorePage() {
  const planned = moduleRegistry.filter((item) => item.stage === "PLANNED");

  return (
    <AppShell active="more">
      <header className="page-header compact-page-header">
        <div>
          <p className="eyebrow">เมนูอื่น</p>
          <h1>เมนูเพิ่มเติม</h1>
          <p className="page-subtitle">รวมงานที่ใช้น้อยกว่าและส่วนที่เตรียมไว้สำหรับอนาคต เพื่อให้เมนูหลักใช้งานง่ายบนมือถือ</p>
        </div>
      </header>

      <section className="more-grid">
        {operations.map(([label, href, readiness]) => (
          <Link href={href} className="more-card" key={href}>
            <div>
              <strong>{label}</strong>
              <p>เปิดดู</p>
            </div>
            <ReadinessBadge readiness={readiness} />
          </Link>
        ))}
      </section>

      <section className="panel future-panel">
        <p className="eyebrow">เตรียมไว้สำหรับอนาคต</p>
        <h2>ส่วนที่ยังไม่เปิดใช้งาน</h2>
        <div className="future-module-list">
          {planned.map((item) => (
            <div className="future-module-row" key={item.id}>
              <div>
                <strong>{plannedLabels[item.id] ?? item.label}</strong>
                <p>จะเปิดเมื่อผ่านการตรวจและพร้อมใช้งาน</p>
              </div>
              <span className="state-chip">{featureFlags[item.flag] ? "เปิด" : "ปิด"}</span>
            </div>
          ))}
        </div>
      </section>
    </AppShell>
  );
}
