# AI Handoff Log

รายการใหม่อยู่บนสุด (ดูรูปแบบใน `../AI_HANDOFF.md`)

## 2026-10-17 14:06Bangkok — Codex — Reconcile deployed V10 source; coordinate Web Issue30
- Task: Founder asked checkedV10source/migrations push, real E2E/media/Finance-Partner-Consent and24h monitoring; final handoff in English/max8lines
- Changes: canonicalV10files/formal migrations matched fresh deployed readback; recorded raw-sync403/HMAC401, bounded media retries, terminal/event-lock safeguards and exact protected fingerprints. No redeploy/reclaim needed in this continuation
- Evidence:65unit/contract tests and2real PostgreSQL tests passed before gap; fresh source hashes identical07:04UTC.07:06Data Bot6new scoped mappings/6COMPLETED/6SYNCED/2Candidate proposal effects/0Finance commands.07:05Raw=ledger=SYNCED4,762; DB149,892,243bytes/readonlyoff;17capacitysamples/maxgap~20min/no>25mingap; capacityemailSENT1
- Gate state: INCOMPLETE; Cron11/Shadowgate/master+cutoverfalse. Earliest24h18Oct09:14Bangkok with actual coverage review. OA/provider replay/concurrency,6media bytes,source Finance/Partner/Consent remainOPEN
- Ownership: WebIssue30 independent read-only security/RLS/source-authority audit and separate proposals; CodexPR29 source/local recovery/provider E2E/media/release. No overlapping deploys
- Next step: push reviewed V10checkpoint and publish Issue28/PR29 evidence, coordinate source pointers withIssue30; continue actual provider/media tests without invented finance/consent. No confirmed media download artifact; local bridge gap02:58–07:04UTC recorded honestly

## 2026-10-17 — Codex + Luna6 — Approved reclaim complete; V4/capacity controls deployed
- Task: ต่อ Issue28/PR29 ตาม Founder approval MYC-RECLAIM-20261016-749964; ไม่ทำ recovery ซ้ำ
- Changes: encrypted recovery kit verified offsite/separate Founder-only key; exact reclaim complete/ordinary write restored; temporary roles NOLOGIN/deprivileged; deployed deltaV4/75MiBshadow/400MiBDBstop/250MiBwarning; existing Cron3 bounded collector; real Founder Gmail receipt/queue; native myc-recovery heartbeat/private aggregate dashboard
- Evidence: full dump133,444,414bytes SHA256d5e01082b062538c265b4c2322419a02a60fb418a6f5604c6ab1f099f949247d; encrypted195,415,924bytes downloaded/decrypted/hash verified; DB1,647,651,987→149,367,955bytes; protected36,818rows/3,028sessions fingerprints unchanged; actualdelta69rows/replayzero; all4,749Raw canonicalSheets exactonce/allledgerSYNCED; owner INBOX receipt1a1479f1993096a4; physical guards/concurrency/ACL tested isolated
- Gate state: INCOMPLETE; Cron11false/Shadowgatefalse/master+cutoverfalse;02:38UTC DB149,712,019bytes/readonlyoff/no capacityalert. Observation started17Oct02:13:59UTC, earliest24h18Oct09:14Bangkok with actual coverage check
- Next step: read MYC_RECOVERY_EXECUTION_20261016.md, MYC_PERMANENT_PROTECTION_ACCEPTANCE_20261017.md and MYC_CAPACITY_MONITOR_OPERATIONS_20261017.md. Complete reviewed LINE terminal/concurrency/media retry fixes, actual provider E2E, media/object-byte/source finance reconciliation. Keep PR draft; no Cron restart/incident closure
- Blocker / needs Founder: no repeated delete/password/passphrase approval. Six media mirrors unresolved; actual provider test may need one non-PII OA/group message after deployment ready. Clock cannot be accelerated for24h evidence

## 2026-10-16 — Codex + Luna6 — Full PostgreSQL backup/restore PASS; reclaim approval pending
- Task: ดำเนิน MYC Recovery ต่อจาก Issue28/PR29 บนเครื่องเดิม; ไม่ติดตั้ง pgAdmin/ไม่ใช้บริการเสียเงิน
- Changes: ใช้ backup reader ผ่าน TLS Session Pooler5432, PostgreSQL17.6 ใน Docker; เก็บ secret เฉพาะเครื่อง/DPAPIและกันไฟล์ Password ออกจาก Git; ทำ full consistent dump และ fresh network-none restore; บันทึก backup/restore PASS ใน control เดิม; เพิ่มรายงานผลและ exact reclaim review SQL/approval package
- Evidence: dump133,444,414bytes SHA256 d5e01082b062538c265b4c2322419a02a60fb418a6f5604c6ab1f099f949247d; snapshot08:42:41 UTC;214 tables/23 schemas/5 sequences/roles/catalog/ACL ตรงกัน; independent local package21 files re-read/hash PASS; full-shadow extraction rollback786,782rows/fingerprint PASS บน disposable clone
- Gate state: PostgreSQL logical backup/restore PASS; overall recovery INCOMPLETE; broader business/media/document/finance DR ไม่อ้างว่า PASS; source shadow786,782,Raw4,749,readonly on,Cron11false ณ14:10 UTC; no source cleanup/guard deployment/cutover
- Next step: อ่าน MYC_POSTGRES_RESTORE_RESULT_20261016.md และ MYC_SHADOW_RECLAIM_APPROVAL_20261016.md; ขอ Founder อนุมัติ archive-only749,964/keep36,818/all3,028 sessions; ซ้อม reclaim/retained COPY/rollback บน clone PASS แล้ว; หลังอนุมัติให้ live recheck+freeze แล้วจึงทำตาม exact SQL
- Blocker / needs Founder: explicit deletion approval เท่านั้นในขั้นถัดไป; ร่าง guard50MiB ต่ำกว่า retained footprint ต้องแก้/ทดสอบก่อนเปิด import; Cron11 ห้ามเปิดจน restart gates เดิมครบ

## 2026-10-16 — Codex + Luna6 — Local PostgreSQL backup preflight and AGENTS.md
- Task: ต่อ MYC Recovery จาก PR29; Full PostgreSQL Backup + isolated Restore Test เป็น gate แรก; Founder ขอคำสั่งทำงานตามลำดับใน `AGENTS.md`
- Changes: clone recovery branch เข้า workspace ว่าง; เพิ่ม `AGENTS.md`; เตรียม official Supabase PostgreSQL17.6 tool image ตรง source release; อัปเดตผล preflight ใน `docs/runbooks/MYC_RECOVERY_PROGRESS_20261016.md`; ไม่มีการแก้ DB หรือ deploy code
- Evidence: live DB1,647,520,915bytes/read-only on/Cron11false; shadow786,782/sessions3,028/Raw4,730/backup_artifacts0; pg_dump/pg_restore17.6 พร้อม; repo/Preview/Production Actions secret metadata ทั้งหมด0; workflow ที่พบเป็น web typecheck/build; Luna6 review instructions ไม่พบข้อบกพร่อง
- Gate state: **INCOMPLETE**; full dump และ isolated restore **NOT STARTED** เพราะไม่มี PostgreSQL authentication; ไม่ลบข้อมูล ไม่รีเซ็ตรหัส ไม่เปิด Cron11 หรือ cutover gates และไม่ลงทะเบียน backup PASS
- Next step: ใช้ connection เดิมจาก private local environment/password prompt หรือ authorized secret store แล้วทำ full consistent dump + independent hash/readback + isolated restore/comparison ตาม handoff
- Blocker / needs Founder: Founder ไม่ทราบรหัส DB เดิม; ChatGPT SQL connector ไม่ได้ให้รหัสสำหรับ pg_dump; GitHub metadata ที่ตรวจไม่มี credential source; handoff ยังไม่อนุญาต password reset ห้ามส่งรหัส/connection ที่มีรหัสผ่านผ่านแชทหรือ GitHub
- Documentation note: README อ้าง `docs/AI_HANDOFF.md` แต่ไฟล์นั้นไม่มีใน recovery branch ปัจจุบัน; ใช้ runbook ปัจจุบันกับ log นี้เป็นหลักฐาน โดยไม่สมมติเนื้อหาไฟล์ที่หายไป

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
