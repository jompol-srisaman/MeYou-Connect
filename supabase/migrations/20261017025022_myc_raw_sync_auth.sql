-- MYC raw-datahub-sync application-token gate and Cron #5 header update.
-- First apply this Cron #5 header-only update, then immediately deploy the matching
-- Edge Function code. The old handler ignores this extra header, avoiding an auth
-- outage window; security remains open until the new handler deploy succeeds.
-- This updates the existing command only; it does not change schedule or activate #11.
-- Secret values are read only by pg_cron at invocation time and are never selected into output.
DO $raw_sync_auth$
DECLARE
  v_job cron.job%ROWTYPE;
  v_after cron.job%ROWTYPE;
  v_new_command text;
  v_secret_count integer;
  v_restored_command text;
BEGIN
  SELECT * INTO v_job
  FROM cron.job
  WHERE jobid = 5
    AND jobname = 'meyou-connect-raw-datahub-sync';
  IF NOT FOUND OR NOT v_job.active OR v_job.schedule <> '*/5 * * * *' THEN
    RAISE EXCEPTION 'MYC_AUTH_PREFLIGHT_CRON5_IDENTITY_SCHEDULE';
  END IF;
  IF v_job.username <> 'postgres' THEN
    RAISE EXCEPTION 'MYC_AUTH_PREFLIGHT_CRON5_EXECUTOR';
  END IF;
  IF v_job.command !~* $$extensions\.http\s*\(\s*\(\s*'POST'\s*,\s*'https://pgjmxdeafzogzsyawejs\.supabase\.co/functions/v1/raw-datahub-sync'\s*,\s*array\s*\[$$
     OR (length(v_job.command) - length(replace(v_job.command, 'https://pgjmxdeafzogzsyawejs.supabase.co/functions/v1/raw-datahub-sync', ''))) / length('https://pgjmxdeafzogzsyawejs.supabase.co/functions/v1/raw-datahub-sync') <> 1 THEN
    RAISE EXCEPTION 'MYC_AUTH_PREFLIGHT_CRON5_ENDPOINT';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 11 AND NOT active) THEN
    RAISE EXCEPTION 'MYC_AUTH_PREFLIGHT_CRON11_MUST_REMAIN_INACTIVE';
  END IF;
  IF v_job.command !~* 'extensions\.http\s*\('
     OR (length(v_job.command) - length(replace(v_job.command, 'extensions.http_header', ''))) / length('extensions.http_header') <> 2
     OR v_job.command !~* 'extensions\.http_header\s*\(\s*''authorization''\s*,'
     OR v_job.command !~* 'extensions\.http_header\s*\(\s*''apikey''\s*,'
     OR v_job.command ~* 'x-myc-invoke-token' THEN
    RAISE EXCEPTION 'MYC_AUTH_PREFLIGHT_CRON5_COMMAND_SHAPE';
  END IF;
  SELECT count(*) INTO v_secret_count
  FROM vault.decrypted_secrets
  WHERE name = 'myc_shadow_import_invoke_token'
    AND decrypted_secret IS NOT NULL
    AND length(decrypted_secret) > 0;
  IF v_secret_count <> 1 THEN
    RAISE EXCEPTION 'MYC_AUTH_PREFLIGHT_EXISTING_TOKEN_UNAVAILABLE_OR_AMBIGUOUS';
  END IF;

  -- Match the two existing gateway headers and insert one server-side Vault lookup.
  -- All original URL, gateway headers, request body, and timeout literals are preserved.
  v_new_command := regexp_replace(
    v_job.command,
    $$((\[\s*extensions\.http_header\(\s*'authorization'\s*,\s*'[^']*'\s*\)\s*,\s*extensions\.http_header\(\s*'apikey'\s*,\s*'[^']*'\s*\)\s*)(\]))$$,
    $$\2, extensions.http_header('x-myc-invoke-token', (select decrypted_secret from vault.decrypted_secrets where name = 'myc_shadow_import_invoke_token')) \3$$,
    'i'
  );
  IF v_new_command = v_job.command
     OR (length(v_new_command) - length(replace(v_new_command, 'extensions.http_header', ''))) / length('extensions.http_header') <> 3
     OR v_new_command !~* 'x-myc-invoke-token' THEN
    RAISE EXCEPTION 'MYC_AUTH_CRON5_HEADER_INSERT_FAILED';
  END IF;
  v_restored_command := regexp_replace(
    v_new_command,
    $$,\s*extensions\.http_header\(\s*'x-myc-invoke-token'\s*,\s*\(select decrypted_secret from vault\.decrypted_secrets where name = 'myc_shadow_import_invoke_token'\)\s*\)\s*\]$$,
    $$]$$,
    'i'
  );
  IF v_restored_command <> v_job.command THEN
    RAISE EXCEPTION 'MYC_AUTH_CRON5_NONHEADER_COMMAND_CHANGE';
  END IF;

  -- Change only command so this caller needs no superuser authority over username.
  PERFORM cron.alter_job(job_id := v_job.jobid, command := v_new_command);

  SELECT * INTO v_after FROM cron.job WHERE jobid = 5;
  IF NOT FOUND
     OR v_after.jobname IS DISTINCT FROM v_job.jobname
     OR v_after.schedule IS DISTINCT FROM v_job.schedule
     OR v_after.database IS DISTINCT FROM v_job.database
     OR v_after.username IS DISTINCT FROM v_job.username
     OR v_after.active IS DISTINCT FROM v_job.active
     OR v_after.command IS DISTINCT FROM v_new_command THEN
    RAISE EXCEPTION 'MYC_AUTH_CRON5_IDENTITY_PRESERVATION_FAILED';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM cron.job
    WHERE jobid = 5 AND jobname = 'meyou-connect-raw-datahub-sync'
      AND active AND schedule = '*/5 * * * *'
      AND (length(command) - length(replace(command, 'extensions.http_header', ''))) / length('extensions.http_header') = 3
      AND command ~* 'x-myc-invoke-token'
  ) THEN
    RAISE EXCEPTION 'MYC_AUTH_CRON5_READBACK_FAILED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobid = 11 AND NOT active) THEN
    RAISE EXCEPTION 'MYC_AUTH_CRON11_STATE_CHANGED';
  END IF;
END
$raw_sync_auth$;

-- Safe readback: returns only identifiers, schedule/active flags, and boolean shape checks.
SELECT jobid, jobname, schedule, active,
       (command ~* 'x-myc-invoke-token') AS has_invoke_header,
       ((length(command) - length(replace(command, 'extensions.http_header', ''))) / length('extensions.http_header') = 3) AS expected_header_count
FROM cron.job
WHERE jobid IN (5, 11)
ORDER BY jobid;
