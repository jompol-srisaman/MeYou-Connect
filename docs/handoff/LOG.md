# AI Handoff Log

รายการใหม่อยู่บนสุด (ดูรูปแบบใน `../AI_HANDOFF.md`)

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
