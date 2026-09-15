import Link from "next/link";
import { notFound } from "next/navigation";
import { AppShell, ReadinessBadge, SourcePill } from "@/components/app-shell";
import { LiveReadPanel } from "@/components/live-read-panel";
import { modules, type ModuleKey } from "@/lib/phase0";

const validSections = new Set<ModuleKey>(["candidates", "jobs", "inbox", "clients", "partners", "system"]);
type WorkspaceKey = Exclude<ModuleKey, "dashboard">;

const liveConfig: Record<WorkspaceKey, { endpoint: string; kind: "candidate" | "job" | "inbox" | "client" | "partner" | "system" }> = {
  candidates: { endpoint: "/api/v1/read/candidates", kind: "candidate" },
  jobs: { endpoint: "/api/v1/read/jobs", kind: "job" },
  inbox: { endpoint: "/api/v1/read/inbox/line", kind: "inbox" },
  clients: { endpoint: "/api/v1/read/clients", kind: "client" },
  partners: { endpoint: "/api/v1/read/partners", kind: "partner" },
  system: { endpoint: "/api/v1/read/system/health", kind: "system" },
};

const founderCopy: Record<WorkspaceKey, { title: string; summary: string; source: string }> = {
  candidates: {
    title: "ผู้สมัคร",
    summary: "ดูรายชื่อ สถานะ และสิ่งที่ต้องติดตาม โดยระบบจะเตือนเมื่อข้อมูลผู้สมัครยังตรวจสอบไม่ครบ",
    source: "ฐานข้อมูลผู้สมัคร MYC",
  },
  jobs: {
    title: "งานและโรงงาน",
    summary: "ดูงานที่เปิด เงื่อนไข และข้อมูลสำคัญสำหรับคัดเลือกผู้สมัคร",
    source: "ฐานข้อมูลงาน MYC",
  },
  inbox: {
    title: "กล่องข้อความ",
    summary: "ดูข้อความและไฟล์ที่ระบบรับเข้ามา โดยซ่อนข้อมูลอ่อนไหวตามสิทธิ์การเข้าถึง",
    source: "ข้อมูลจากช่องทางรับข้อความ",
  },
  clients: {
    title: "ลูกค้า",
    summary: "ดูสถานะลูกค้า งานที่เกี่ยวข้อง และสิ่งที่ต้องติดตามต่อ",
    source: "ฐานข้อมูลลูกค้า MYC",
  },
  partners: {
    title: "พาร์ตเนอร์",
    summary: "ดูข้อมูลพาร์ตเนอร์ ทีมที่เกี่ยวข้อง และสถานะการทำงานร่วมกัน",
    source: "ฐานข้อมูลพาร์ตเนอร์ MYC",
  },
  system: {
    title: "ระบบ",
    summary: "ดูความพร้อมของการเชื่อมต่อ แหล่งข้อมูล และรายละเอียดสำหรับตรวจสอบระบบ",
    source: "ข้อมูลตรวจสอบระบบ",
  },
};

export default async function ModuleWorkspace({ params }: { params: Promise<{ section: string }> }) {
  const { section } = await params;
  if (!validSections.has(section as ModuleKey)) notFound();
  const key = section as WorkspaceKey;
  const item = modules[key];
  const live = liveConfig[key];
  const copy = founderCopy[key];

  return (
    <AppShell active={key}>
      <header className="page-header compact-page-header">
        <div>
          <p className="eyebrow">ข้อมูลล่าสุด</p>
          <h1>{copy.title}</h1>
          <p className="page-subtitle">{copy.summary}</p>
        </div>
        <ReadinessBadge readiness={item.readiness} />
      </header>

      <section className="workspace-status-card">
        <div>
          <span className="workspace-status-label">แหล่งข้อมูล</span>
          <strong>{copy.source}</strong>
          <p>สถานะด้านล่างอัปเดตตามข้อมูลที่อ่านได้จริงในรอบทดสอบ</p>
        </div>
        <SourcePill>{key === "system" || key === "inbox" ? "ข้อมูลระบบ" : "ฐานข้อมูล MYC"}</SourcePill>
      </section>

      <LiveReadPanel endpoint={live.endpoint} kind={live.kind} title="ข้อมูลใช้งาน" />

      <section className="next-step-card">
        <div>
          <span>สถานะการใช้งาน</span>
          <strong>รอบทดสอบนี้อ่านข้อมูลอย่างเดียว และยังไม่แก้ไขข้อมูลหลัก</strong>
        </div>
        <Link href="/" className="secondary-button">กลับหน้าวันนี้</Link>
      </section>

      {key === "candidates" ? (
        <section className="notice notice-warning">
          <div>
            <strong>ข้อมูลผู้สมัครยังตรวจสอบไม่ครบ</strong>
            <p>ผู้สมัครบางรายการจากช่องทางรับข้อมูลยังเชื่อมเข้าทะเบียนไม่ครบ จึงอาจไม่ครบหรือไม่ล่าสุด และยังไม่ใช้จำนวนรวมเป็นตัวเลขยืนยัน</p>
          </div>
          <span>กำลังตรวจสอบ</span>
        </section>
      ) : null}

      {key === "inbox" ? (
        <section className="notice notice-warning">
          <div>
            <strong>มีการปกป้องข้อมูลส่วนบุคคล</strong>
            <p>รอบทดสอบจะแสดงเฉพาะข้อมูลที่จำเป็นต่อการทำงาน ข้อมูลผู้ส่งและเนื้อหาที่อ่อนไหวจะยังถูกซ่อนไว้จนกว่าสิทธิ์การเข้าถึงจะพร้อม</p>
          </div>
          <span>ปกป้องข้อมูล</span>
        </section>
      ) : null}
    </AppShell>
  );
}
