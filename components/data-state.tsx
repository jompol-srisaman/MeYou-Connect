import type { ReactNode } from "react";
import type { Readiness } from "@/lib/platform/contracts";

export const READINESS_UI: Record<Readiness, { label: string; description: string }> = {
  READY: {
    label: "พร้อมใช้งาน",
    description: "ข้อมูลส่วนนี้พร้อมใช้ตามแหล่งข้อมูลที่กำหนด",
  },
  PARTIAL: {
    label: "ใช้งานได้บางส่วน",
    description: "มีข้อมูลให้ใช้ แต่บางส่วนยังไม่พร้อมหรือยังตรวจสอบไม่ครบ",
  },
  STALE: {
    label: "ข้อมูลอาจไม่ครบ/ไม่ล่าสุด",
    description: "ข้อมูลส่วนนี้ควรตรวจสอบอีกครั้งก่อนใช้ตัดสินใจ",
  },
  NOT_READY: {
    label: "ยังไม่พร้อม",
    description: "แหล่งข้อมูลหรือการเชื่อมต่อส่วนนี้ยังไม่พร้อมใช้งาน",
  },
  BLOCKED: {
    label: "ต้องแก้เงื่อนไขก่อน",
    description: "มีเงื่อนไขที่ต้องแก้หรืออนุมัติก่อนจึงจะใช้งานได้",
  },
};

export function readinessLabel(readiness: string) {
  return READINESS_UI[readiness as Readiness]?.label ?? readiness;
}

export function ReadinessBadge({ readiness }: { readiness: string }) {
  return (
    <span className={`readiness readiness-${readiness.toLowerCase()}`} title={READINESS_UI[readiness as Readiness]?.description}>
      {readinessLabel(readiness)}
    </span>
  );
}

export type DataStateVariant = "loading" | "empty" | "error";

const STATE_SYMBOL: Record<DataStateVariant, string> = {
  loading: "…",
  empty: "—",
  error: "!",
};

export function DataState({
  variant,
  title,
  description,
  action,
}: {
  variant: DataStateVariant;
  title: string;
  description?: string;
  action?: ReactNode;
}) {
  const role = variant === "error" ? "alert" : "status";
  const resolvedAction = action ?? (variant === "error" ? (
    <a className="secondary-button" href="" aria-label="ลองโหลดข้อมูลอีกครั้ง">ลองใหม่</a>
  ) : null);

  return (
    <div className={`data-state data-state-${variant}`} role={role} aria-live="polite">
      <span className="data-state-symbol" aria-hidden="true">{STATE_SYMBOL[variant]}</span>
      <div className="data-state-copy">
        <strong>{title}</strong>
        {description ? <p>{description}</p> : null}
      </div>
      {resolvedAction ? <div className="data-state-action">{resolvedAction}</div> : null}
    </div>
  );
}

export function sourceAuthorityLabel(authority: string) {
  if (authority === "GOOGLE_SHEETS_DRIVE") return "ฐานข้อมูล MYC";
  if (authority === "SUPABASE_TECHNICAL") return "ข้อมูลระบบ";
  if (authority === "COMPOSITE_GOVERNED") return "แหล่งข้อมูลรวม";
  return "แหล่งข้อมูล";
}

export function freshnessLabel(state: string) {
  if (state === "FRESH") return "ล่าสุด";
  if (state === "STALE") return "อาจไม่ล่าสุด";
  return "ยังตรวจเวลาไม่ได้";
}

const REASON_UI: Record<string, string> = {
  UNPROMOTED_RAW_GAP: "ข้อมูลผู้สมัครบางรายการยังเชื่อมเข้าทะเบียนไม่ครบ",
  GOOGLE_DATA_HUB_AUTH_NOT_CONFIGURED: "ยังเชื่อมต่อฐานข้อมูล MYC ไม่ได้ในรอบทดสอบนี้",
  GOOGLE_DATA_HUB_AUTH_INVALID: "การตั้งค่าการเชื่อมต่อฐานข้อมูล MYC ยังไม่ถูกต้อง",
  GOOGLE_DATA_HUB_AUTH_FAILED: "การเชื่อมต่อฐานข้อมูล MYC ไม่สำเร็จ",
  GOOGLE_DATA_HUB_READ_FAILED: "อ่านฐานข้อมูล MYC ไม่สำเร็จ",
  SUPABASE_SERVER_AUTH_NOT_CONFIGURED: "ยังเชื่อมต่อข้อมูลระบบไม่ได้ในรอบทดสอบนี้",
  SUPABASE_TECHNICAL_READ_FAILED: "อ่านข้อมูลสถานะระบบไม่สำเร็จ",
  DATA_HUB_REQUIRED_HEADER_MISSING: "รูปแบบข้อมูลต้นทางยังไม่พร้อมสำหรับการอ่าน",
  SENSITIVE_READ_BLOCKED: "ข้อมูลส่วนนี้ถูกปิดไว้ตามสิทธิ์การเข้าถึง",
  SENSITIVE_FIELDS_REDACTED: "ซ่อนข้อมูลส่วนบุคคลบางส่วนในรอบทดสอบ",
  READ_SOURCE_FAILED: "อ่านข้อมูลจากแหล่งข้อมูลไม่สำเร็จ",
};

export function reasonLabel(reasonCode?: string) {
  if (!reasonCode) return "ข้อมูลส่วนนี้ยังไม่พร้อมใช้งาน";
  return REASON_UI[reasonCode] ?? "ข้อมูลบางส่วนยังไม่พร้อมใช้งาน";
}
