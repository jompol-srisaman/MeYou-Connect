-- Founder-authorized permanent controls: Issue28 approval6217872819 / PR29.
-- PostgreSQL17.6 restored-data delta, concurrency, ACL and physical caps PASS.
-- Preserves existing shadow rows/sessions. Cron11 and cutover gates stay off.
CREATE OR REPLACE FUNCTION ops.open_shadow_import_session(
  p_source_system text,
  p_source_file_id text,
  p_source_file_name text,
  p_source_revision text,
  p_snapshot_at timestamptz,
  p_source_of_truth boolean,
  p_expected_entities text[],
  p_metadata jsonb,
  p_created_by text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_id uuid;
  v_existing ops.shadow_import_sessions%ROWTYPE;
  v_baseline uuid;
  v_requested_baseline uuid;
  v_input_rows integer;
  v_source_rows integer;
  v_input_bytes bigint;
  v_snapshot_at timestamptz;
  v_latest_snapshot_at timestamptz;
BEGIN
  IF NOT config.setting_is_true('migration_shadow_write_enabled') THEN
    RAISE EXCEPTION 'migration shadow write gate is disabled';
  END IF;
  IF p_source_system IS NULL THEN RAISE EXCEPTION 'source_system required'; END IF;
  IF p_source_system IS NULL OR pg_catalog.btrim(p_source_system) = '' THEN
    RAISE EXCEPTION 'source_system required';
  END IF;
  IF p_created_by IS NULL OR pg_catalog.btrim(p_created_by) = '' THEN
    RAISE EXCEPTION 'created_by required';
  END IF;
  -- Physical hard stops apply to every source system before the legacy
  -- non-Google compatibility branch can return early.
  IF pg_catalog.pg_database_size(pg_catalog.current_database()) >= 419430400
     OR pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass) >= 78643200 THEN
    RAISE EXCEPTION 'SHADOW_CAPACITY_STOP';
  END IF;

  IF p_source_system <> 'GOOGLE_SHEETS' THEN
    INSERT INTO ops.shadow_import_sessions(
      source_system,source_file_id,source_file_name,source_revision,snapshot_at,
      source_of_truth,expected_entities,metadata,created_by
    ) VALUES (
      p_source_system,p_source_file_id,p_source_file_name,p_source_revision,
      COALESCE(p_snapshot_at,pg_catalog.now()),COALESCE(p_source_of_truth,false),
      COALESCE(p_expected_entities,'{}'::text[]),COALESCE(p_metadata,'{}'::jsonb),p_created_by
    ) RETURNING session_id INTO v_id;
    RETURN v_id;
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('MYC_SHADOW_IMPORT_V3',0));

  IF p_source_file_id IS NULL OR pg_catalog.btrim(p_source_file_id) = '' OR pg_catalog.octet_length(p_source_file_id) > 512
     OR p_source_revision IS NULL OR p_source_revision !~ '^sha256:[0-9a-f]{64}$'
     OR p_metadata IS NULL OR pg_catalog.jsonb_typeof(p_metadata) IS DISTINCT FROM 'object'
     OR p_metadata->>'function' IS DISTINCT FROM 'datahub-shadow-import-v4'
     OR p_metadata->>'mode' IS DISTINCT FROM 'read_only_sheets_to_shadow'
     OR p_metadata->>'guard_required' IS DISTINCT FROM 'v4'
     OR p_metadata->>'import_protocol' IS DISTINCT FROM 'delta-v1'
     OR p_metadata->>'source_revision' IS DISTINCT FROM p_source_revision
     OR p_metadata->'allowlisted_fields_only' IS DISTINCT FROM 'true'::jsonb
     OR NOT (p_metadata ? 'baseline_session_id')
     OR p_metadata ? 'guard_applied' OR p_metadata ? 'database_bytes'
     OR p_source_of_truth IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'SHADOW_HASH_PROTOCOL_REQUIRED';
  END IF;

  IF p_expected_entities IS NULL OR pg_catalog.cardinality(p_expected_entities) < 1
     OR pg_catalog.cardinality(p_expected_entities) > 10
     OR pg_catalog.array_position(p_expected_entities,NULL) IS NOT NULL
     OR pg_catalog.cardinality(p_expected_entities) <> (
       SELECT pg_catalog.count(DISTINCT e.entity_key)
       FROM pg_catalog.unnest(p_expected_entities) AS e(entity_key)
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.unnest(p_expected_entities) AS e(entity_key)
       LEFT JOIN ops.migration_entity_map m ON m.entity_key=e.entity_key
       WHERE m.entity_key IS NULL
     ) THEN
    RAISE EXCEPTION 'SHADOW_ENTITY_SCOPE_INVALID';
  END IF;

  BEGIN
    v_input_rows := (p_metadata->>'input_rows')::integer;
    v_source_rows := (p_metadata->>'source_rows')::integer;
    v_input_bytes := (p_metadata->>'input_bytes')::bigint;
  EXCEPTION WHEN OTHERS THEN
    RAISE EXCEPTION 'SHADOW_INPUT_BUDGET_EXCEEDED';
  END;
  IF v_input_rows IS NULL OR v_source_rows IS NULL OR v_input_bytes IS NULL
     OR v_input_rows NOT BETWEEN 1 AND 1000 OR v_source_rows NOT BETWEEN v_input_rows AND 1000
     OR v_input_bytes NOT BETWEEN 1 AND 2097152 THEN
    RAISE EXCEPTION 'SHADOW_INPUT_BUDGET_EXCEEDED';
  END IF;
  IF p_metadata->>'baseline_session_id' IS NOT NULL THEN
    BEGIN
      v_requested_baseline := (p_metadata->>'baseline_session_id')::uuid;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'SHADOW_BASELINE_INVALID';
    END;
  END IF;

  SELECT s.* INTO v_existing
  FROM ops.shadow_import_sessions s
  WHERE s.source_system=p_source_system
    AND s.source_file_id=p_source_file_id
    AND s.source_revision=p_source_revision
  ORDER BY s.created_at DESC,s.session_id DESC
  LIMIT 1
  FOR UPDATE;
  IF FOUND THEN
    IF v_existing.status IN ('OPEN','STAGED') THEN
      RAISE EXCEPTION 'SHADOW_IMPORT_IN_PROGRESS';
    END IF;
    IF v_existing.status IN ('VALIDATED','RECONCILED')
       AND NOT EXISTS (
         SELECT 1 FROM ops.shadow_import_rows r
         WHERE r.session_id=v_existing.session_id
           AND (r.validation_status <> 'VALID' OR r.source_pk IS NULL)
       ) THEN
      IF v_existing.source_of_truth IS TRUE
         AND v_existing.expected_entities IS NOT DISTINCT FROM p_expected_entities
         AND (v_existing.metadata - 'guard_applied' - 'database_bytes') IS NOT DISTINCT FROM p_metadata
         AND v_existing.source_file_name IS NOT DISTINCT FROM p_source_file_name THEN
        RETURN v_existing.session_id;
      END IF;
      RAISE EXCEPTION 'SHADOW_SNAPSHOT_ALREADY_EXISTS';
    END IF;
    RAISE EXCEPTION 'SHADOW_INCOMPLETE_SNAPSHOT_REQUIRES_REVIEW';
  END IF;

  IF EXISTS (
    SELECT 1 FROM ops.shadow_import_sessions s
    WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
      AND s.status IN ('OPEN','STAGED') AND s.source_revision LIKE 'sha256:%'
  ) THEN
    RAISE EXCEPTION 'SHADOW_IMPORT_IN_PROGRESS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM ops.shadow_import_sessions s
    WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
      AND s.metadata->>'import_protocol'='delta-v1'
      AND s.status IN ('VALIDATED','RECONCILED')
      AND EXISTS (
        SELECT 1 FROM ops.shadow_import_rows r
        WHERE r.session_id=s.session_id AND (r.validation_status <> 'VALID' OR r.source_pk IS NULL)
      )
  ) THEN
    RAISE EXCEPTION 'SHADOW_INCOMPLETE_SNAPSHOT_REQUIRES_REVIEW';
  END IF;

  SELECT s.session_id INTO v_baseline
  FROM ops.shadow_import_sessions s
  WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
    AND s.source_of_truth IS TRUE
    AND s.status IN ('VALIDATED','RECONCILED')
  ORDER BY s.created_at DESC,s.session_id DESC
  LIMIT 1;
  IF v_baseline IS DISTINCT FROM v_requested_baseline THEN
    RAISE EXCEPTION 'SHADOW_STALE_BASELINE';
  END IF;

  v_snapshot_at := COALESCE(p_snapshot_at,pg_catalog.now());
  IF v_snapshot_at > pg_catalog.now() + interval '5 minutes' THEN
    RAISE EXCEPTION 'SHADOW_SNAPSHOT_TIME_INVALID';
  END IF;
  SELECT pg_catalog.max(s.snapshot_at) INTO v_latest_snapshot_at
  FROM ops.shadow_import_sessions s
  WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
    AND s.source_of_truth IS TRUE AND s.status IN ('VALIDATED','RECONCILED');
  IF v_latest_snapshot_at IS NOT NULL AND v_snapshot_at < v_latest_snapshot_at THEN
    RAISE EXCEPTION 'SHADOW_SNAPSHOT_OUT_OF_ORDER';
  END IF;

  IF pg_catalog.pg_database_size(pg_catalog.current_database()) >= 419430400
     OR pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass) >= 78643200 THEN
    RAISE EXCEPTION 'SHADOW_CAPACITY_STOP';
  END IF;
  IF (
    SELECT pg_catalog.count(*) FROM ops.shadow_import_sessions s
    WHERE s.source_system='GOOGLE_SHEETS' AND s.source_revision LIKE 'sha256:%'
  ) >= 20 THEN
    RAISE EXCEPTION 'SHADOW_RETENTION_ARCHIVE_REQUIRED';
  END IF;

  INSERT INTO ops.shadow_import_sessions(
    source_system,source_file_id,source_file_name,source_revision,snapshot_at,
    source_of_truth,expected_entities,metadata,created_by
  ) VALUES (
    p_source_system,p_source_file_id,p_source_file_name,p_source_revision,
    v_snapshot_at,true,p_expected_entities,
    p_metadata || pg_catalog.jsonb_build_object(
      'guard_applied','v4','database_bytes',pg_catalog.pg_database_size(pg_catalog.current_database())
    ),p_created_by
  ) RETURNING session_id INTO v_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION ops.stage_shadow_row(
  p_session_id uuid,
  p_entity_key text,
  p_source_row_number integer,
  p_source_pk text,
  p_raw_record jsonb,
  p_normalized_record jsonb
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_session ops.shadow_import_sessions%ROWTYPE;
  v_map ops.migration_entity_map%ROWTYPE;
  v_existing ops.shadow_import_rows%ROWTYPE;
  v_id uuid;
  v_count integer;
  v_bytes bigint;
  v_cap_rows integer;
  v_expected_baseline uuid;
  v_latest_baseline uuid;
  v_raw jsonb := COALESCE(p_raw_record,'{}'::jsonb);
  v_normalized jsonb := COALESCE(p_normalized_record,'{}'::jsonb);
BEGIN
  IF NOT config.setting_is_true('migration_shadow_write_enabled') THEN
    RAISE EXCEPTION 'migration shadow write gate is disabled';
  END IF;
  -- Apply the same physical hard stops before looking at source_system, so
  -- alternate shadow sources cannot bypass capacity protection.
  IF pg_catalog.pg_database_size(pg_catalog.current_database()) >= 419430400
     OR pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass) >= 78643200 THEN
    RAISE EXCEPTION 'SHADOW_CAPACITY_STOP';
  END IF;
  -- Take the same lock before row locks as open/get-baseline. This avoids an
  -- open-versus-stage deadlock and prevents a baseline changing mid-stage.
  IF EXISTS (SELECT 1 FROM ops.shadow_import_sessions s WHERE s.session_id=p_session_id AND s.source_system='GOOGLE_SHEETS') THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('MYC_SHADOW_IMPORT_V3',0));
  END IF;
  SELECT s.* INTO v_session FROM ops.shadow_import_sessions s
  WHERE s.session_id=p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown shadow session'; END IF;
  IF v_session.status IN ('VALIDATED','RECONCILED') THEN
    RAISE EXCEPTION 'SHADOW_ACCEPTED_SESSION_SEALED';
  END IF;
  IF v_session.status NOT IN ('OPEN','STAGED') THEN
    RAISE EXCEPTION 'shadow session is not stageable: %',v_session.status;
  END IF;
  SELECT m.* INTO v_map FROM ops.migration_entity_map m WHERE m.entity_key=p_entity_key;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown migration entity: %',p_entity_key; END IF;
  IF p_source_row_number IS NULL OR p_source_row_number < 2 THEN
    RAISE EXCEPTION 'source row number must be >= 2';
  END IF;

  IF v_session.source_system='GOOGLE_SHEETS' THEN
    IF v_session.metadata->>'guard_required' IS DISTINCT FROM 'v4'
       OR v_session.metadata->>'import_protocol' IS DISTINCT FROM 'delta-v1'
       OR v_session.metadata->>'function' IS DISTINCT FROM 'datahub-shadow-import-v4'
       OR v_session.metadata->>'mode' IS DISTINCT FROM 'read_only_sheets_to_shadow'
       OR v_session.metadata->'allowlisted_fields_only' IS DISTINCT FROM 'true'::jsonb
       OR NOT (v_session.expected_entities @> ARRAY[p_entity_key]::text[])
       OR p_source_pk IS NULL OR pg_catalog.btrim(p_source_pk)=''
       OR pg_catalog.jsonb_typeof(v_raw) <> 'object'
       OR pg_catalog.jsonb_typeof(v_normalized) <> 'object' THEN
      RAISE EXCEPTION 'SHADOW_HASH_PROTOCOL_REQUIRED';
    END IF;

    IF EXISTS (
      SELECT 1 FROM ops.shadow_import_sessions s
      WHERE s.source_system=v_session.source_system
        AND s.source_file_id=v_session.source_file_id
        AND s.session_id<>p_session_id AND s.status IN ('OPEN','STAGED')
        AND s.source_revision LIKE 'sha256:%'
    ) THEN
      RAISE EXCEPTION 'SHADOW_IMPORT_IN_PROGRESS';
    END IF;
    IF EXISTS (
      SELECT 1 FROM ops.shadow_import_sessions s
      WHERE s.source_system=v_session.source_system
        AND s.source_file_id=v_session.source_file_id
        AND s.metadata->>'import_protocol'='delta-v1'
        AND s.status IN ('VALIDATED','RECONCILED')
        AND EXISTS (
          SELECT 1 FROM ops.shadow_import_rows r
          WHERE r.session_id=s.session_id AND (r.validation_status <> 'VALID' OR r.source_pk IS NULL)
        )
    ) THEN
      RAISE EXCEPTION 'SHADOW_INCOMPLETE_SNAPSHOT_REQUIRES_REVIEW';
    END IF;
    SELECT s.session_id INTO v_latest_baseline
    FROM ops.shadow_import_sessions s
    WHERE s.source_system=v_session.source_system AND s.source_file_id=v_session.source_file_id
      AND s.source_of_truth IS TRUE
      AND s.status IN ('VALIDATED','RECONCILED')
    ORDER BY s.created_at DESC,s.session_id DESC LIMIT 1;
    IF v_session.metadata->>'baseline_session_id' IS NOT NULL THEN
      BEGIN
        v_expected_baseline := (v_session.metadata->>'baseline_session_id')::uuid;
      EXCEPTION WHEN OTHERS THEN
        RAISE EXCEPTION 'SHADOW_BASELINE_INVALID';
      END;
    END IF;
    IF v_expected_baseline IS DISTINCT FROM v_latest_baseline THEN
      RAISE EXCEPTION 'SHADOW_STALE_BASELINE';
    END IF;

    SELECT r.* INTO v_existing FROM ops.shadow_import_rows r
    WHERE r.session_id=p_session_id AND r.source_sheet=v_map.source_sheet
      AND r.source_row_number=p_source_row_number FOR UPDATE;
    IF FOUND THEN
      IF v_existing.source_pk IS NOT DISTINCT FROM p_source_pk
         AND v_existing.raw_record IS NOT DISTINCT FROM v_raw
         AND v_existing.normalized_record IS NOT DISTINCT FROM v_normalized THEN
        RETURN v_existing.row_pk;
      END IF;
      RAISE EXCEPTION 'SHADOW_ROW_REPLAY_MISMATCH';
    END IF;

    IF pg_catalog.octet_length(v_raw::text)>32768
       OR pg_catalog.octet_length(v_normalized::text)>32768 THEN
      RAISE EXCEPTION 'SHADOW_ROW_BUDGET_EXCEEDED';
    END IF;
    IF pg_catalog.pg_database_size(pg_catalog.current_database())>=419430400
       OR pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass)>=78643200 THEN
      RAISE EXCEPTION 'SHADOW_CAPACITY_STOP';
    END IF;
    BEGIN
      v_cap_rows := (v_session.metadata->>'input_rows')::integer;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'SHADOW_INPUT_BUDGET_EXCEEDED';
    END;
    IF v_cap_rows IS NULL OR v_cap_rows NOT BETWEEN 1 AND 1000
       OR v_session.metadata->>'source_revision' IS DISTINCT FROM v_session.source_revision THEN
      RAISE EXCEPTION 'SHADOW_INPUT_BUDGET_EXCEEDED';
    END IF;
    SELECT pg_catalog.count(*),COALESCE(pg_catalog.sum(GREATEST(
      pg_catalog.octet_length(r.raw_record::text),pg_catalog.octet_length(r.normalized_record::text)
    )),0)
      INTO v_count,v_bytes FROM ops.shadow_import_rows r WHERE r.session_id=p_session_id;
    IF v_count>=v_cap_rows OR v_count>=1000 THEN
      RAISE EXCEPTION 'SHADOW_ROW_COUNT_BUDGET_EXCEEDED';
    END IF;
    IF v_bytes+GREATEST(pg_catalog.octet_length(v_raw::text),pg_catalog.octet_length(v_normalized::text))>2097152 THEN
      RAISE EXCEPTION 'SHADOW_INPUT_BUDGET_EXCEEDED';
    END IF;
  END IF;

  INSERT INTO ops.shadow_import_rows(
    session_id,entity_key,source_sheet,source_row_number,source_pk,
    raw_record,normalized_record,row_hash,validation_status,validation_issues,validated_at
  ) VALUES (
    p_session_id,p_entity_key,v_map.source_sheet,p_source_row_number,nullif(pg_catalog.btrim(p_source_pk),''),
    v_raw,v_normalized,pg_catalog.md5(v_raw::text),'STAGED','[]'::jsonb,NULL
  )
  ON CONFLICT(session_id,source_sheet,source_row_number) DO UPDATE SET
    source_pk=EXCLUDED.source_pk,raw_record=EXCLUDED.raw_record,normalized_record=EXCLUDED.normalized_record,
    row_hash=EXCLUDED.row_hash,validation_status='STAGED',validation_issues='[]'::jsonb,
    validated_at=NULL,staged_at=pg_catalog.now()
  RETURNING row_pk INTO v_id;
  UPDATE ops.shadow_import_sessions SET status='STAGED',updated_at=pg_catalog.now()
  WHERE session_id=p_session_id;
  RETURN v_id;
END;
$function$;

CREATE OR REPLACE FUNCTION ops.validate_shadow_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  r record;
  v_issues jsonb;
  v_status text;
  v_invalid integer:=0;
  v_valid integer:=0;
  v_skipped integer:=0;
  v_pk_count integer;
  v_session ops.shadow_import_sessions%ROWTYPE;
  v_expected integer;
  v_actual integer;
BEGIN
  IF NOT config.setting_is_true('migration_shadow_write_enabled') THEN
    RAISE EXCEPTION 'migration shadow write gate is disabled';
  END IF;
  IF EXISTS (SELECT 1 FROM ops.shadow_import_sessions s WHERE s.session_id=p_session_id AND s.source_system='GOOGLE_SHEETS') THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('MYC_SHADOW_IMPORT_V3',0));
  END IF;
  SELECT s.* INTO v_session FROM ops.shadow_import_sessions s
  WHERE s.session_id=p_session_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'unknown shadow session'; END IF;
  v_status:=v_session.status;
  IF v_status IN ('VALIDATED','RECONCILED') THEN
    SELECT pg_catalog.count(*) FILTER(WHERE validation_status='VALID'),
           pg_catalog.count(*) FILTER(WHERE validation_status='INVALID'),
           pg_catalog.count(*) FILTER(WHERE validation_status='SKIPPED')
      INTO v_valid,v_invalid,v_skipped
    FROM ops.shadow_import_rows WHERE session_id=p_session_id;
    RETURN pg_catalog.jsonb_build_object('session_id',p_session_id,'valid',v_valid,'invalid',v_invalid,'skipped',v_skipped,'sealed',true);
  END IF;
  IF v_status NOT IN ('OPEN','STAGED') THEN
    RAISE EXCEPTION 'shadow session is not stageable: %',v_status;
  END IF;
  IF v_session.source_system='GOOGLE_SHEETS' THEN
    IF v_session.metadata->>'guard_required' IS DISTINCT FROM 'v4'
       OR v_session.metadata->>'import_protocol' IS DISTINCT FROM 'delta-v1' THEN
      RAISE EXCEPTION 'SHADOW_HASH_PROTOCOL_REQUIRED';
    END IF;
    BEGIN
      v_expected := (v_session.metadata->>'input_rows')::integer;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'SHADOW_INPUT_BUDGET_EXCEEDED';
    END;
    IF v_expected IS NULL OR v_expected NOT BETWEEN 1 AND 1000
       OR v_session.metadata->>'source_revision' IS DISTINCT FROM v_session.source_revision THEN
      RAISE EXCEPTION 'SHADOW_INPUT_BUDGET_EXCEEDED';
    END IF;
    SELECT pg_catalog.count(*) INTO v_actual FROM ops.shadow_import_rows WHERE session_id=p_session_id;
    IF v_actual IS DISTINCT FROM v_expected THEN
      RAISE EXCEPTION 'SHADOW_INCOMPLETE_DELTA_SESSION';
    END IF;
  END IF;

  FOR r IN
    SELECT sr.*,m.id_regex,m.target_ready,m.target_pk_column
    FROM ops.shadow_import_rows sr JOIN ops.migration_entity_map m USING(entity_key)
    WHERE sr.session_id=p_session_id
    ORDER BY sr.source_sheet,sr.source_row_number
  LOOP
    v_issues:='[]'::jsonb;
    IF r.source_pk IS NULL OR pg_catalog.btrim(r.source_pk)='' THEN
      v_issues:=v_issues||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','MISSING_SOURCE_PK','severity','HIGH'));
    END IF;
    IF r.source_pk IS NOT NULL AND r.id_regex IS NOT NULL AND r.source_pk !~ r.id_regex THEN
      v_issues:=v_issues||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','ID_PATTERN_MISMATCH','severity','HIGH','expected_regex',r.id_regex,'actual',r.source_pk));
    END IF;
    IF r.source_pk IS NOT NULL AND r.normalized_record ? r.target_pk_column
       AND NULLIF(r.normalized_record->>r.target_pk_column,'') IS DISTINCT FROM r.source_pk THEN
      v_issues:=v_issues||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','NORMALIZED_PK_MISMATCH','severity','HIGH','normalized_pk',r.normalized_record->>r.target_pk_column));
    END IF;
    IF r.source_pk IS NOT NULL THEN
      SELECT pg_catalog.count(*) INTO v_pk_count FROM ops.shadow_import_rows x
      WHERE x.session_id=p_session_id AND x.entity_key=r.entity_key AND x.source_pk=r.source_pk;
      IF v_pk_count>1 THEN
        v_issues:=v_issues||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','DUPLICATE_SOURCE_PK','severity','HIGH','count',v_pk_count));
      END IF;
    END IF;
    IF NOT r.target_ready THEN
      UPDATE ops.shadow_import_rows SET validation_status='SKIPPED',
        validation_issues=v_issues||pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('code','TARGET_NOT_READY','severity','MEDIUM')),
        validated_at=pg_catalog.now() WHERE row_pk=r.row_pk;
      v_skipped:=v_skipped+1;
    ELSIF pg_catalog.jsonb_array_length(v_issues)>0 THEN
      UPDATE ops.shadow_import_rows SET validation_status='INVALID',validation_issues=v_issues,
        validated_at=pg_catalog.now() WHERE row_pk=r.row_pk;
      v_invalid:=v_invalid+1;
    ELSE
      UPDATE ops.shadow_import_rows SET validation_status='VALID',validation_issues='[]'::jsonb,
        validated_at=pg_catalog.now() WHERE row_pk=r.row_pk;
      v_valid:=v_valid+1;
    END IF;
  END LOOP;
  UPDATE ops.shadow_import_sessions SET status='VALIDATED',updated_at=pg_catalog.now()
  WHERE session_id=p_session_id;
  RETURN pg_catalog.jsonb_build_object('session_id',p_session_id,'valid',v_valid,'invalid',v_invalid,'skipped',v_skipped);
END;
$function$;

CREATE OR REPLACE FUNCTION ops.get_shadow_import_baseline(
  p_source_system text,
  p_source_file_id text,
  p_entities text[]
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_baseline uuid;
  v_rows jsonb;
  v_count integer;
BEGIN
  IF p_source_system IS DISTINCT FROM 'GOOGLE_SHEETS'
     OR p_source_file_id IS NULL OR pg_catalog.btrim(p_source_file_id)=''
     OR pg_catalog.octet_length(p_source_file_id)>512
     OR p_entities IS NULL OR pg_catalog.cardinality(p_entities)<1
     OR pg_catalog.cardinality(p_entities)>10
     OR pg_catalog.array_position(p_entities,NULL) IS NOT NULL
     OR pg_catalog.cardinality(p_entities)<>(
       SELECT pg_catalog.count(DISTINCT e.entity_key)
       FROM pg_catalog.unnest(p_entities) AS e(entity_key)
     )
     OR EXISTS (
       SELECT 1 FROM pg_catalog.unnest(p_entities) AS e(entity_key)
       LEFT JOIN ops.migration_entity_map m ON m.entity_key=e.entity_key
       WHERE m.entity_key IS NULL
     ) THEN
    RAISE EXCEPTION 'SHADOW_BASELINE_INVALID';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('MYC_SHADOW_IMPORT_V3',0));
  IF EXISTS (
    SELECT 1 FROM ops.shadow_import_sessions s
    WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
      AND s.status IN ('OPEN','STAGED') AND s.source_revision LIKE 'sha256:%'
  ) THEN
    RAISE EXCEPTION 'SHADOW_IMPORT_IN_PROGRESS';
  END IF;
  IF EXISTS (
    SELECT 1 FROM ops.shadow_import_sessions s
    WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
      AND s.metadata->>'import_protocol'='delta-v1'
      AND s.status IN ('VALIDATED','RECONCILED')
      AND EXISTS (
        SELECT 1 FROM ops.shadow_import_rows r
        WHERE r.session_id=s.session_id AND (r.validation_status <> 'VALID' OR r.source_pk IS NULL)
      )
  ) THEN
    RAISE EXCEPTION 'SHADOW_INCOMPLETE_SNAPSHOT_REQUIRES_REVIEW';
  END IF;

  SELECT s.session_id INTO v_baseline
  FROM ops.shadow_import_sessions s
  WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
    AND s.source_of_truth IS TRUE
    AND s.status IN ('VALIDATED','RECONCILED')
  ORDER BY s.created_at DESC,s.session_id DESC
  LIMIT 1;

  WITH accepted AS MATERIALIZED (
    SELECT s.session_id,s.created_at
    FROM ops.shadow_import_sessions s
    WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
      AND s.source_of_truth IS TRUE
      AND s.status IN ('VALIDATED','RECONCILED')
  ), latest AS MATERIALIZED (
    SELECT DISTINCT ON (r.entity_key,r.source_pk)
      r.entity_key,r.source_pk,r.source_row_number,r.normalized_record,
      a.created_at,r.session_id,r.staged_at
    FROM accepted a JOIN ops.shadow_import_rows r ON r.session_id=a.session_id
    WHERE r.entity_key=ANY(p_entities) AND r.validation_status='VALID' AND r.source_pk IS NOT NULL
    ORDER BY r.entity_key,r.source_pk,a.created_at DESC,r.session_id DESC,r.source_row_number DESC,r.staged_at DESC
  )
  SELECT pg_catalog.count(*) INTO v_count FROM latest;
  IF v_count>1000 THEN RAISE EXCEPTION 'SHADOW_BASELINE_INVALID'; END IF;

  WITH accepted AS MATERIALIZED (
    SELECT s.session_id,s.created_at
    FROM ops.shadow_import_sessions s
    WHERE s.source_system=p_source_system AND s.source_file_id=p_source_file_id
      AND s.source_of_truth IS TRUE
      AND s.status IN ('VALIDATED','RECONCILED')
  ), latest AS MATERIALIZED (
    SELECT DISTINCT ON (r.entity_key,r.source_pk)
      r.entity_key,r.source_pk,r.source_row_number,r.normalized_record,
      a.created_at,r.session_id,r.staged_at
    FROM accepted a JOIN ops.shadow_import_rows r ON r.session_id=a.session_id
    WHERE r.entity_key=ANY(p_entities) AND r.validation_status='VALID' AND r.source_pk IS NOT NULL
    ORDER BY r.entity_key,r.source_pk,a.created_at DESC,r.session_id DESC,r.source_row_number DESC,r.staged_at DESC
  )
  SELECT COALESCE(
    pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
      'entity_key',entity_key,'source_pk',source_pk,
      'source_row_number',source_row_number,'normalized_record',normalized_record
    ) ORDER BY entity_key,source_pk),'[]'::jsonb
  ) INTO v_rows FROM latest;
  IF pg_catalog.octet_length(v_rows::text)>2097152 THEN
    RAISE EXCEPTION 'SHADOW_BASELINE_INVALID';
  END IF;
  IF EXISTS (
    SELECT 1 FROM pg_catalog.jsonb_array_elements(v_rows) AS e(value)
    WHERE pg_catalog.jsonb_typeof(e.value->'normalized_record')<>'object'
  ) THEN
    RAISE EXCEPTION 'SHADOW_BASELINE_INVALID';
  END IF;
  RETURN pg_catalog.jsonb_build_object(
    'baseline_session_id',v_baseline,
    'rows',v_rows,
    'entity_scope',pg_catalog.to_jsonb(ARRAY(SELECT u.entity_key FROM pg_catalog.unnest(p_entities) AS u(entity_key) ORDER BY u.entity_key))
  );
END;
$function$;

ALTER FUNCTION ops.get_shadow_import_baseline(text,text,text[]) OWNER TO postgres;

REVOKE ALL ON FUNCTION ops.get_shadow_import_baseline(text,text,text[]) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ops.get_shadow_import_baseline(text,text,text[]) TO service_role;
REVOKE ALL ON FUNCTION ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text) TO service_role;
REVOKE ALL ON FUNCTION ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb) TO service_role;
REVOKE ALL ON FUNCTION ops.validate_shadow_session(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION ops.validate_shadow_session(uuid) TO service_role;
