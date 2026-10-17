-- REVIEW PACKAGE ONLY. No source execution without exact Founder approval.
-- Requires a caller session setting myc.reclaim_approval after approval is recorded.
-- Maintenance: freeze ALL shadow writers first. Cron11 stays off.
\set ON_ERROR_STOP on
BEGIN READ WRITE;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL timezone = 'UTC';
SET LOCAL extra_float_digits = 3;
LOCK TABLE ops.shadow_import_sessions IN SHARE MODE;
LOCK TABLE ops.shadow_import_rows IN ACCESS EXCLUSIVE MODE;
DO $$
DECLARE n bigint; fp numeric;
BEGIN
 IF current_database()<>'postgres' THEN RAISE EXCEPTION 'WRONG_DATABASE'; END IF;
 IF current_setting('myc.reclaim_approval',true) IS DISTINCT FROM
    'MYC-RECLAIM-20261016-749964' THEN RAISE EXCEPTION 'FOUNDER_APPROVAL_REQUIRED'; END IF;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobid=11 AND active) THEN RAISE EXCEPTION 'CRON11_ACTIVE'; END IF;
 IF (SELECT count(*) FROM config.system_settings WHERE setting_key IN
    ('business_master_apply_enabled','migration_target_apply_enabled','production_cutover_approved')
    AND setting_value='false'::jsonb)<>3 THEN RAISE EXCEPTION 'CUTOVER_GATE_CHANGED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM config.system_settings WHERE setting_key='migration_shadow_write_enabled'
    AND setting_value='false'::jsonb) THEN RAISE EXCEPTION 'FREEZE_SHADOW_WRITERS_FIRST'; END IF;
 IF EXISTS(SELECT 1 FROM pg_constraint WHERE contype='f' AND confrelid='ops.shadow_import_rows'::regclass)
    THEN RAISE EXCEPTION 'INBOUND_FK_CHANGED'; END IF;
 IF (SELECT count(*) FROM ops.shadow_import_sessions)<>3028
    THEN RAISE EXCEPTION 'SESSIONS_CHANGED_REPREPARE'; END IF;
 SELECT coalesce(sum(('x'||substr(md5(to_jsonb(s)::text),1,16))::bit(64)::bigint),0)
 INTO fp FROM ops.shadow_import_sessions s;
 IF fp<>62814098099219885444::numeric THEN RAISE EXCEPTION 'SESSION_METADATA_CHANGED_REPREPARE'; END IF;
 IF EXISTS(SELECT 1 FROM ops.reconciliation_runs) OR EXISTS(SELECT 1 FROM ops.reconciliation_results)
    OR EXISTS(SELECT 1 FROM ops.cutover_rehearsals) OR EXISTS(SELECT 1 FROM ops.delta_batches)
    OR EXISTS(SELECT 1 FROM ops.delta_rows) OR EXISTS(SELECT 1 FROM ops.rehearsal_reconciliation_runs)
    OR EXISTS(SELECT 1 FROM ops.rehearsal_reconciliation_results) OR EXISTS(SELECT 1 FROM ops.rehearsal_target_rows)
    THEN RAISE EXCEPTION 'RECONCILIATION_CHANGED_REPREPARE'; END IF;
 SELECT count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint),0)
 INTO n,fp FROM ops.shadow_import_rows r;
 IF n<>786782 OR fp<>-3216402315079991706826::numeric
    THEN RAISE EXCEPTION 'SHADOW_CHANGED_REPREPARE'; END IF;
 WITH ranked AS (
   SELECT s.*,row_number() OVER(PARTITION BY source_system,source_file_id,expected_entities
     ORDER BY snapshot_at DESC,created_at DESC,session_id DESC) AS keep_rank
   FROM ops.shadow_import_sessions s WHERE status='VALIDATED'
 ), keep AS (
   SELECT session_id FROM ops.shadow_import_sessions
     WHERE status<>'VALIDATED' OR snapshot_at>='2026-10-09 08:42:39+00'::timestamptz
   UNION SELECT session_id FROM ranked WHERE keep_rank<=2
   UNION SELECT session_id FROM ops.shadow_import_rows
     WHERE validation_status<>'VALID' OR validation_issues<>'[]'::jsonb
 )
 SELECT count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint),0)
 INTO n,fp FROM ops.shadow_import_rows r WHERE session_id IN(SELECT session_id FROM keep);
 IF n<>36818 OR fp<>-2770658449854450349::numeric
    THEN RAISE EXCEPTION 'LIVE_RETENTION_SCOPE_CHANGED_REPREPARE'; END IF;
 -- Operator must independently re-read backup manifest/hash/restore PASS, <=24h RPO,
 -- both retained CSV copies, endpoint identity, disk headroom and recorded approval.
END $$;
TRUNCATE TABLE ops.shadow_import_rows; -- deliberately NO CASCADE / RESTART IDENTITY
COMMIT;
-- Disk is freed here. Shadow views are temporarily empty until Phase B commits.
-- After this COMMIT, recovery is a verified COPY roll-forward, not SQL ROLLBACK.
