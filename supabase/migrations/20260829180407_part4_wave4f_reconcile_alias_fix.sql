create or replace function ops.reconcile_shadow_session(p_session_id uuid,p_created_by text)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare r record; map_rec record; v_run uuid; v_target jsonb; v_diffs jsonb; v_status text; v_counts record; v_target_pk text;
begin
  if not config.setting_is_true('migration_shadow_write_enabled') then raise exception 'migration shadow write gate is disabled'; end if;
  if p_created_by is null or btrim(p_created_by)='' then raise exception 'created_by required'; end if;
  perform ops.validate_shadow_session(p_session_id);
  insert into ops.reconciliation_runs(session_id,created_by) values(p_session_id,p_created_by) returning run_id into v_run;

  for r in
    select sr.*,em.target_ready,em.compare_fields
    from ops.shadow_import_rows sr join ops.migration_entity_map em using(entity_key)
    where sr.session_id=p_session_id order by sr.source_sheet,sr.source_row_number
  loop
    if r.validation_status='INVALID' then
      insert into ops.reconciliation_results(run_id,session_id,entity_key,source_pk,result_type,severity,field_diffs,issue_code,review_required)
      values(v_run,p_session_id,r.entity_key,r.source_pk,'INVALID_SOURCE','HIGH',jsonb_build_object('validation_issues',r.validation_issues),'SOURCE_VALIDATION_FAILED',true);
    elsif r.validation_status='SKIPPED' or not r.target_ready or cardinality(r.compare_fields)=0 then
      insert into ops.reconciliation_results(run_id,session_id,entity_key,source_pk,result_type,severity,field_diffs,issue_code,review_required)
      values(v_run,p_session_id,r.entity_key,r.source_pk,'UNSUPPORTED','MEDIUM',jsonb_build_object('validation_issues',r.validation_issues),'COMPARE_MAPPING_NOT_READY',true);
    else
      v_target:=ops.shadow_target_record(r.entity_key,r.source_pk);
      if v_target is null then
        insert into ops.reconciliation_results(run_id,session_id,entity_key,source_pk,result_type,severity,issue_code,review_required)
        values(v_run,p_session_id,r.entity_key,r.source_pk,'SOURCE_ONLY','INFO','TARGET_ROW_MISSING',false);
      else
        v_diffs:=ops.shadow_field_diffs(r.normalized_record,v_target,r.compare_fields);
        if v_diffs='{}'::jsonb then
          insert into ops.reconciliation_results(run_id,session_id,entity_key,source_pk,target_pk,result_type,severity,review_required)
          values(v_run,p_session_id,r.entity_key,r.source_pk,r.source_pk,'MATCH','INFO',false);
        else
          insert into ops.reconciliation_results(run_id,session_id,entity_key,source_pk,target_pk,result_type,severity,field_diffs,issue_code,review_required)
          values(v_run,p_session_id,r.entity_key,r.source_pk,r.source_pk,'FIELD_MISMATCH','HIGH',v_diffs,'SOURCE_TARGET_FIELD_MISMATCH',true);
        end if;
      end if;
    end if;
  end loop;

  for map_rec in
    select em.* from ops.migration_entity_map em
    where em.target_ready=true and cardinality(em.compare_fields)>0
      and (select expected_entities from ops.shadow_import_sessions where session_id=p_session_id) @> array[em.entity_key]
  loop
    for v_target_pk in execute format('select %I::text from %I.%I',map_rec.target_pk_column,map_rec.target_schema,map_rec.target_table)
    loop
      if not exists(select 1 from ops.shadow_import_rows sr where sr.session_id=p_session_id and sr.entity_key=map_rec.entity_key and sr.source_pk=v_target_pk and sr.validation_status='VALID') then
        insert into ops.reconciliation_results(run_id,session_id,entity_key,target_pk,result_type,severity,issue_code,review_required)
        values(v_run,p_session_id,map_rec.entity_key,v_target_pk,'TARGET_ONLY','HIGH','SOURCE_ROW_MISSING',true);
      end if;
    end loop;
  end loop;

  select count(*) as total,
    count(*) filter(where result_type='MATCH') as matches,
    count(*) filter(where result_type='SOURCE_ONLY') as source_only,
    count(*) filter(where result_type='TARGET_ONLY') as target_only,
    count(*) filter(where result_type='FIELD_MISMATCH') as mismatches,
    count(*) filter(where result_type='INVALID_SOURCE') as invalids,
    count(*) filter(where result_type='UNSUPPORTED') as unsupported
  into v_counts from ops.reconciliation_results where run_id=v_run;

  v_status:=case when v_counts.invalids>0 or v_counts.target_only>0 or v_counts.mismatches>0 or v_counts.unsupported>0 or v_counts.source_only>0 then 'REVIEW_REQUIRED' else 'PASS' end;
  update ops.reconciliation_runs set status=v_status,
    source_row_count=(select count(*) from ops.shadow_import_rows where session_id=p_session_id),
    valid_row_count=(select count(*) from ops.shadow_import_rows where session_id=p_session_id and validation_status='VALID'),
    invalid_row_count=(select count(*) from ops.shadow_import_rows where session_id=p_session_id and validation_status='INVALID'),
    match_count=v_counts.matches,source_only_count=v_counts.source_only,target_only_count=v_counts.target_only,mismatch_count=v_counts.mismatches,unsupported_count=v_counts.unsupported,finished_at=now()
  where run_id=v_run;
  update ops.shadow_import_sessions set status='RECONCILED',updated_at=now() where session_id=p_session_id;
  return v_run;
end;$$;

revoke execute on function ops.reconcile_shadow_session(uuid,text) from public,anon,authenticated;
grant execute on function ops.reconcile_shadow_session(uuid,text) to service_role;