import Link from "next/link";
import type { ReactNode } from "react";
import { OfflineStatus } from "@/components/offline-status";
import { ReadinessBadge, readinessLabel } from "@/components/data-state";
import { canonicalSystem, modules, navOrder, type ModuleKey } from "@/lib/phase0";

export { ReadinessBadge } from "@/components/data-state";

export type ShellActive = ModuleKey | "more";

const mobileNav: Array<{ key: ShellActive; label: string; href: string }> = [
  { key: "dashboard", label: "หน้าแรก", href: "/" },
  { key: "candidates", label: "ผู้สมัคร", href: "/candidates" },
  { key: "jobs", label: "งาน", href: "/jobs" },
  { key: "inbox", label: "กล่องเข้า", href: "/inbox" },
  { key: "more", label: "เพิ่มเติม", href: "/more" },
];

function moduleHref(key: ModuleKey) {
  return key === "dashboard" ? "/" : `/${key}`;
}

export function AppShell({ active, children }: { active: ShellActive; children: ReactNode }) {
  return (
    <div className="app-frame">
      <aside className="sidebar">
        <div className="brand-block">
          <div className="brand-mark" aria-label="MeYou Connect">
            <img src="/myc-icon-192.png" alt="" width="46" height="46" />
          </div>
          <div>
            <strong>{canonicalSystem.brand}</strong>
            <p>{canonicalSystem.concept}</p>
          </div>
        </div>
        <nav className="nav-list" aria-label="เมนูหลัก">
          {navOrder.map((key) => {
            const item = modules[key];
            return (
              <Link key={key} href={moduleHref(key)} className={`nav-item ${active === key ? "active" : ""}`}>
                <span>{item.shortLabel}</span><small>{readinessLabel(item.readiness)}</small>
              </Link>
            );
          })}
        </nav>
        <div className="sidebar-foot"><span className="status-dot" /><div><strong>MYC สำหรับ Founder</strong><p>รอบทดสอบ · อ่านข้อมูลอย่างเดียว</p></div></div>
      </aside>
      <main className="main-area"><OfflineStatus />{children}</main>
      <nav className="mobile-bottom-nav" aria-label="เมนูมือถือ">
        {mobileNav.map(({ key, label, href }) => (
          <Link key={key} href={href} className={`mobile-bottom-item ${active === key ? "active" : ""}`}><span>{label}</span></Link>
        ))}
      </nav>
    </div>
  );
}

export function SourcePill({ children }: { children: ReactNode }) {
  return <span className="source-pill">{children}</span>;
}
