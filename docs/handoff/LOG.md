# AI Handoff Log

รายการใหม่อยู่บนสุด (ดูรูปแบบใน `../AI_HANDOFF.md`)

## 2026-10-02 — Claude — Money↔People linking, Finance/Partners tabs, Founder WebApp v5
- Task: แก้ปัญหาที่ Founder พบว่า Dashboard ใช้งานจริงไม่ได้ — ไม่เห็นชื่อโรงงาน, ไม่เห็นหน้าการเงิน, "จบงานแล้ว" ไม่ขึ้น
- Root cause ที่เจอ: เงินจริง (รับจาก Inaba, จ่ายค่าคอม Partner) ถูกบันทึกใน `22_Finance_Cashbook` เป็นข้อความบรรยายอิสระ (เช่น "อาทิตย์ ยิวคิม") ไม่ได้เลือกจาก Candidate ID — ระบบจึงจับคู่อัตโนมัติไม่ได้ และ `05_Placement`/`08_Revenue`/`10_Commission` ว่างเปล่าจริง (ธุรกิจไม่ได้ใช้ชีตเหล่านี้เลย)
- Changes (Supabase): เพิ่ม `workplace_name` ใน jobs_v; แก้ `cashbook_v` (fix timestamp parsing bug ที่มี noncash note ต่อท้าย); เพิ่มตาราง `ops.cashbook_links` (tag เงิน↔Candidate/Partner, Supabase-only ไม่เขียนกลับ Sheets); เพิ่ม `dash.partners_payable_v`, `dash.list_cashbook/list_partners/list_partners_payable/link_cashbook_txn`; `candidates_v.completed_and_paid` เปลี่ยนมา derive จาก cashbook_links แทน Placement/Revenue ที่ว่างเปล่า
- Changes (WebApp): เพิ่มแท็บ Finance (ดู+ผูกรายการเงินกับ Candidate/Partner) และแท็บ Partners (ยอดค้างจ่ายต่อคน); Jobs แสดงชื่อโรงงานจริง (Thai Inaba Foods, มุโต้ะ ฯลฯ)
- Evidence: Partner 9 คนในระบบตรงกับชื่อใน Cashbook (มิ้นท์, อีฟ, หยก ฯลฯ); Cashbook 14 รายการ โหลดผ่าน RLS-gated RPC ได้ถูกต้อง
- Gate state: ไม่แตะ safety gate ใดๆ; `ops.cashbook_links` เป็นชั้น tag เสริม ไม่ใช่ source of truth ใหม่
- Next step: รอ Founder ผูกรายการ Cashbook ย้อนหลังทีละแถวผ่านเว็บ; พิจารณาเพิ่มคอลัมน์ Partner ใน `02_งาน_Job` ถ้าต้องการ track "ส่งงานให้ใคร"; ตั้งค่า ChatGPT Custom GPT Actions (endpoint `gpt-actions` deploy ไว้แล้ว รอ Founder ไปตั้งค่าในแอป ChatGPT)
- Blockers / needs Founder: ตัดสินใจเรื่องคอลัมน์ Partner ใน Job sheet; ไปตั้งค่า Custom GPT เมื่อพร้อม

## 2026-09-29 — Claude — Shadow import live, Founder Dashboard v1 deployed
- Task: เปิด shadow import gate (Founder-approved), deploy `datahub-shadow-import`, เพิ่ม Cashbook mapping, ตั้ง cron sync ทุก 5 นาที, สร้าง view `dash.founder_daily_v` + RBAC (deny-by-default), deploy WebApp v1 ไป Vercel `me-you-connect`
- Changes: migrations หลายไฟล์ (`ops.migration_entity_map` เพิ่ม Cashbook, `dash` schema ใหม่ทั้งหมด, `ops.backup_runs` บันทึก manual snapshot), Edge Function `datahub-shadow-import` v0→v2, `public/index.html` (WebApp)
- Evidence: `dash.founder_daily_v` ให้ผลตรงกับ Data Hub — Candidate 52, Job 17 (open headcount 134), Client 3, Partner 9, DQ 23 (critical 0), Cashbook 8 รายการ (230 บาท unreconciled); `core.*`/`finance.*` ยังเป็น 0 ตามดีไซน์ (business_master_apply_enabled=false)
- Gate state: เปิดเฉพาะ `migration_shadow_write_enabled=true` (Founder approved 2026-09-28); `business_master_apply_enabled`, `analytics_postgres_publish_enabled`, `production_cutover_approved`, `external_channel_webhooks_enabled` ยังปิดทั้งหมด
- Next step: ตรวจสอบตัวเลข "57 candidate submissions ตั้งแต่ 22 ก.ย." ที่ ChatGPT รายงาน (Claude ตรวจแล้วนับได้ผู้ส่งไม่ซ้ำ 9 คนใน LINE raw ช่วงเดียวกัน — ตัวเลขไม่ตรงกัน ต้องเทียบวิธีนับ), ใส่ token guard ให้ `raw-datahub-sync` (ยังไม่ทำเพราะเป็น pipeline ที่รันจริงอยู่), ทำ Alert Engine และ AI Executive Brief ตาม spec ของ ChatGPT
- Blockers / needs Founder: ตัดสินใจ AI provider สำหรับ Executive Brief (Claude API vs ChatGPT API + ใครจ่าย), แหล่งข้อมูลของเลข 57 จาก ChatGPT

## 2026-09-28 — Claude — Repo review + docs baseline
- Task: อ่าน repo ทั้งหมด, ตรวจสถานะจริงของ Supabase TEST และ Vercel แบบอ่านอย่างเดียว, ปรับ README/ROADMAP, สร้างโปรโตคอล handoff
- Changes: docs only (ไม่มี migration, ไม่มีการแก้ค่าใน DB)
- Evidence: safety gates ใน `config.system_settings` ตรงกับเอกสาร; Security Advisor 0 lint; Edge Functions 4 ตัว ACTIVE (`line-official-webhook`, `line-group-bot-webhook`, `line-backup-export`, `raw-datahub-sync`) source ยังไม่อยู่ใน repo; `ops.raw_inputs` LINE 3,681 แถว; `candidate.lead.received` 86 (ล่าสุด 2026-09-19); `ops.domain_commands` 86 แถว VALID/READY ไม่มี master effect; Vercel project `me-you-connect` มีอยู่
- Gate state: ไม่มีการแก้ safety gate; Production NOT_READY / OFF; Source of Truth = Google Sheets/Drive
- Next step: (1) ดึง source Edge Functions เข้า `supabase/functions/` (2) ตรวจว่าทำไมไม่มี lead ใหม่หลัง 2026-09-19 (3) สร้าง Founder Dashboard
- Blockers / needs Founder: ตัดสินใจเรื่องแยก PROD environment, ผู้รับ alert จริง, การอนุมัติ Production
