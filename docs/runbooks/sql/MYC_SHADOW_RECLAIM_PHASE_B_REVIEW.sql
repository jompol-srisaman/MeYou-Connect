-- REVIEW PACKAGE ONLY. Run immediately after approved Phase A on SAME endpoint.
-- Client must first verify retained CSV SHA256 from the approval package.
-- COPY path belongs to local backup-client container; password never belongs here.
\set ON_ERROR_STOP on
BEGIN READ WRITE;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '180s';
SET LOCAL timezone = 'UTC';
SET LOCAL extra_float_digits = 3;
LOCK TABLE ops.shadow_import_sessions IN SHARE MODE;
LOCK TABLE ops.shadow_import_rows IN ACCESS EXCLUSIVE MODE;
DO $$ DECLARE fp numeric; BEGIN
 IF current_setting('myc.reclaim_approval',true) IS DISTINCT FROM 'MYC-RECLAIM-20261016-749964'
    THEN RAISE EXCEPTION 'FOUNDER_APPROVAL_REQUIRED'; END IF;
 IF current_database()<>'postgres' THEN RAISE EXCEPTION 'WRONG_DATABASE'; END IF;
 IF EXISTS(SELECT 1 FROM cron.job WHERE jobid=11 AND active) THEN RAISE EXCEPTION 'CRON11_ACTIVE'; END IF;
 IF (SELECT count(*) FROM config.system_settings WHERE setting_key IN
    ('business_master_apply_enabled','migration_target_apply_enabled','production_cutover_approved')
    AND setting_value='false'::jsonb)<>3 THEN RAISE EXCEPTION 'CUTOVER_GATE_CHANGED'; END IF;
 IF EXISTS(SELECT 1 FROM ops.shadow_import_rows) THEN RAISE EXCEPTION 'TARGET_NOT_EMPTY'; END IF;
 IF (SELECT count(*) FROM ops.shadow_import_sessions)<>3028 THEN RAISE EXCEPTION 'SESSIONS_CHANGED'; END IF;
 SELECT coalesce(sum(('x'||substr(md5(to_jsonb(s)::text),1,16))::bit(64)::bigint),0)
 INTO fp FROM ops.shadow_import_sessions s;
 IF fp<>62814098099219885444::numeric THEN RAISE EXCEPTION 'SESSION_METADATA_CHANGED'; END IF;
 IF NOT EXISTS(SELECT 1 FROM config.system_settings WHERE setting_key='migration_shadow_write_enabled'
    AND setting_value='false'::jsonb) THEN RAISE EXCEPTION 'SHADOW_WRITERS_NOT_FROZEN'; END IF;
END $$;
\copy ops.shadow_import_rows (row_pk,session_id,entity_key,source_sheet,source_row_number,source_pk,raw_record,normalized_record,row_hash,validation_status,validation_issues,staged_at,validated_at) FROM '/run/myc/backup-20261016T084239Z/reclaim/retained-shadow-rows.csv' WITH (FORMAT csv,HEADER true)
DO $$ DECLARE n bigint; fp numeric; BEGIN
 SELECT count(*),coalesce(sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint),0)
 INTO n,fp FROM ops.shadow_import_rows r;
 IF n<>36818 OR fp<>-2770658449854450349::numeric
    THEN RAISE EXCEPTION 'RETAINED_CONTENT_MISMATCH'; END IF;
 IF (SELECT count(*) FROM ops.shadow_import_rows WHERE validation_status<>'VALID')<>4
    THEN RAISE EXCEPTION 'INVALID_HISTORY_NOT_PRESERVED'; END IF;
END $$;
COMMIT;
-- Keep Cron11 and shadow write gate off until root-cause guard + restart gates pass.
