import { AppShell, ReadinessBadge, SourcePill } from "@/components/app-shell";
import { canonicalSystem, modules, navOrder } from "@/lib/phase0";

const todayCards = [
  ["Candidate ใหม่", "รอ Live Adapter"],
  ["ต้องโทรวันนี้", "รอ Live Adapter"],
  ["นัดสมัคร", "รอ Live Adapter"],
  ["Start", "รอ Live Adapter"],
  ["Follow-up Due", "รอ Live Adapter"],
  ["Collected", "รอ Live Adapter"],
] as const;

export default function FounderDashboard() {
  return (
    <AppShell active="dashboard">
      <header className="page-header">
        <div>
          <p className="eyebrow">FOUNDER CONTROL CENTER</p>
          <h1>ภาพรวมวันนี้</h1>
          <p className="page-subtitle">
            หน้าแรกของ MYC Internal Operations — แสดงเฉพาะข้อมูลที่ระบุแหล่งและความพร้อมชัดเจน
          </p>
        </div>
        <SourcePill>{canonicalSystem.operationalSource.kind}</SourcePill>
      </header>

      <section className="notice notice-warning">
        <div>
          <strong>Operational Live Adapter ยังไม่เชื่อม</strong>
          <p>
            ตัวเลขธุรกิจด้านล่างจึงไม่ถูกเดาหรือดึงจาก Supabase TEST shadow มาแทนข้อมูลจริง
          </p>
        </div>
        <span>SAFE MODE</span>
      </section>

      <section className="metric-grid" aria-label="ตัวชี้วัดวันนี้">
        {todayCards.map(([label, value]) => (
          <article className="metric-card" key={label}>
            <span>{label}</span>
            <strong className="metric-pending">{value}</strong>
            <small>Source: Data Hub</small>
          </article>
        ))}
      </section>

      <section className="two-column">
        <div className="panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">P0 MODULES</p>
              <h2>ความพร้อมของหน้าหลัก</h2>
            </div>
          </div>
          <div className="module-list">
            {navOrder.map((key) => {
              const item = modules[key];
              return (
                <div className="module-row" key={key}>
                  <div>
                    <strong>{item.label}</strong>
                    <p>{item.summary}</p>
                  </div>
                  <ReadinessBadge readiness={item.readiness} />
                </div>
              );
            })}
          </div>
        </div>

        <div className="panel">
          <div className="panel-head">
            <div>
              <p className="eyebrow">SOURCE CONTROL</p>
              <h2>ระบบที่ Web App ต้องเคารพ</h2>
            </div>
          </div>
          <dl className="detail-list">
            <div>
              <dt>Operational Source</dt>
              <dd>{canonicalSystem.operationalSource.name}</dd>
            </div>
            <div>
              <dt>Supabase</dt>
              <dd>{canonicalSystem.supabase.projectRef}</dd>
            </div>
            <div>
              <dt>Supabase Role</dt>
              <dd>{canonicalSystem.supabase.role}</dd>
            </div>
            <div>
              <dt>Vercel</dt>
              <dd>{canonicalSystem.vercel.projectName}</dd>
            </div>
          </dl>
        </div>
      </section>

      <section className="panel flow-panel">
        <p className="eyebrow">CANONICAL FLOW</p>
        <h2>เส้นทางข้อมูลที่ห้ามข้าม</h2>
        <code>{canonicalSystem.canonicalFlow}</code>
      </section>
    </AppShell>
  );
}
