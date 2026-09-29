# MeYou Connect

Engineering repository สำหรับระบบ MeYou Connect / Work Connect (business ID namespace: `MYC-*`)

## Status (อัปเดต 2026-09-29)

| หัวข้อ | สถานะ |
|---|---|
| Technical build ใน TEST | COMPLETE ถึง Part 7 Wave 7G (`TEST_TECHNICAL_COMPLETE_EXTERNAL_ACTIVATION_BLOCKED`) |
| Shadow import (Sheets → Supabase) | **LIVE** — cron ทุก 5 นาที, 6 entity (Candidate, Client, Partner, Job, Data_Quality, Cashbook) |
| Founder WebApp | **LIVE** — https://me-you-connect-jompol-srisamans-projects.vercel.app (Founder-only, deny-by-default RBAC) |
| Production (PostgreSQL master / Portal / Province) | NOT_READY / OFF |
| Operational Source of Truth | Google Sheets + Google Drive (ยังไม่ cutover) |
| Supabase TEST project | `pgjmxdeafzogzsyawejs` |

รายละเอียดงานถัดไปดูที่ [`docs/ROADMAP.md`](docs/ROADMAP.md) · สเปก Dashboard ดูที่ [`docs/product/FOUNDER_DASHBOARD_SPEC.md`](docs/product/FOUNDER_DASHBOARD_SPEC.md)

## Architecture

| Part | เนื้อหา | สถานะ |
|---|---|---|
| 3 | Event / Automation Kernel (Raw → Event → Worker → Command → Audit) | TEST implemented |
| 4 | Supabase / PostgreSQL: core master, PII/consent, RLS, finance, shadow migration | TEST closed |
| 5 | Security / Reliability: production gates PG-001..015 | TEST closed, PROD NOT_READY |
| 6 | Analytics / Dashboard: KPI semantic layer | TEST closed, publish OFF |
| 7 | Candidate / Partner / Client Portal | TEST closed, external OFF |
| 8 | Shadow import + Founder WebApp (read-only, internal) | **LIVE (2026-09-29)** |

## โครงสร้าง repo

- `docs/` — สถานะรายรอบ, schema overview, runbook, open issues, roadmap, AI handoff, product spec
- `supabase/migrations/` — migration ทั้งหมด (source-controlled)
- `supabase/functions/` — source ของ Edge Functions (ยังไม่ครบ — ดู Known Gaps)
- `web/` — source ของ Founder WebApp ที่ deploy จริงบน Vercel
- `scripts/` — สคริปต์ตรวจสอบ/ช่วยงาน

## Known Gaps (2026-09-29)

- Edge Functions ที่ ACTIVE บน Supabase แต่ source ยังไม่อยู่ใน repo: `line-official-webhook`, `line-group-bot-webhook`, `line-backup-export`, `raw-datahub-sync`
- `raw-datahub-sync` เรียกด้วย publishable key เปล่า ไม่มี token guard (ต่างจากฟังก์ชันใหม่ `datahub-shadow-import`) — ยังไม่แก้เพราะเป็น pipeline ที่รันจริงอยู่ ต้องตรวจก่อนแก้
- Classifier ที่แปลง LINE เป็น candidate lead หยุดทำงานตั้งแต่ 2026-09-19 — ต้องสอบสาเหตุ

## กติกาสำคัญ

- Development ต้องทำใน **TEST** ก่อนเสมอ
- Production Source of Truth ปัจจุบันยังเป็น Google Sheets + Google Drive
- **ห้าม commit** API Key, Database Password, service-role key หรือ Secret ใดๆ ลง repository
- ห้ามเปิด safety gate (เช่น `production_cutover_approved`, `business_master_apply_enabled`) โดยไม่มีหลักฐานและการอนุมัติจริงจาก Founder
- ใช้ business ID namespace `MYC-*` เท่านั้น (`WC-*` เลิกใช้แล้ว)
- ข้อมูลอ่อนไหว (เลขบัญชี, เลขบัตร, เบอร์โทร, ข้อมูลสุขภาพละเอียด, LINE ID) **ห้าม** ดึงเข้า `dash.*` หรือแสดงบน WebApp — ดู `docs/product/FOUNDER_DASHBOARD_SPEC.md` หัวข้อ 6

## การทำงานร่วมกันระหว่าง AI

repo นี้เป็นสื่อกลางส่งต่องานระหว่าง AI หลายตัว (Claude, ChatGPT ฯลฯ) — อ่าน [`docs/AI_HANDOFF.md`](docs/AI_HANDOFF.md) ก่อนเริ่มงาน และบันทึกใน [`docs/handoff/LOG.md`](docs/handoff/LOG.md) ทุกครั้งที่จบงาน
