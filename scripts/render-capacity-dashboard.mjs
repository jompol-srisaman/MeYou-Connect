#!/usr/bin/env node
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const MiB = 1024 * 1024;
const DB_WARN = 250 * MiB;
const DB_STOP = 400 * MiB;
const SHADOW_STOP = 75 * MiB;
const PROVIDER_MB = 500_000_000;
const PR_URL = 'https://github.com/jompol-srisaman/MeYou-Connect/pull/29';

const metricNumbers = [
  'database_bytes', 'shadow_relation_bytes', 'open_shadow_sessions',
  'staged_shadow_sessions', 'open_alerts', 'active_capacity_alerts',
  'held_deliveries', 'ready_deliveries', 'verified_active_external_routes',
  'capacity_samples_24h', 'capacity_samples_retained', 'capacity_sample_limit'
];
const metricBooleans = [
  'external_delivery_enabled', 'migration_shadow_write_enabled',
  'business_master_apply_enabled', 'migration_target_apply_enabled',
  'production_cutover_approved', 'cron11_active', 'capacity_history_full'
];
const allowedRawKeys = new Set(['raw', 'ledger', 'synced', 'pending', 'retry', 'dead_letter', 'in_flight']);

function fail(message) { throw new TypeError(message); }
function nonnegativeNumber(value, name) {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) fail(`${name} must be a finite nonnegative number`);
  return value;
}
function validTimestamp(value, name) {
  if (typeof value !== 'string' || !Number.isFinite(Date.parse(value))) fail(`${name} must be a valid timestamp`);
  return value;
}

export function validatePayload(p) {
  if (!p || typeof p !== 'object' || Array.isArray(p)) fail('payload must be an object');
  if (!p.metrics || typeof p.metrics !== 'object' || Array.isArray(p.metrics)) fail('metrics must be an object');
  for (const key of metricNumbers) nonnegativeNumber(p.metrics[key], `metrics.${key}`);
  if (p.metrics.shadow_relation_bytes === null) fail('metrics.shadow_relation_bytes must be available');
  for (const key of metricBooleans) if (typeof p.metrics[key] !== 'boolean') fail(`metrics.${key} must be boolean`);
  validTimestamp(p.metrics.sampled_at, 'metrics.sampled_at');
  if (!Array.isArray(p.samples)) fail('samples must be an array');
  let previous = -Infinity;
  p.samples.forEach((s, i) => {
    if (!s || typeof s !== 'object' || Array.isArray(s)) fail(`samples[${i}] must be an object`);
    const t = Date.parse(validTimestamp(s.sampled_at, `samples[${i}].sampled_at`));
    if (t < previous) fail('samples must be ordered by sampled_at');
    previous = t;
    nonnegativeNumber(s.database_bytes, `samples[${i}].database_bytes`);
    nonnegativeNumber(s.shadow_relation_bytes, `samples[${i}].shadow_relation_bytes`);
  });
  if (!p.raw_sync || typeof p.raw_sync !== 'object' || Array.isArray(p.raw_sync)) fail('raw_sync must be an object');
  for (const key of Object.keys(p.raw_sync)) {
    if (!allowedRawKeys.has(key)) fail(`raw_sync contains unsupported field: ${key}`);
    nonnegativeNumber(p.raw_sync[key], `raw_sync.${key}`);
  }
  for (const key of allowedRawKeys) if (!(key in p.raw_sync)) fail(`raw_sync.${key} is required`);
  nonnegativeNumber(p.media_missing, 'media_missing');
  if (!['on', 'off'].includes(p.readonly)) fail('readonly must be on or off');
  if (!['INCOMPLETE', 'PASS'].includes(p.recovery_status)) fail('recovery_status must be INCOMPLETE or PASS');
  return p;
}

const escapeHtml = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
const fmt = n => new Intl.NumberFormat('th-TH', { maximumFractionDigits: 2 }).format(n);
const fmtMiB = n => `${fmt(n / MiB)} MiB`;
function dateLabel(value) {
  return new Intl.DateTimeFormat('th-TH', { dateStyle: 'long', timeStyle: 'short', timeZone: 'Asia/Bangkok' }).format(new Date(value)) + ' น. (เวลาไทย)';
}
function stateForDb(bytes) { return bytes >= DB_STOP ? ['หยุดรับ', 'stop'] : bytes >= DB_WARN ? ['เตือน', 'warn'] : ['ปกติ', 'ok']; }
function stateForShadow(bytes) { return bytes >= SHADOW_STOP ? ['หยุดรับ', 'stop'] : ['ปกติ', 'ok']; }
function progress(value, limit) { return Math.max(0, Math.min(100, value / limit * 100)); }
function bar(value, warn, stop, limit, label) {
  const width = progress(value, limit);
  const warnLeft = progress(warn, limit);
  const stopLeft = progress(stop, limit);
  return `<div class="bar" role="img" aria-label="${escapeHtml(label)}"><span class="fill" style="width:${width.toFixed(2)}%"></span><i class="marker warn-marker" style="left:${warnLeft.toFixed(2)}%"></i><i class="marker stop-marker" style="left:${stopLeft.toFixed(2)}%"></i></div>`;
}
function chart(samples) {
  if (!samples.length) return '<p class="muted">ยังไม่มีตัวอย่างตามช่วงเวลา จึงยังไม่มีกราฟ</p>';
  const w = 680, h = 150, pad = 14;
  const ratios = samples.flatMap(s => [s.database_bytes / DB_STOP, s.shadow_relation_bytes / SHADOW_STOP]);
  const maxRatio = Math.max(1, ...ratios);
  const coords = values => values.map((v, i) => `${pad + (samples.length === 1 ? (w - 2 * pad) / 2 : i * (w - 2 * pad) / (samples.length - 1))},${h - pad - (v / maxRatio) * (h - 2 * pad)}`);
  const dbPoints = coords(samples.map(s => s.database_bytes / DB_STOP)).join(' ');
  const shadowPoints = coords(samples.map(s => s.shadow_relation_bytes / SHADOW_STOP)).join(' ');
  const points = samples.map((s, i) => {
    const [x, y] = coords(samples.map(x => x.database_bytes / DB_STOP))[i].split(',').map(Number);
    return `<circle class="sample-point" cx="${x}" cy="${y}" r="3"><title>${escapeHtml(dateLabel(s.sampled_at))}; ฐานข้อมูล ${escapeHtml(fmtMiB(s.database_bytes))}</title></circle>`;
  }).join('');
  return `<svg class="chart" viewBox="0 0 ${w} ${h}" role="img" aria-label="กราฟสัดส่วนต่อเพดานจากตัวอย่างจริง ${samples.length} จุด"><line x1="${pad}" y1="${h - pad}" x2="${w - pad}" y2="${h - pad}" class="axis"/><polyline points="${dbPoints}" class="db-line"/><polyline points="${shadowPoints}" class="shadow-line"/>${points}</svg><div class="legend"><span class="db-key">ฐานข้อมูล / 400 MiB</span><span class="shadow-key">Shadow / 75 MiB</span><span class="muted">สัดส่วนเพดาน · ตัวอย่างจริง ${samples.length} จุด · ${escapeHtml(dateLabel(samples[0].sampled_at))} ถึง ${escapeHtml(dateLabel(samples.at(-1).sampled_at))}</span></div>`;
}

export function renderDashboard(input) {
  const p = validatePayload(input);
  const m = p.metrics;
  const [dbState, dbClass] = stateForDb(m.database_bytes);
  const [shadowState, shadowClass] = stateForShadow(m.shadow_relation_bytes);
  const syncGap = Math.max(0, p.raw_sync.raw - p.raw_sync.synced);
  const readonlyText = p.readonly === 'on' ? 'เปิด' : 'ปิด';
  const recovery = p.recovery_status === 'PASS' ? 'ผ่าน' : 'ยังไม่สมบูรณ์';
  const toggle = v => v ? 'เปิด' : 'ปิด';
  return `<!doctype html>
<html lang="th"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>สุขภาพระบบ MYC</title>
<style>
:root{color-scheme:light;--ink:#172a38;--muted:#5c6d78;--line:#d7e1e7;--paper:#f4f7f8;--card:#fff;--teal:#087e75;--amber:#b76e00;--red:#b42318;--blue:#2563a6}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.5 system-ui,"Segoe UI",sans-serif}main{max-width:1120px;margin:auto;padding:28px 20px 48px}header{display:flex;justify-content:space-between;align-items:flex-start;gap:20px;border-bottom:1px solid var(--line);padding-bottom:18px;margin-bottom:20px}h1{font-size:1.75rem;margin:0 0 4px}.sub,.muted{color:var(--muted)}.badge{display:inline-block;padding:5px 10px;border-radius:99px;font-weight:700;background:#fff1d6;color:#805000}.grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:16px}.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:18px;box-shadow:0 2px 8px #172a3808}.wide{grid-column:1/-1}h2{font-size:1.13rem;margin:0 0 12px}.big{font-size:1.65rem;font-weight:750;letter-spacing:-.02em}.state{font-weight:700}.ok{color:var(--teal)}.warn{color:var(--amber)}.stop{color:var(--red)}.bar{height:13px;background:#e8eef1;border-radius:20px;position:relative;overflow:hidden;margin:12px 0 7px}.fill{height:100%;display:block;background:var(--teal);border-radius:20px}.warn-marker,.stop-marker{position:absolute;top:-2px;height:17px;width:2px;background:var(--amber)}.stop-marker{background:var(--red)}.scale,.line{display:flex;justify-content:space-between;gap:10px;flex-wrap:wrap}.line{padding:7px 0;border-bottom:1px solid #eef2f4}.line:last-child{border:0}.chart{width:100%;height:auto;max-height:180px}.axis{stroke:var(--line);stroke-width:1}.db-line,.shadow-line{fill:none;stroke:var(--blue);stroke-width:2}.shadow-line{stroke:var(--teal);stroke-dasharray:5 4}.sample-point{fill:var(--blue);stroke:white;stroke-width:1}.legend{display:flex;gap:14px;align-items:center;flex-wrap:wrap;font-size:.88rem}.db-key:before,.shadow-key:before{content:"";display:inline-block;width:12px;height:3px;background:var(--blue);vertical-align:middle;margin-right:5px}.shadow-key:before{background:var(--teal)}a{color:var(--blue);font-weight:700}.foot{font-size:.9rem;margin-top:18px;color:var(--muted)}@media(max-width:720px){.grid{grid-template-columns:1fr}.wide{grid-column:auto}header{display:block}.badge{margin-top:10px}}
</style></head><body><main>
<header><div><h1>สุขภาพระบบ MYC</h1><div class="sub">ภาพรวมจากข้อมูลรวมที่บันทึก ${escapeHtml(dateLabel(m.sampled_at))}</div></div><span class="badge">สถานะการกู้คืน: ${escapeHtml(recovery)}</span></header>
<section class="grid">
<article class="card"><h2>พื้นที่ฐานข้อมูล</h2><div class="big">${escapeHtml(fmtMiB(m.database_bytes))}</div><div class="state ${dbClass}">ฐานข้อมูล: ${dbState}</div>${bar(m.database_bytes, DB_WARN, DB_STOP, PROVIDER_MB, 'พื้นที่ฐานข้อมูลเทียบเส้นเตือนและหยุดรับ') }<div class="scale"><span>เตือน ${fmt(DB_WARN / MiB)} MiB</span><span>หยุดรับ ${fmt(DB_STOP / MiB)} MiB</span><span>โควตาผู้ให้บริการ 500 MB (หน่วยฐานสิบ)</span></div></article>
<article class="card"><h2>Shadow relation</h2><div class="big">${escapeHtml(fmtMiB(m.shadow_relation_bytes))}</div><div class="state ${shadowClass}">Shadow: ${shadowState}</div>${bar(m.shadow_relation_bytes, SHADOW_STOP, SHADOW_STOP, SHADOW_STOP, 'ขนาด Shadow relation เทียบเพดาน')}<div class="scale"><span>เพดานหยุดรับ 75 MiB</span><span>OPEN ${fmt(m.open_shadow_sessions)} · STAGED ${fmt(m.staged_shadow_sessions)}</span></div></article>
<article class="card"><h2>ประตูความปลอดภัย</h2><div class="line"><span>Shadow write</span><strong>${toggle(m.migration_shadow_write_enabled)}</strong></div><div class="line"><span>Business master apply</span><strong>${toggle(m.business_master_apply_enabled)}</strong></div><div class="line"><span>Migration target apply</span><strong>${toggle(m.migration_target_apply_enabled)}</strong></div><div class="line"><span>Production cutover</span><strong>${toggle(m.production_cutover_approved)}</strong></div><div class="line"><span>Cron #11</span><strong>${toggle(m.cron11_active)}</strong></div><div class="line"><span>Read-only mode</span><strong>${readonlyText}</strong></div></article>
<article class="card"><h2>แจ้งเตือนและคิวงาน</h2><div class="line"><span>แจ้งเตือนที่เปิดอยู่</span><strong>${fmt(m.open_alerts)}</strong></div><div class="line"><span>Capacity alerts</span><strong>${fmt(m.active_capacity_alerts)}</strong></div><div class="line"><span>ส่งรอในคิว / พร้อมส่ง</span><strong>${fmt(m.held_deliveries)} / ${fmt(m.ready_deliveries)}</strong></div><div class="line"><span>ปลายทางภายนอกที่ยืนยันแล้ว</span><strong>${fmt(m.verified_active_external_routes)}</strong></div><p class="muted">การส่งแจ้งเตือนต้องอาศัยแอปภายในเครื่องและการตั้งค่าปลายทางที่อนุมัติ; รายงานนี้ไม่ส่งข้อมูลออก</p></article>
<article class="card"><h2>LINE Raw และการซิงก์</h2><div class="line"><span>Raw</span><strong>${fmt(p.raw_sync.raw)}</strong></div><div class="line"><span>Ledger / SYNCED</span><strong>${fmt(p.raw_sync.ledger)} / ${fmt(p.raw_sync.synced)}</strong></div><div class="line"><span>ค้างเทียบ SYNCED</span><strong>${fmt(syncGap)}</strong></div><div class="line"><span>Pending · Retry · DLQ · In-flight</span><strong>${fmt(p.raw_sync.pending)} · ${fmt(p.raw_sync.retry)} · ${fmt(p.raw_sync.dead_letter)} · ${fmt(p.raw_sync.in_flight)}</strong></div><div class="line"><span>สื่อที่ยังขาดการยืนยัน</span><strong>${fmt(p.media_missing)} รายการ</strong></div><div class="line"><span>ตัวอย่าง capacity ใน 24 ชั่วโมง</span><strong>${fmt(m.capacity_samples_24h)} จุดจริง</strong></div></article>
<article class="card"><h2>สถานะการส่งและพื้นที่เก็บ</h2><div class="line"><span>ส่งแจ้งเตือนภายนอก</span><strong>${toggle(m.external_delivery_enabled)}</strong></div><div class="line"><span>History capacity เต็ม</span><strong>${toggle(m.capacity_history_full)}</strong></div><div class="line"><span>ตัวอย่างสะสม / เพดาน</span><strong>${fmt(m.capacity_samples_retained)} / ${fmt(m.capacity_sample_limit)}</strong></div><p class="muted">สื่อที่ยังขาด: ${fmt(p.media_missing)} รายการ · สถานะ 24 ชั่วโมงแสดงจากตัวอย่างจริง ${fmt(m.capacity_samples_24h)} จุด</p></article>
<article class="card wide"><h2>แนวโน้มจากตัวอย่างที่มีจริง</h2>${chart(p.samples)}</article>
</section><p class="foot">ข้อมูลนี้เป็นภาพรวมสำหรับติดตาม guard และ backlog เท่านั้น · ตรวจงานที่ <a href="${PR_URL}" rel="noopener noreferrer">PR #29</a></p>
</main></body></html>`;
}

function parseArgs(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    if (!['--input', '--output'].includes(arg) || !argv[i + 1] || argv[i + 1].startsWith('--')) fail(`expected --input ABSJSON and --output ABSHTML`);
    const key = arg.slice(2);
    if (result[key]) fail(`${arg} may be supplied only once`);
    result[key] = argv[++i];
  }
  for (const key of ['input', 'output']) if (!result[key] || !path.isAbsolute(result[key])) fail(`--${key} must be an absolute path`);
  if (path.resolve(result.input).toLowerCase() === path.resolve(result.output).toLowerCase()) fail('input and output paths must differ');
  return result;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const data = JSON.parse(await readFile(args.input, 'utf8'));
  const html = renderDashboard(data);
  await writeFile(args.output, html, { encoding: 'utf8', flag: 'w' });
  process.stdout.write(`Dashboard written: ${args.output}; samples=${data.samples.length}; sync_fields=${Object.keys(data.raw_sync).length}\n`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().catch(error => {
    process.stderr.write(`render-capacity-dashboard: ${error.message}\n`);
    process.exitCode = 1;
  });
}
