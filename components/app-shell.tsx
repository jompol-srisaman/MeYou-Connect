import Link from "next/link";
import type { ReactNode } from "react";
import { canonicalSystem, modules, navOrder, type ModuleKey } from "@/lib/phase0";

function readinessLabel(readiness: string) {
  if (readiness === "READY") return "พร้อม";
  if (readiness === "PARTIAL") return "บางส่วน";
  if (readiness === "BLOCKED") return "ติด Dependency";
  return "ยังไม่มี";
}

const mobileNav: Array<{ key: ModuleKey; label: string }> = [
  { key: "dashboard", label: "หน้าแรก" },
  { key: "candidates", label: "ผู้สมัคร" },
  { key: "jobs", label: "งาน" },
  { key: "inbox", label: "กล่องเข้า" },
  { key: "system", label: "เพิ่มเติม" },
];

function moduleHref(key: ModuleKey) {
  return key === "dashboard" ? "/" : `/${key}`;
}

export function AppShell({
  active,
  children,
}: {
  active: ModuleKey;
  children: ReactNode;
}) {
  return (
    <div className="app-frame">
      <aside className="sidebar">
        <div className="brand-block">
          <div className="brand-mark" aria-label="MeYou Connect">
            <img src="/myc-icon.svg" alt="" width="46" height="46" />
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
              <Link
                key={key}
                href={moduleHref(key)}
                className={`nav-item ${active === key ? "active" : ""}`}
              >
                <span>{item.shortLabel}</span>
                <small>{readinessLabel(item.readiness)}</small>
              </Link>
            );
          })}
        </nav>

        <div className="sidebar-foot">
          <span className="status-dot" />
          <div>
            <strong>Founder PWA V0.1</strong>
            <p>Internal only · Safe Mode</p>
          </div>
        </div>
      </aside>

      <main className="main-area">{children}</main>

      <nav className="mobile-bottom-nav" aria-label="เมนูมือถือ">
        {mobileNav.map(({ key, label }) => (
          <Link
            key={key}
            href={moduleHref(key)}
            className={`mobile-bottom-item ${active === key ? "active" : ""}`}
          >
            <span>{label}</span>
          </Link>
        ))}
      </nav>
    </div>
  );
}

export function SourcePill({ children }: { children: ReactNode }) {
  return <span className="source-pill">{children}</span>;
}

export function ReadinessBadge({ readiness }: { readiness: string }) {
  return (
    <span className={`readiness readiness-${readiness.toLowerCase()}`}>
      {readinessLabel(readiness)}
    </span>
  );
}
