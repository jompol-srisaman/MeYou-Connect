begin;

create or replace function ops.open_shadow_import_session(
  p_source_system text,
  p_source_file_id text,
  p_source_file_name text,
  p_source_revision text,
  p_snapshot_at timestamptz,
  p_source_of_truth boolean,
  p_expected_entities text[],
  p_metadata jsonb,
  p_created_by text
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_id uuid;
begin
  if not config.setting_is_true('migration_shadow_write_enabled') then raise exception 'migration shadow write gate is disabled'; end if;
  if p_source_system is null or btrim(p_source_system)='' then raise exception 'source_system required'; end if;
  if p_created_by is null or btrim(p_created_by)='' then raise exception 'created_by required'; end if;
  insert into ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,source_of_truth,expected_entities,metadata,created_by)
  values(p_source_system,p_source_file_id,p_source_file_name,p_source_revision,coalesce(p_snapshot_at,now()),coalesce(p_source_of_truth,false),coalesce(p_expected_entities,'{}'),coalesce(p_metadata,'{}'),p_created_by)
  returning session_id into v_id;
  return v_id;
end;$$;

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
  values(p_session_id,p_entity_key,v_map.source_sheet,p_source_row_number,nullif(btrim(p_source_pk),''),coalesce(p_raw_record,'{}'),coalesce(p_normalized_record,'{}'),encode(digest(convert_to(coalesce(p_raw_record,'{}')::text,'UTF8'),'sha256'),'hex'),'STAGED','[]',null)
  on conflict(session_id,source_sheet,source_row_number) do update set
    source_pk=excluded.source_pk,raw_record=excluded.raw_record,normalized_record=excluded.normalized_record,row_hash=excluded.row_hash,validation_status='STAGED',validation_issues='[]',validated_at=null,staged_at=now()
  returning row_pk into v_id;
  update ops.shadow_import_sessions set status='STAGED',updated_at=now() where session_id=p_session_id;
  return v_id;
end;$$;

create or replace function ops.validate_shadow_session(p_session_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare r record; v_issues jsonb; v_status text; v_invalid int:=0; v_valid int:=0; v_skipped int:=0; v_pk_count int;
begin
  if not config.setting_is_true('migration_shadow_write_enabled') then raise exception 'migration shadow write gate is disabled'; end if;
  select status into v_status from ops.shadow_import_sessions where session_id=p_session_id for update;
  if not found then raise exception 'unknown shadow session'; end if;
  for r in
    select sr.*, m.id_regex, m.target_ready, m.target_pk_column, m.compare_fields
    from ops.shadow_import_rows sr join ops.migration_entity_map m using(entity_key)
    where sr.session_id=p_session_id order by sr.source_sheet,sr.source_row_number
  loop
    v_issues:='[]'::jsonb;
    if r.source_pk is null then
      v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','MISSING_SOURCE_PK','severity','HIGH'));
    end if;
    if r.source_pk is not null and r.id_regex is not null and r.source_pk !~ r.id_regex then
      v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','ID_PATTERN_MISMATCH','severity','HIGH','expected_regex',r.id_regex,'actual',r.source_pk));
    end if;
    if r.source_pk is not null and r.normalized_record ? r.target_pk_column and nullif(r.normalized_record->>r.target_pk_column,'') is distinct from r.source_pk then
      v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','NORMALIZED_PK_MISMATCH','severity','HIGH','normalized_pk',r.normalized_record->>r.target_pk_column));
    end if;
    if r.source_pk is not null then
      select count(*) into v_pk_count from ops.shadow_import_rows x where x.session_id=p_session_id and x.entity_key=r.entity_key and x.source_pk=r.source_pk;
      if v_pk_count > 1 then
        v_issues:=v_issues||jsonb_build_array(jsonb_build_object('code','DUPLICATE_SOURCE_PK','severity','HIGH','count',v_pk_count));
      end if;
    end if;
    if not r.target_ready then
      update ops.shadow_import_rows set validation_status='SKIPPED',validation_issues=v_issues||jsonb_build_array(jsonb_build_object('code','TARGET_NOT_READY','severity','MEDIUM')),validated_at=now() where row_pk=r.row_pk;
      v_skipped:=v_skipped+1;
    elsif jsonb_array_length(v_issues)>0 then
      update ops.shadow_import_rows set validation_status='INVALID',validation_issues=v_issues,validated_at=now() where row_pk=r.row_pk;
      v_invalid:=v_invalid+1;
    else
      update ops.shadow_import_rows set validation_status='VALID',validation_issues='[]',validated_at=now() where row_pk=r.row_pk;
      v_valid:=v_valid+1;
    end if;
  end loop;
  update ops.shadow_import_sessions set status='VALIDATED',updated_at=now() where session_id=p_session_id;
  return jsonb_build_object('session_id',p_session_id,'valid',v_valid,'invalid',v_invalid,'skipped',v_skipped);
end;$$;

create or replace function ops.shadow_target_record(p_entity_key text,p_target_pk text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_map ops.migration_entity_map; v_record jsonb;
begin
  select * into v_map from ops.migration_entity_map where entity_key=p_entity_key and target_ready=true;
  if not found then return null; end if;
  execute format('select to_jsonb(t) from %I.%I t where %I::text=$1',v_map.target_schema,v_map.target_table,v_map.target_pk_column)
    into v_record using p_target_pk;
  return v_record;
end;$$;

create or replace function ops.shadow_field_diffs(p_source jsonb,p_target jsonb,p_fields text[])
returns jsonb
language plpgsql
immutable
set search_path=''
as $$
declare f text; v jsonb:='{}'::jsonb;
begin
  if p_target is null then return '{}'::jsonb; end if;
  foreach f in array coalesce(p_fields,'{}') loop
    if p_source ? f and (p_source->f) is distinct from (p_target->f) then
      v:=v||jsonb_build_object(f,jsonb_build_object('source',p_source->f,'target',p_target->f));
    end if;
  end loop;
  return v;
end;$$;

create or replace function ops.reconcile_shadow_session(p_session_id uuid,p_created_by text)
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare r record; m record; v_run uuid; v_target jsonb; v_diffs jsonb; v_status text; v_counts record; v_target_pk text;
begin
  if not config.setting_is_true('migration_shadow_write_enabled') then raise exception 'migration shadow write gate is disabled'; end if;
  if p_created_by is null or btrim(p_created_by)='' then raise exception 'created_by required'; end if;
  perform ops.validate_shadow_session(p_session_id);
  insert into ops.reconciliation_runs(session_id,created_by) values(p_session_id,p_created_by) returning run_id into v_run;

  for r in
    select sr.*,m.target_ready,m.compare_fields
    from ops.shadow_import_rows sr join ops.migration_entity_map m using(entity_key)
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

  for m in
    select em.* from ops.migration_entity_map em
    where em.target_ready=true and cardinality(em.compare_fields)>0
      and (select expected_entities from ops.shadow_import_sessions where session_id=p_session_id) @> array[em.entity_key]
  loop
    for v_target_pk in execute format('select %I::text from %I.%I',m.target_pk_column,m.target_schema,m.target_table)
    loop
      if not exists(select 1 from ops.shadow_import_rows sr where sr.session_id=p_session_id and sr.entity_key=m.entity_key and sr.source_pk=v_target_pk and sr.validation_status='VALID') then
        insert into ops.reconciliation_results(run_id,session_id,entity_key,target_pk,result_type,severity,issue_code,review_required)
        values(v_run,p_session_id,m.entity_key,v_target_pk,'TARGET_ONLY','HIGH','SOURCE_ROW_MISSING',true);
      end if;
    end loop;
  end loop;

  select
    count(*) as total,
    count(*) filter(where result_type='MATCH') as matches,
    count(*) filter(where result_type='SOURCE_ONLY') as source_only,
    count(*) filter(where result_type='TARGET_ONLY') as target_only,
    count(*) filter(where result_type='FIELD_MISMATCH') as mismatches,
    count(*) filter(where result_type='INVALID_SOURCE') as invalids,
    count(*) filter(where result_type='UNSUPPORTED') as unsupported
  into v_counts from ops.reconciliation_results where run_id=v_run;

  v_status:=case when v_counts.invalids>0 or v_counts.target_only>0 or v_counts.mismatches>0 or v_counts.unsupported>0 then 'REVIEW_REQUIRED' when v_counts.source_only>0 then 'REVIEW_REQUIRED' else 'PASS' end;
  update ops.reconciliation_runs set status=v_status,source_row_count=(select count(*) from ops.shadow_import_rows where session_id=p_session_id),valid_row_count=(select count(*) from ops.shadow_import_rows where session_id=p_session_id and validation_status='VALID'),invalid_row_count=(select count(*) from ops.shadow_import_rows where session_id=p_session_id and validation_status='INVALID'),match_count=v_counts.matches,source_only_count=v_counts.source_only,target_only_count=v_counts.target_only,mismatch_count=v_counts.mismatches,unsupported_count=v_counts.unsupported,finished_at=now() where run_id=v_run;
  update ops.shadow_import_sessions set status='RECONCILED',updated_at=now() where session_id=p_session_id;
  return v_run;
end;$$;

create or replace view ops.reconciliation_summary_v as
select s.session_id,s.source_system,s.source_file_id,s.source_file_name,s.snapshot_at,s.status as session_status,r.run_id,r.status as run_status,r.source_row_count,r.valid_row_count,r.invalid_row_count,r.match_count,r.source_only_count,r.target_only_count,r.mismatch_count,r.unsupported_count,r.started_at,r.finished_at
from ops.shadow_import_sessions s left join lateral (select rr.* from ops.reconciliation_runs rr where rr.session_id=s.session_id order by rr.started_at desc limit 1) r on true;

insert into authz.role_capabilities(role_key,capability_key) values
('founder','migration_reconcile_read'),('secretary','migration_reconcile_read'),('data_audit','migration_reconcile_read')
on conflict do nothing;

create or replace function api.migration_reconciliation_summary(p_session_id uuid default null)
returns table(session_id uuid,source_system text,source_file_name text,snapshot_at timestamptz,session_status text,run_id uuid,run_status text,source_row_count int,valid_row_count int,invalid_row_count int,match_count int,source_only_count int,target_only_count int,mismatch_count int,unsupported_count int)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('migration_reconcile_read');
  return query select v.session_id,v.source_system,v.source_file_name,v.snapshot_at,v.session_status,v.run_id,v.run_status,v.source_row_count,v.valid_row_count,v.invalid_row_count,v.match_count,v.source_only_count,v.target_only_count,v.mismatch_count,v.unsupported_count from ops.reconciliation_summary_v v where p_session_id is null or v.session_id=p_session_id order by v.snapshot_at desc;
end;$$;

create or replace function api.migration_reconciliation_issues(p_session_id uuid)
returns table(entity_key text,source_pk text,target_pk text,result_type text,severity text,issue_code text,field_diffs jsonb,review_required boolean)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('migration_reconcile_read');
  return query select rr.entity_key,rr.source_pk,rr.target_pk,rr.result_type,rr.severity,rr.issue_code,rr.field_diffs,rr.review_required from ops.reconciliation_results rr where rr.session_id=p_session_id and rr.result_type<>'MATCH' order by rr.severity desc,rr.entity_key,coalesce(rr.source_pk,rr.target_pk);
end;$$;

revoke execute on function ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text) from public,anon,authenticated;
revoke execute on function ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb) from public,anon,authenticated;
revoke execute on function ops.validate_shadow_session(uuid) from public,anon,authenticated;
revoke execute on function ops.shadow_target_record(text,text) from public,anon,authenticated;
revoke execute on function ops.reconcile_shadow_session(uuid,text) from public,anon,authenticated;
grant execute on function ops.open_shadow_import_session(text,text,text,text,timestamptz,boolean,text[],jsonb,text) to service_role;
grant execute on function ops.stage_shadow_row(uuid,text,integer,text,jsonb,jsonb) to service_role;
grant execute on function ops.validate_shadow_session(uuid) to service_role;
grant execute on function ops.shadow_target_record(text,text) to service_role;
grant execute on function ops.reconcile_shadow_session(uuid,text) to service_role;
revoke execute on function api.migration_reconciliation_summary(uuid) from public,anon;
revoke execute on function api.migration_reconciliation_issues(uuid) from public,anon;
grant execute on function api.migration_reconciliation_summary(uuid) to authenticated;
grant execute on function api.migration_reconciliation_issues(uuid) to authenticated;
revoke all on ops.reconciliation_summary_v from anon,authenticated;
grant select on ops.reconciliation_summary_v to service_role;

commit;