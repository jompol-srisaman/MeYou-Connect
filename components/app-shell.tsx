import Link from "next/link";
import type { ReactNode } from "react";
import { canonicalSystem, modules, navOrder, type ModuleKey } from "@/lib/phase0";

function readinessLabel(readiness: string) {
  if (readiness === "READY") return "พร้อม";
  if (readiness === "PARTIAL") return "บางส่วน";
  if (readiness === "BLOCKED") return "ติด Dependency";
  return "ยังไม่มี";
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
          <div className="brand-mark">MYC</div>
          <div>
            <strong>{canonicalSystem.brand}</strong>
            <p>{canonicalSystem.concept}</p>
          </div>
        </div>

        <nav className="nav-list" aria-label="เมนูหลัก">
          {navOrder.map((key) => {
            const item = modules[key];
            const href = key === "dashboard" ? "/" : `/${key}`;
            return (
              <Link
                key={key}
                href={href}
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
            <strong>Internal P0</strong>
            <p>ไม่เปิด External Portal</p>
          </div>
        </div>
      </aside>

      <main className="main-area">{children}</main>
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
