import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const sql=readFileSync(new URL('../docs/runbooks/sql/MYC_RAW_SYNC_AUTH_REVIEW.sql',import.meta.url),'utf8').replace(/\r\n/g,'\n');

test('Cron #5 update is identity/schedule guarded and leaves #11 inactive',()=>{
  assert.match(sql,/jobid\s*=\s*5[\s\S]*jobname\s*=\s*'meyou-connect-raw-datahub-sync'/i);
  assert.match(sql,/schedule\s*<>\s*'\*\/5 \* \* \* \*'/i);
  assert.match(sql,/extensions\\\.http\\s\*\\\(\\s\*\\\(\\s\*'POST'[\s\S]*raw-datahub-sync'[\s\S]*array\\s\*\\\[/i);
  assert.match(sql,/MYC_AUTH_PREFLIGHT_CRON5_ENDPOINT/);
  assert.match(sql,/jobid\s*=\s*11\s+AND NOT active/i);
  assert.match(sql,/cron\.alter_job\(job_id\s*:=\s*v_job\.jobid,\s*command\s*:=\s*v_new_command\)/i);
  assert.match(sql,/v_after\.schedule IS DISTINCT FROM v_job\.schedule[\s\S]*v_after\.database IS DISTINCT FROM v_job\.database[\s\S]*v_after\.username IS DISTINCT FROM v_job\.username[\s\S]*v_after\.active IS DISTINCT FROM v_job\.active/i);
  assert.match(sql,/MYC_AUTH_CRON5_IDENTITY_PRESERVATION_FAILED/);
  assert.doesNotMatch(sql,/cron\.alter_job\([^)]*v_job\.schedule/i);
});

test('formal migration matches the review SQL draft',()=>{
  const migration=readFileSync(new URL('../supabase/migrations/20261017025022_myc_raw_sync_auth.sql',import.meta.url),'utf8').replace(/\r\n/g,'\n');
  assert.equal(migration,sql);
});

test('only a Vault lookup is inserted as a header and secrets are not selected or printed',()=>{
  assert.match(sql,/extensions\.http_header\('x-myc-invoke-token', \(select decrypted_secret from vault\.decrypted_secrets where name = 'myc_shadow_import_invoke_token'\)\)/i);
  assert.match(sql,/v_restored_command <> v_job\.command/i);
  assert.doesNotMatch(sql,/select\s+decrypted_secret\s+from\s+vault\.decrypted_secrets\s*;/i);
  assert.doesNotMatch(sql,/authorization\s*[:=].*(eyJ|sb_secret|sb_publishable)/i);
});
