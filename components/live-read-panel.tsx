"use client";

import { useEffect, useState } from "react";
import type { ReadEnvelopeV1, Readiness } from "@/lib/platform/contracts";

type Kind = "founder" | "candidate" | "job" | "client" | "partner" | "inbox" | "system" | "dq";

type AnyRecord = { canonical_id?: string; readiness?: Readiness; data?: Record<string, unknown> };

function displayValue(value: unknown) {
  if (value === null || value === undefined || value === "") return "—";
  if (typeof value === "boolean") return value ? "ใช่" : "ไม่";
  return String(value);
}

const labels: Record<string, string> = {
  display_name: "ชื่อ", status: "สถานะ", next_action: "Next Action", province: "จังหวัด", current_location: "พื้นที่",
  education: "การศึกษา", preferred_job: "งานที่สนใจ", company: "บริษัท", position: "ตำแหน่ง", location: "พื้นที่",
  headcount: "จำนวนรับ", wage: "ค่าแรง", shift: "กะ", transport_available: "รถรับส่ง", dorm_available: "หอพัก",
  company_name: "Client", crm_status: "CRM", payment_term: "เงื่อนไขจ่าย", verification_status: "การยืนยัน",
  partner_name: "Partner", partner_type: "ประเภท", parent_partner_id: "ทีม/ผู้แนะนำ", started_at: "เริ่ม",
  thread_name: "กลุ่ม/Thread", content_type: "ประเภทข้อความ", identity_status: "Identity", processing_status: "Processing",
  attachment_status: "ไฟล์", source: "Source", occurred_at: "เวลา", issue_type: "DQ", severity: "ระดับ", required_action: "ต้องทำ",
};

const fieldOrder: Record<Exclude<Kind, "founder" | "system">, string[]> = {
  candidate: ["display_name", "status", "next_action", "current_location", "province", "education", "preferred_job"],
  job: ["company", "position", "status", "location", "province", "headcount", "wage", "shift", "transport_available", "dorm_available"],
  client: ["company_name", "crm_status", "next_action", "province", "area", "payment_term", "verification_status"],
  partner: ["partner_name", "status", "partner_type", "province", "parent_partner_id", "started_at"],
  inbox: ["thread_name", "occurred_at", "content_type", "identity_status", "processing_status", "attachment_status"],
  dq: ["issue_type", "severity", "status", "required_action", "entity_type", "entity_id"],
};

function StateChip({ readiness }: { readiness: Readiness }) {
  return <span className={`readiness readiness-${readiness.toLowerCase()}`}>{readiness}</span>;
}

function RecordCards({ kind, value }: { kind: Exclude<Kind, "founder" | "system">; value: unknown }) {
  const source = Array.isArray(value) ? value : value ? [value] : [];
  const records = source.slice(0, 30) as AnyRecord[];
  if (!records.length) return <p className="live-empty">ไม่มี record ที่ส่งกลับอย่างปลอดภัยจาก source นี้</p>;
  return (
    <div className="live-record-list">
      {records.map((record, index) => {
        const data = record.data ?? {};
        return (
          <article className="live-record-card" key={record.canonical_id ?? index}>
            <div className="live-record-head">
              <strong>{record.canonical_id ?? "Record"}</strong>
              {record.readiness ? <StateChip readiness={record.readiness} /> : null}
            </div>
            <dl className="live-fields">
              {fieldOrder[kind].filter((field) => field in data).map((field) => (
                <div key={field}><dt>{labels[field] ?? field}</dt><dd>{displayValue(data[field])}</dd></div>
              ))}
            </dl>
          </article>
        );
      })}
    </div>
  );
}

function FounderData({ value }: { value: unknown }) {
  const data = (value ?? {}) as { today?: Array<{ metric?: string; value?: unknown; meaning?: string }>; need_my_action?: Array<Record<string, unknown>>; source_readiness?: Record<string, string>; ai_system_handled?: unknown };
  return (
    <div className="founder-live-grid">
      <article className="panel live-mini-panel"><h3>Today</h3><ul className="compact-list">{(data.today ?? []).slice(0, 12).map((item, i) => <li key={`${item.metric}-${i}`}><strong>{item.metric}</strong> — {displayValue(item.value)}{item.meaning ? ` · ${item.meaning}` : ""}</li>)}</ul></article>
      <article className="panel live-mini-panel"><h3>Need My Action</h3><ul className="compact-list">{(data.need_my_action ?? []).length ? data.need_my_action!.map((item, i) => <li key={String(item.canonical_id ?? i)}><strong>{displayValue(item.severity)}</strong> · {displayValue(item.next_action ?? item.issue_type)}</li>) : <li>ไม่มีรายการที่ส่งกลับจาก governed read</li>}</ul></article>
      <article className="panel live-mini-panel"><h3>Source readiness</h3><ul className="compact-list">{Object.entries(data.source_readiness ?? {}).map(([key, status]) => <li key={key}>{key}: <strong>{status}</strong></li>)}</ul></article>
      <article className="panel live-mini-panel"><h3>AI / System handled</h3><p className="safe-note">สถานะระบบถูกอ่านผ่าน server-side governed endpoint; ดูรายละเอียดที่เมนู ระบบ</p></article>
    </div>
  );
}

function SystemData({ value }: { value: unknown }) {
  const data = (value ?? {}) as { operations?: Record<string, unknown>; workers?: Array<Record<string, unknown>>; candidate_gap?: Record<string, unknown> };
  const operations = data.operations ?? {};
  return (
    <div className="system-live-grid">
      <article className="panel live-mini-panel"><h3>Operations</h3><ul className="compact-list"><li>Events: {displayValue(operations.completed_events)} / {displayValue(operations.total_events)} completed</li><li>Dead letter: {displayValue(operations.dead_letter_events)}</li><li>Ready commands: {displayValue(operations.ready_domain_commands)}</li><li>Scheduler age: {displayValue(operations.scheduler_age_seconds)} sec</li></ul></article>
      <article className="panel live-mini-panel"><h3>Workers</h3><ul className="compact-list">{(data.workers ?? []).slice(0, 30).map((worker) => <li key={String(worker.worker_key)}>{displayValue(worker.worker_key)} — <strong>{displayValue(worker.effective_status)}</strong></li>)}</ul></article>
      <article className="panel live-mini-panel"><h3>Candidate guard</h3><ul className="compact-list"><li>Unverified linkage: {displayValue(data.candidate_gap?.unverifiedCount)}</li><li>Verified linkage: {displayValue(data.candidate_gap?.verifiedCount)}</li></ul></article>
    </div>
  );
}

export function LiveReadPanel({ endpoint, kind, title = "ข้อมูลจริง" }: { endpoint: string; kind: Kind; title?: string }) {
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
        setState({ loading: false, envelope: null, error: "อ่านข้อมูลจาก server ไม่สำเร็จ" });
      });
    return () => controller.abort();
  }, [endpoint]);

  if (state.loading) return <section className="live-read-shell"><p className="eyebrow">LIVE READ V1</p><h2>{title}</h2><p className="live-loading">กำลังอ่าน authoritative source…</p></section>;
  if (state.error || !state.envelope) return <section className="notice notice-danger"><div><strong>Live read error</strong><p>{state.error}</p></div><span>NOT_READY</span></section>;

  const envelope = state.envelope;
  return (
    <section className="live-read-shell">
      <div className="live-read-head">
        <div><p className="eyebrow">LIVE READ V1</p><h2>{title}</h2><p>Source: {envelope.source_authority} · Freshness: {envelope.freshness.state}</p></div>
        <StateChip readiness={envelope.readiness} />
      </div>
      {envelope.reason_code ? <div className="live-reason"><strong>{envelope.reason_code}</strong></div> : null}
      {envelope.warnings.length ? <ul className="live-warning-list">{envelope.warnings.slice(0, 8).map((warning, i) => <li key={`${warning.code}-${i}`}><strong>{warning.code}</strong>{warning.count != null ? ` (${warning.count})` : ""} — {warning.message}</li>)}</ul> : null}
      {envelope.data == null ? <p className="live-empty">Source นี้ยังไม่พร้อม จึงไม่แสดง empty/0 แทนข้อมูลจริง</p> : kind === "founder" ? <FounderData value={envelope.data} /> : kind === "system" ? <SystemData value={envelope.data} /> : <RecordCards kind={kind} value={kind === "dq" && !Array.isArray(envelope.data) ? ([...(((envelope.data as { business?: unknown[] }).business) ?? []), ...(((envelope.data as { technical?: unknown[] }).technical) ?? [])]) : envelope.data} />}
      <p className="live-foot">Generated: {envelope.generated_at} · Observed: {envelope.freshness.observed_at ?? "unknown"}</p>
    </section>
  );
}
