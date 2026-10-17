-- REVIEW DRAFT ONLY. NOT APPLIED. No deletion or cron reactivation.
-- Historical V3 rehearsal only; superseded by deployed V4 migration
-- 20261017020029_myc_shadow_import_v4_delta_guards.sql. Do not apply V3 live.
-- Preserves existing signatures/owners/ACLs/search_path and safety gates.
-- Must be exercised on a verified restored copy before production execution.
-- Approved retained baseline is61,038,592bytes (~58.2MiB). 75MiB gives ~16.8MiB
-- staging headroom; overall database hard stop stays400MiB (Free quota500MB).
BEGIN;
CREATE OR REPLACE FUNCTION ops.open_shadow_import_session(p_source_system text, p_source_file_id text, p_source_file_name text, p_source_revision text, p_snapshot_at timestamp with time zone, p_source_of_truth boolean, p_expected_entities text[], p_metadata jsonb, p_created_by text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_id uuid;
begin
  if not config.setting_is_true('migration_shadow_write_enabled') then raise exception 'migration shadow write gate is disabled'; end if;
  if p_source_system is null or btrim(p_source_system)='' then raise exception 'source_system required'; end if;
  if p_created_by is null or btrim(p_created_by)='' then raise exception 'created_by required'; end if;

  -- All Google Sheets writers must use the content-hash protocol.
  if p_source_system = 'GOOGLE_SHEETS' then
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('MYC_SHADOW_IMPORT_V3', 0));
    if p_source_revision is null or p_source_revision !~ '^sha256:[0-9a-f]{64}$'
       or coalesce(p_metadata->>'guard_required', '') <> 'v3' then
      raise exception 'SHADOW_HASH_PROTOCOL_REQUIRED';
    end if;
    select session_id into v_id from ops.shadow_import_sessions
      where source_system=p_source_system and source_file_id=p_source_file_id
        and source_revision=p_source_revision order by created_at desc limit 1;
    if found then
      if exists(select 1 from ops.shadow_import_sessions where session_id=v_id and status in ('VALIDATED','RECONCILED')) then
        raise exception 'SHADOW_SNAPSHOT_ALREADY_EXISTS';
      end if;
      raise exception 'SHADOW_INCOMPLETE_SNAPSHOT_REQUIRES_REVIEW';
    end if;
    if coalesce((p_metadata->>'input_rows')::integer, -1) not between 0 and 1000
       or coalesce((p_metadata->>'input_bytes')::bigint, -1) not between 0 and 2097152 then
      raise exception 'SHADOW_INPUT_BUDGET_EXCEEDED';
    end if;
    if pg_catalog.pg_database_size(pg_catalog.current_database()) >= 419430400
       or pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass) >= 78643200 then
      raise exception 'SHADOW_CAPACITY_STOP';
    end if;
    if (select count(*) from ops.shadow_import_sessions where source_system='GOOGLE_SHEETS' and source_revision like 'sha256:%') >= 20 then
      raise exception 'SHADOW_RETENTION_ARCHIVE_REQUIRED';
    end if;
    p_metadata := coalesce(p_metadata,'{}'::jsonb) || jsonb_build_object(
      'guard_applied','v3','database_bytes',pg_catalog.pg_database_size(pg_catalog.current_database()));
  end if;

  insert into ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,source_of_truth,expected_entities,metadata,created_by)
  values(p_source_system,p_source_file_id,p_source_file_name,p_source_revision,coalesce(p_snapshot_at,now()),coalesce(p_source_of_truth,false),coalesce(p_expected_entities,'{}'),coalesce(p_metadata,'{}'),p_created_by)
  returning session_id into v_id;
  return v_id;
end;$function$;

CREATE OR REPLACE FUNCTION ops.stage_shadow_row(p_session_id uuid, p_entity_key text, p_source_row_number integer, p_source_pk text, p_raw_record jsonb, p_normalized_record jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_map ops.migration_entity_map; v_id uuid; v_status text;
begin
  if not config.setting_is_true('migration_shadow_write_enabled') then raise exception 'migration shadow write gate is disabled'; end if;
  select status into v_status from ops.shadow_import_sessions where session_id=p_session_id for update;
  if not found then raise exception 'unknown shadow session'; end if;
  if v_status not in ('OPEN','STAGED','VALIDATED','RECONCILED') then raise exception 'shadow session is not stageable: %',v_status; end if;
  select * into v_map from ops.migration_entity_map where entity_key=p_entity_key;
  if not found then raise exception 'unknown migration entity: %',p_entity_key; end if;
  if p_source_row_number < 2 then raise exception 'source row number must be >= 2'; end if;

  if exists(select 1 from ops.shadow_import_sessions s where s.session_id=p_session_id and s.source_system='GOOGLE_SHEETS') then
    -- Serialize capacity checks across sessions, not only rows in one session.
    perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('MYC_SHADOW_IMPORT_V3', 0));
    if not exists(select 1 from ops.shadow_import_sessions s where s.session_id=p_session_id and s.metadata->>'guard_applied'='v3') then
      raise exception 'SHADOW_HASH_PROTOCOL_REQUIRED';
    end if;
    if pg_catalog.pg_database_size(pg_catalog.current_database()) >= 419430400
       or pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass) >= 78643200 then
      raise exception 'SHADOW_CAPACITY_STOP';
    end if;
    if pg_catalog.octet_length(coalesce(p_raw_record,'{}')::text)>32768
       or pg_catalog.octet_length(coalesce(p_normalized_record,'{}')::text)>32768 then
      raise exception 'SHADOW_ROW_BUDGET_EXCEEDED';
    end if;
    if (select count(*) from ops.shadow_import_rows where session_id=p_session_id) >= 1000
       and not exists(select 1 from ops.shadow_import_rows where session_id=p_session_id and source_sheet=v_map.source_sheet and source_row_number=p_source_row_number) then
      raise exception 'SHADOW_ROW_COUNT_BUDGET_EXCEEDED';
    end if;
  end if;

  insert into ops.shadow_import_rows(session_id,entity_key,source_sheet,source_row_number,source_pk,raw_record,normalized_record,row_hash,validation_status,validation_issues,validated_at)
  values(p_session_id,p_entity_key,v_map.source_sheet,p_source_row_number,nullif(btrim(p_source_pk),''),coalesce(p_raw_record,'{}'),coalesce(p_normalized_record,'{}'),md5(coalesce(p_raw_record,'{}')::text),'STAGED','[]',null)
  on conflict(session_id,source_sheet,source_row_number) do update set
    source_pk=excluded.source_pk,raw_record=excluded.raw_record,normalized_record=excluded.normalized_record,row_hash=excluded.row_hash,validation_status='STAGED',validation_issues='[]',validated_at=null,staged_at=now()
  returning row_pk into v_id;
  update ops.shadow_import_sessions set status='STAGED',updated_at=now() where session_id=p_session_id;
  return v_id;
end;$function$;

COMMIT;

