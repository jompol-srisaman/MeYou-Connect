"use client";

import { useEffect, useState } from "react";
import { DataState, ReadinessBadge, freshnessLabel, readinessLabel, reasonLabel, sourceAuthorityLabel } from "@/components/data-state";
import type { ReadEnvelopeV1, Readiness } from "@/lib/platform/contracts";

type Kind = "founder" | "candidate" | "job" | "client" | "partner" | "inbox" | "system" | "dq";
type AnyRecord = { canonical_id?: string; readiness?: Readiness; data?: Record<string, unknown> };

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "ใช่" : "ไม่";
  return String(value);
}

function formatDate(value?: string | null) {
  if (!value) return "ยังตรวจเวลาไม่ได้";
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return value;
  return parsed.toLocaleString("th-TH", {
    timeZone: "Asia/Bangkok",
    dateStyle: "short",
    timeStyle: "short",
  });
}

const labels: Record<string, string> = {
  display_name: "ชื่อ",
  status: "สถานะ",
  next_action: "สิ่งที่ต้องทำต่อ",
  province: "จังหวัด",
  current_location: "พื้นที่",
  education: "การศึกษา",
  preferred_job: "งานที่สนใจ",
  company: "บริษัท",
  position: "ตำแหน่ง",
  location: "พื้นที่",
  headcount: "จำนวนรับ",
  wage: "ค่าแรง",
  shift: "กะ",
  transport_available: "รถรับส่ง",
  dorm_available: "หอพัก",
  company_name: "ลูกค้า",
  crm_status: "สถานะลูกค้า",
  payment_term: "เงื่อนไขจ่าย",
  verification_status: "การยืนยัน",
  partner_name: "พาร์ตเนอร์",
  partner_type: "ประเภท",
  parent_partner_id: "ทีม/ผู้แนะนำ",
  started_at: "เริ่ม",
  thread_name: "กลุ่ม/ห้องสนทนา",
  content_type: "ประเภทข้อความ",
  identity_status: "การเชื่อมผู้ติดต่อ",
  processing_status: "การประมวลผล",
  attachment_status: "ไฟล์",
  source: "แหล่งข้อมูล",
  occurred_at: "เวลา",
  issue_type: "ปัญหาข้อมูล",
  severity: "ระดับ",
  required_action: "สิ่งที่ต้องทำ",
};

const fieldOrder: Record<Exclude<Kind, "founder" | "system">, string[]> = {
  candidate: ["display_name", "status", "next_action", "current_location", "province", "education", "preferred_job"],
  job: ["company", "position", "status", "location", "province", "headcount", "wage", "shift", "transport_available", "dorm_available"],
  client: ["company_name", "crm_status", "next_action", "province", "area", "payment_term", "verification_status"],
  partner: ["partner_name", "status", "partner_type", "province", "parent_partner_id", "started_at"],
  inbox: ["thread_name", "occurred_at", "content_type", "identity_status", "processing_status", "attachment_status"],
  dq: ["issue_type", "severity", "status", "required_action", "entity_type", "entity_id"],
};

function sourceSectionLabel(key: string) {
  const value = key.toLowerCase();
  if (value.includes("candidate")) return "ผู้สมัคร";
  if (value.includes("job")) return "งาน";
  if (value.includes("client")) return "ลูกค้า";
  if (value.includes("partner")) return "พาร์ตเนอร์";
  if (value.includes("inbox") || value.includes("line")) return "กล่องข้อความ";
  if (value.includes("system") || value.includes("health")) return "ระบบ";
  if (value.includes("dq") || value.includes("quality")) return "คุณภาพข้อมูล";
  return key;
}

function RecordCards({ kind, value }: { kind: Exclude<Kind, "founder" | "system">; value: unknown }) {
  const source = Array.isArray(value) ? value : value ? [value] : [];
  const records = source.slice(0, 30) as AnyRecord[];
  if (!records.length) {
    return (
      <DataState
        variant="empty"
        title="ยังไม่มีรายการ"
        description="แหล่งข้อมูลพร้อม แต่ยังไม่มีรายการที่แสดงได้ในส่วนนี้"
      />
    );
  }

  return (
    <div className="live-record-list">
      {records.map((record, index) => {
        const data = record.data ?? {};
        return (
          <article className="live-record-card" key={record.canonical_id ?? index}>
            <div className="live-record-head">
              <strong>{record.canonical_id ?? "รายการ"}</strong>
              {record.readiness ? <ReadinessBadge readiness={record.readiness} /> : null}
            </div>
            <dl className="live-fields">
              {fieldOrder[kind].filter((field) => field in data).map((field) => (
                <div key={field}>
                  <dt>{labels[field] ?? field}</dt>
                  <dd>{displayValue(data[field])}</dd>
                </div>
              ))}
            </dl>
          </article>
        );
      })}
    </div>
  );
}

function FounderData({ value }: { value: unknown }) {
  const data = (value ?? {}) as {
    today?: Array<{ metric?: string; value?: unknown; meaning?: string }>;
    need_my_action?: Array<Record<string, unknown>>;
    source_readiness?: Record<string, string>;
    ai_system_handled?: unknown;
  };

  return (
    <div className="founder-live-grid">
      <article className="panel live-mini-panel">
        <h3>วันนี้</h3>
        {(data.today ?? []).length ? (
          <ul className="compact-list">
            {(data.today ?? []).slice(0, 12).map((item, i) => (
              <li key={`${item.metric}-${i}`}><strong>{item.metric}</strong> — {displayValue(item.value)}{item.meaning ? ` · ${item.meaning}` : ""}</li>
            ))}
          </ul>
        ) : <p className="safe-note">ยังไม่มีรายการสำหรับวันนี้จากข้อมูลที่พร้อมใช้งาน</p>}
      </article>

      <article className="panel live-mini-panel">
        <h3>ต้องทำเอง</h3>
        <ul className="compact-list">
          {(data.need_my_action ?? []).length
            ? data.need_my_action!.map((item, i) => <li key={String(item.canonical_id ?? i)}><strong>{displayValue(item.severity)}</strong> · {displayValue(item.next_action ?? item.issue_type)}</li>)
            : <li>ยังไม่มีรายการที่ต้องให้ Founder จัดการจากข้อมูลที่พร้อมใช้งาน</li>}
        </ul>
      </article>

      <article className="panel live-mini-panel">
        <h3>ความพร้อมของข้อมูล</h3>
        <ul className="compact-list">
          {Object.entries(data.source_readiness ?? {}).length
            ? Object.entries(data.source_readiness ?? {}).map(([key, status]) => <li key={key}>{sourceSectionLabel(key)}: <strong>{readinessLabel(status)}</strong></li>)
            : <li>ยังตรวจความพร้อมของแหล่งข้อมูลไม่ได้</li>}
        </ul>
      </article>

      <article className="panel live-mini-panel">
        <h3>ระบบจัดการให้แล้ว</h3>
        <p className="safe-note">งานที่ระบบทำได้เองจะแสดงที่นี่เมื่อข้อมูลพร้อม ส่วนรายละเอียดเชิงเทคนิคดูได้ที่เมนู “ระบบ”</p>
      </article>
    </div>
  );
}

function SystemData({ value }: { value: unknown }) {
  const data = (value ?? {}) as {
    operations?: Record<string, unknown>;
    workers?: Array<Record<string, unknown>>;
    candidate_gap?: Record<string, unknown>;
  };
  const operations = data.operations ?? {};

  return (
    <div className="system-live-grid">
      <article className="panel live-mini-panel">
        <h3>ภาพรวมระบบ</h3>
        <ul className="compact-list">
          <li>รายการที่ประมวลผลเสร็จ: {displayValue(operations.completed_events)} / {displayValue(operations.total_events)}</li>
          <li>รายการที่ต้องแก้ไข: {displayValue(operations.dead_letter_events)}</li>
          <li>คำสั่งที่รอดำเนินการ: {displayValue(operations.ready_domain_commands)}</li>
          <li>ตรวจระบบล่าสุด: {displayValue(operations.scheduler_age_seconds)} วินาทีที่แล้ว</li>
        </ul>
      </article>

      <article className="panel live-mini-panel">
        <h3>ตัวทำงานอัตโนมัติ</h3>
        <ul className="compact-list">
          {(data.workers ?? []).slice(0, 30).map((worker) => <li key={String(worker.worker_key)}>{displayValue(worker.worker_key)} — <strong>{displayValue(worker.effective_status)}</strong></li>)}
        </ul>
      </article>

      <article className="panel live-mini-panel">
        <h3>การตรวจข้อมูลผู้สมัคร</h3>
        <ul className="compact-list">
          <li>ยังเชื่อมไม่ครบ: {displayValue(data.candidate_gap?.unverifiedCount)}</li>
          <li>ยืนยันแล้ว: {displayValue(data.candidate_gap?.verifiedCount)}</li>
        </ul>
        <details className="technical-detail">
          <summary>รายละเอียดสำหรับตรวจระบบ</summary>
          <code>ops.candidate_promotion_gap_v</code>
        </details>
      </article>
    </div>
  );
}

function technicalDetails(envelope: ReadEnvelopeV1<unknown>) {
  return (
    <details className="technical-detail live-technical-detail">
      <summary>รายละเอียดสำหรับตรวจระบบ</summary>
      <dl>
        <div><dt>Interface</dt><dd>{envelope.interface_key}</dd></div>
        <div><dt>Source authority</dt><dd>{envelope.source_authority}</dd></div>
        <div><dt>Source ref</dt><dd>{envelope.source_ref}</dd></div>
        <div><dt>Reason code</dt><dd>{envelope.reason_code ?? "—"}</dd></div>
        <div><dt>Generated</dt><dd>{envelope.generated_at}</dd></div>
        <div><dt>Observed</dt><dd>{envelope.freshness.observed_at ?? "—"}</dd></div>
      </dl>
      {envelope.warnings.length ? (
        <ul className="technical-warning-list">
          {envelope.warnings.slice(0, 8).map((warning, index) => (
            <li key={`${warning.code}-${index}`}>{warning.code}{warning.count != null ? ` (${warning.count})` : ""}: {warning.message}</li>
          ))}
        </ul>
      ) : null}
    </details>
  );
}

export function LiveReadPanel({ endpoint, kind, title = "ข้อมูลใช้งาน" }: { endpoint: string; kind: Kind; title?: string }) {
  const [state, setState] = useState<{ loading: boolean; envelope: ReadEnvelopeV1<unknown> | null; error: string | null }>({ loading: true, envelope: null, error: null });

  useEffect(() => {
    const controller = new AbortController();
    setState({ loading: true, envelope: null, error: null });
    fetch(endpoint, { cache: "no-store", headers: { accept: "application/json" }, signal: controller.signal })
      .then(async (response) => {
        const body = await response.json() as ReadEnvelopeV1<unknown>;
        if (!response.ok && response.status !== 404) throw new Error(`HTTP ${response.status}`);
        return body;
      })
      .then((envelope) => setState({ loading: false, envelope, error: null }))
      .catch((error: unknown) => {
        if ((error as { name?: string }).name === "AbortError") return;
        setState({ loading: false, envelope: null, error: "อ่านข้อมูลไม่สำเร็จ กรุณาลองใหม่เมื่อการเชื่อมต่อพร้อม" });
      });
    return () => controller.abort();
  }, [endpoint]);

  if (state.loading) {
    return (
      <section className="live-read-shell">
        <p className="eyebrow">ข้อมูลล่าสุด</p>
        <h2>{title}</h2>
        <DataState variant="loading" title="กำลังโหลดข้อมูล" description="ระบบกำลังตรวจแหล่งข้อมูลและความพร้อมล่าสุด" />
      </section>
    );
  }

  if (state.error || !state.envelope) {
    return (
      <section className="live-read-shell">
        <p className="eyebrow">ข้อมูลล่าสุด</p>
        <h2>{title}</h2>
        <DataState variant="error" title="อ่านข้อมูลไม่สำเร็จ" description={state.error ?? "ยังไม่สามารถอ่านข้อมูลส่วนนี้ได้"} />
      </section>
    );
  }

  const envelope = state.envelope;
  const friendlyReason = reasonLabel(envelope.reason_code);
  const showTechnical = kind === "system";

  return (
    <section className="live-read-shell">
      <div className="live-read-head">
        <div>
          <p className="eyebrow">ข้อมูลล่าสุด</p>
          <h2>{title}</h2>
          <p>แหล่งข้อมูล: {sourceAuthorityLabel(envelope.source_authority)} · ความสดใหม่: {freshnessLabel(envelope.freshness.state)}</p>
        </div>
        <ReadinessBadge readiness={envelope.readiness} />
      </div>

      {envelope.reason_code ? <div className="live-reason"><strong>{friendlyReason}</strong></div> : null}

      {envelope.warnings.length ? (
        <ul className="live-warning-list">
          {envelope.warnings.slice(0, 8).map((warning, index) => (
            <li key={`${warning.code}-${index}`}>
              {reasonLabel(warning.code)}{warning.count != null ? ` (${warning.count})` : ""}
            </li>
          ))}
        </ul>
      ) : null}

      {envelope.data == null ? (
        <DataState
          variant="empty"
          title={envelope.readiness === "BLOCKED" ? "ยังเปิดดูข้อมูลส่วนนี้ไม่ได้" : "ข้อมูลส่วนนี้ยังไม่พร้อม"}
          description={friendlyReason}
        />
      ) : kind === "founder" ? (
        <FounderData value={envelope.data} />
      ) : kind === "system" ? (
        <SystemData value={envelope.data} />
      ) : (
        <RecordCards
          kind={kind}
          value={kind === "dq" && !Array.isArray(envelope.data)
            ? ([...(((envelope.data as { business?: unknown[] }).business) ?? []), ...(((envelope.data as { technical?: unknown[] }).technical) ?? [])])
            : envelope.data}
        />
      )}

      <p className="live-foot">ตรวจข้อมูลเมื่อ {formatDate(envelope.freshness.observed_at ?? envelope.generated_at)}</p>
      {showTechnical ? technicalDetails(envelope) : null}
    </section>
  );
}
