import Link from "next/link";
import { AppShell, ReadinessBadge } from "@/components/app-shell";
import { modules } from "@/lib/phase0";
import { featureFlags } from "@/lib/platform/feature-flags";
import { moduleRegistry } from "@/lib/platform/module-registry";

const operations = [
  ["Client / B2B", "/clients", modules.clients.readiness],
  ["Partner", "/partners", modules.partners.readiness],
  ["System", "/system", modules.system.readiness],
] as const;

export default function MorePage() {
  const planned = moduleRegistry.filter((item) => item.stage === "PLANNED");

  return (
    <AppShell active="more">
      <header className="page-header compact-page-header">
        <div>
          <p className="eyebrow">MORE</p>
          <h1>เมนูเพิ่มเติม</h1>
          <p className="page-subtitle">งานรองและโมดูลอนาคตอยู่ที่นี่ เพื่อให้หน้า Founder Today และเมนูมือถือหลักยังเรียบง่าย</p>
        </div>
      </header>

      <section className="more-grid">
        {operations.map(([label, href, readiness]) => (
          <Link href={href} className="more-card" key={href}>
            <div>
              <strong>{label}</strong>
              <p>เปิด workspace</p>
            </div>
            <ReadinessBadge readiness={readiness} />
          </Link>
        ))}
      </section>

      <section className="panel future-panel">
        <p className="eyebrow">MODULAR ROADMAP</p>
        <h2>โมดูลที่เตรียมขอบเขตไว้แล้ว แต่ยังไม่เปิด</h2>
        <div className="future-module-list">
          {planned.map((item) => (
            <div className="future-module-row" key={item.id}>
              <div>
                <strong>{item.label}</strong>
                <p>{item.contract}</p>
              </div>
              <span className="state-chip">{featureFlags[item.flag] ? "ON" : "OFF"}</span>
            </div>
          ))}
        </div>
      </section>
    </AppShell>
  );
}
