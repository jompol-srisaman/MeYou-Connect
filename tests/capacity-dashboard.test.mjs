import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { renderDashboard, validatePayload } from '../scripts/render-capacity-dashboard.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const script = path.join(root, 'scripts', 'render-capacity-dashboard.mjs');
const MiB = 1024 * 1024;
const payload = () => ({
  metrics: {
    sampled_at: '2026-10-17T01:58:00Z', database_bytes: 143 * MiB,
    shadow_relation_bytes: 58 * MiB, database_state: 'OK', shadow_state: 'OK',
    open_shadow_sessions: 1, staged_shadow_sessions: 0, open_alerts: 2,
    active_capacity_alerts: 0, held_deliveries: 1, ready_deliveries: 3,
    verified_active_external_routes: 0, external_delivery_enabled: false,
    migration_shadow_write_enabled: false, business_master_apply_enabled: false,
    migration_target_apply_enabled: false, production_cutover_approved: false,
    cron11_active: false, capacity_samples_24h: 4, capacity_samples_retained: 10, capacity_sample_limit: 2016,
    capacity_history_full: false
  },
  samples: [
    { sampled_at: '2026-10-17T01:00:00Z', database_bytes: 140 * MiB, shadow_relation_bytes: 57 * MiB },
    { sampled_at: '2026-10-17T01:15:00Z', database_bytes: 143 * MiB, shadow_relation_bytes: 58 * MiB }
  ],
  raw_sync: { raw: 4749, ledger: 4749, synced: 4749, pending: 0, retry: 0, dead_letter: 0, in_flight: 0 },
  media_missing: 6, readonly: 'off', recovery_status: 'INCOMPLETE'
});

test('renders only supplied samples and the approved aggregate health fields', () => {
  const html = renderDashboard(payload());
  assert.match(html, /สุขภาพระบบ/);
  assert.match(html, /17 ตุลาคม 2569/);
  assert.match(html, /250 MiB/);
  assert.match(html, /400 MiB/);
  assert.match(html, /500 MB/);
  assert.match(html, /75 MiB/);
  assert.match(html, /ตัวอย่างจริง 2 จุด/);
  assert.match(html, /Cron #11/);
  assert.match(html, /การส่งแจ้งเตือนต้องอาศัยแอปภายในเครื่อง/);
  assert.match(html, /PR #29/);
  assert.equal((html.match(/class="sample-point"/g) || []).length, 2);
  assert.doesNotMatch(html, /24 ชั่วโมงจำลอง/);
});

test('classifies inclusive warning and stop boundaries with correct units', () => {
  const p = payload();
  p.metrics.database_bytes = 250 * MiB;
  p.metrics.shadow_relation_bytes = 75 * MiB;
  const html = renderDashboard(p);
  assert.match(html, /ฐานข้อมูล: เตือน/);
  assert.match(html, /Shadow: หยุดรับ/);
  p.metrics.database_bytes = 400 * MiB;
  assert.match(renderDashboard(p), /ฐานข้อมูล: หยุดรับ/);
  p.metrics.database_bytes = 500_000_000;
  assert.match(renderDashboard(p), /476\.84 MiB/);
  assert.match(renderDashboard(p), /500 MB/);
});

test('rejects malformed or unsafe numeric input and timestamps', () => {
  const p = payload();
  p.metrics.database_bytes = -1;
  assert.throws(() => validatePayload(p), /database_bytes/);
  const q = payload();
  q.samples[0].sampled_at = 'not-a-date';
  assert.throws(() => validatePayload(q), /sampled_at/);
  const r = payload();
  r.raw_sync.pending = Infinity;
  assert.throws(() => validatePayload(r), /pending/);
  assert.throws(() => validatePayload({ ...payload(), samples: 'fake' }), /samples/);
});

test('ignores unapproved payload fields and has no external code or assets', () => {
  const p = payload();
  p.private_note = '</title><img src=x onerror=alert(1)>';
  p.metrics.destination = '<svg onload=alert(1)>';
  p.samples[0].email = '</script><img src=x onerror=alert(1)>';
  const html = renderDashboard(p);
  assert.doesNotMatch(html, /<img|<script|onerror|onload|javascript:/i);
  assert.doesNotMatch(html, /<script\s+src|<link\s+[^>]*href|fetch\s*\(|XMLHttpRequest/i);
  assert.doesNotMatch(html, /onerror|private_note|destination/);
  const unsafe = payload();
  unsafe.samples[0].sampled_at = '</script><img src=x onerror=alert(1)>';
  assert.throws(() => renderDashboard(unsafe), /sampled_at/);
  const hrefs = [...html.matchAll(/\shref="([^"]+)"/g)].map(m => m[1]);
  assert.deepEqual(hrefs, ['https://github.com/jompol-srisaman/MeYou-Connect/pull/29']);
});

test('CLI writes standalone HTML and emits only the path plus aggregate counts', async () => {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'myc-capacity-dashboard-'));
  try {
    const input = path.join(dir, 'aggregate.json');
    const output = path.join(dir, 'dashboard.html');
    await writeFile(input, JSON.stringify(payload()), 'utf8');
    const run = spawnSync(process.execPath, [script, '--input', input, '--output', output], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    assert.match(run.stdout, /samples=2/);
    assert.match(run.stdout, /sync_fields=7/);
    assert.doesNotMatch(run.stdout, /4749|database_bytes|raw_sync/);
    const html = await readFile(output, 'utf8');
    assert.match(html, /<!doctype html>/i);
    assert.doesNotMatch(html, /<script\s+src|<link\s+[^>]*href/i);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
