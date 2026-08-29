-- Part 4F shadow row change-detection fix
create or replace function ops.stage_shadow_row(
  p_session_id uuid,
  p_entity_key text,
  p_source_row_number integer,
  p_source_pk text,
  p_raw_record jsonb,
  p_normalized_record jsonb
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_map ops.migration_entity_map; v_id uuid; v_status text;
begin
  if not config.setting_is_true('migration_shadow_write_enabled') then raise exception 'migration shadow write gate is disabled'; end if;
  select status into v_status from ops.shadow_import_sessions where session_id=p_session_id for update;
  if not found then raise exception 'unknown shadow session'; end if;
  if v_status not in ('OPEN','STAGED','VALIDATED','RECONCILED') then raise exception 'shadow session is not stageable: %',v_status; end if;
  select * into v_map from ops.migration_entity_map where entity_key=p_entity_key;
  if not found then raise exception 'unknown migration entity: %',p_entity_key; end if;
  if p_source_row_number < 2 then raise exception 'source row number must be >= 2'; end if;
  insert into ops.shadow_import_rows(session_id,entity_key,source_sheet,source_row_number,source_pk,raw_record,normalized_record,row_hash,validation_status,validation_issues,validated_at)
  values(p_session_id,p_entity_key,v_map.source_sheet,p_source_row_number,nullif(btrim(p_source_pk),''),coalesce(p_raw_record,'{}'),coalesce(p_normalized_record,'{}'),md5(coalesce(p_raw_record,'{}')::text),'STAGED','[]',null)
  on conflict(session_id,source_sheet,source_row_number) do update set source_pk=excluded.source_pk,raw_record=excluded.raw_record,normalized_record=excluded.normalized_record,row_hash=excluded.row_hash,validation_status='STAGED',validation_issues='[]',validated_at=null,staged_at=now()
  returning row_pk into v_id;
  update ops.shadow_import_sessions set status='STAGED',updated_at=now() where session_id=p_session_id;
  return v_id;
end;$$;