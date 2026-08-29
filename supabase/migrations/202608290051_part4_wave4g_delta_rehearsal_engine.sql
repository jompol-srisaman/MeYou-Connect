create or replace function ops.create_cutover_rehearsal(
  p_rehearsal_name text,
  p_baseline_session_id uuid,
  p_created_by text,
  p_notes text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_session ops.shadow_import_sessions; v_source text;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  if config.setting_is_true('migration_cutover_enabled') or config.setting_is_true('production_cutover_approved') then raise exception 'rehearsal cannot start while production cutover is enabled/approved'; end if;
  select setting_value #>> '{}' into v_source from config.system_settings where setting_key='current_operational_source';
  if v_source is distinct from 'GOOGLE_SHEETS_DRIVE' then raise exception 'current operational source must remain GOOGLE_SHEETS_DRIVE during rehearsal'; end if;
  if nullif(btrim(p_rehearsal_name),'') is null or nullif(btrim(p_created_by),'') is null then raise exception 'rehearsal_name and created_by are required'; end if;
  select * into v_session from ops.shadow_import_sessions where session_id=p_baseline_session_id;
  if not found then raise exception 'unknown baseline shadow session'; end if;
  if v_session.status not in ('VALIDATED','RECONCILED') then raise exception 'baseline session must be validated/reconciled'; end if;
  insert into ops.cutover_rehearsals(rehearsal_name,source_system,source_file_id,baseline_session_id,baseline_source_revision,notes,created_by)
  values(p_rehearsal_name,v_session.source_system,v_session.source_file_id,p_baseline_session_id,v_session.source_revision,p_notes,p_created_by)
  returning rehearsal_id into v_id;
  return v_id;
end;$$;

create or replace function ops.load_baseline_into_rehearsal_target(p_rehearsal_id uuid)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_reh ops.cutover_rehearsals; v_invalid int; v_loaded int;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  select * into v_reh from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id for update;
  if not found then raise exception 'unknown rehearsal'; end if;
  select count(*) into v_invalid from ops.shadow_import_rows r join ops.migration_entity_map m using(entity_key)
  where r.session_id=v_reh.baseline_session_id and (r.validation_status<>'VALID' or not m.target_ready);
  if v_invalid>0 then raise exception 'baseline contains invalid/unsupported rows: %',v_invalid; end if;
  delete from ops.rehearsal_target_rows where rehearsal_id=p_rehearsal_id;
  insert into ops.rehearsal_target_rows(rehearsal_id,entity_key,source_pk,normalized_record,row_hash,is_archived,applied_from)
  select p_rehearsal_id,r.entity_key,r.source_pk,r.normalized_record,r.row_hash,false,'BASELINE'
  from ops.shadow_import_rows r
  where r.session_id=v_reh.baseline_session_id and r.validation_status='VALID' and r.source_pk is not null;
  get diagnostics v_loaded=row_count;
  update ops.cutover_rehearsals set status='BASELINE_LOADED',updated_at=now() where rehearsal_id=p_rehearsal_id;
  return jsonb_build_object('rehearsal_id',p_rehearsal_id,'loaded_rows',v_loaded);
end;$$;

create or replace function ops.begin_write_freeze_rehearsal(
  p_rehearsal_id uuid,
  p_freeze_source_revision text,
  p_actor text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_reh ops.cutover_rehearsals;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') or not config.setting_is_true('migration_freeze_rehearsal_enabled') then raise exception 'write-freeze rehearsal gate is disabled'; end if;
  if config.setting_is_true('migration_cutover_enabled') or config.setting_is_true('production_cutover_approved') then raise exception 'production cutover must remain disabled during rehearsal'; end if;
  select * into v_reh from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id for update;
  if not found then raise exception 'unknown rehearsal'; end if;
  if v_reh.status not in ('BASELINE_LOADED','PLANNED') then raise exception 'rehearsal not ready for freeze checkpoint: %',v_reh.status; end if;
  update ops.cutover_rehearsals
  set freeze_requested_at=coalesce(freeze_requested_at,now()),freeze_started_at=now(),freeze_acknowledged=true,
      freeze_source_revision=p_freeze_source_revision,status='FREEZE_REHEARSAL',updated_at=now()
  where rehearsal_id=p_rehearsal_id;
  return jsonb_build_object('rehearsal_id',p_rehearsal_id,'freeze_rehearsal_acknowledged',true,'actual_source_lock_performed',false,'actor',p_actor);
end;$$;

create or replace function ops.record_final_backup_checkpoint(
  p_rehearsal_id uuid,
  p_final_backup_ref text,
  p_actor text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_ack boolean;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  select freeze_acknowledged into v_ack from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id for update;
  if not found then raise exception 'unknown rehearsal'; end if;
  if not v_ack then raise exception 'freeze rehearsal checkpoint must be acknowledged first'; end if;
  if nullif(btrim(p_final_backup_ref),'') is null then raise exception 'final backup reference is required'; end if;
  update ops.cutover_rehearsals set final_backup_ref=p_final_backup_ref,final_backup_recorded=true,updated_at=now() where rehearsal_id=p_rehearsal_id;
  return jsonb_build_object('rehearsal_id',p_rehearsal_id,'final_backup_recorded',true,'actor',p_actor);
end;$$;

create or replace function ops.attach_final_shadow_session(
  p_rehearsal_id uuid,
  p_final_session_id uuid,
  p_final_source_revision text,
  p_actor text
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_reh ops.cutover_rehearsals; v_final ops.shadow_import_sessions;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  select * into v_reh from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id for update;
  if not found then raise exception 'unknown rehearsal'; end if;
  if not v_reh.freeze_acknowledged or not v_reh.final_backup_recorded then raise exception 'freeze and final-backup checkpoints are required before final delta snapshot'; end if;
  select * into v_final from ops.shadow_import_sessions where session_id=p_final_session_id;
  if not found then raise exception 'unknown final shadow session'; end if;
  if v_final.status not in ('VALIDATED','RECONCILED') then raise exception 'final shadow session must be validated/reconciled'; end if;
  if v_final.source_system is distinct from v_reh.source_system then raise exception 'source system mismatch'; end if;
  update ops.cutover_rehearsals set final_session_id=p_final_session_id,final_source_revision=coalesce(p_final_source_revision,v_final.source_revision),updated_at=now() where rehearsal_id=p_rehearsal_id;
  return jsonb_build_object('rehearsal_id',p_rehearsal_id,'final_session_id',p_final_session_id,'actor',p_actor);
end;$$;

create or replace function ops.build_delta_batch(p_rehearsal_id uuid,p_created_by text)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_reh ops.cutover_rehearsals; v_batch uuid; v_version int; v_counts record;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') or not config.setting_is_true('migration_delta_capture_enabled') then raise exception 'delta rehearsal gate is disabled'; end if;
  select * into v_reh from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id for update;
  if not found then raise exception 'unknown rehearsal'; end if;
  if v_reh.final_session_id is null then raise exception 'final shadow session is not attached'; end if;
  select coalesce(max(batch_version),0)+1 into v_version from ops.delta_batches where rehearsal_id=p_rehearsal_id;
  insert into ops.delta_batches(rehearsal_id,batch_version,baseline_session_id,final_session_id,created_by)
  values(p_rehearsal_id,v_version,v_reh.baseline_session_id,v_reh.final_session_id,p_created_by)
  returning delta_batch_id into v_batch;

  insert into ops.delta_rows(delta_batch_id,entity_key,source_pk,change_type,baseline_hash,final_hash,baseline_record,final_record,validation_issues,review_required)
  select v_batch,f.entity_key,f.source_pk,
    case
      when f.validation_status='INVALID' then 'INVALID_SOURCE'
      when f.validation_status='SKIPPED' or not m.target_ready then 'UNSUPPORTED'
      when b.row_pk is null then 'INSERT'
      when b.row_hash is distinct from f.row_hash then 'UPDATE'
      else 'UNCHANGED'
    end,
    b.row_hash,f.row_hash,b.normalized_record,f.normalized_record,f.validation_issues,
    case when f.validation_status in ('INVALID','SKIPPED') or not m.target_ready then true else false end
  from ops.shadow_import_rows f
  join ops.migration_entity_map m using(entity_key)
  left join ops.shadow_import_rows b
    on b.session_id=v_reh.baseline_session_id and b.entity_key=f.entity_key and b.source_pk=f.source_pk and b.validation_status='VALID'
  where f.session_id=v_reh.final_session_id;

  insert into ops.delta_rows(delta_batch_id,entity_key,source_pk,change_type,baseline_hash,baseline_record,review_required)
  select v_batch,b.entity_key,b.source_pk,'SOURCE_REMOVED',b.row_hash,b.normalized_record,true
  from ops.shadow_import_rows b
  where b.session_id=v_reh.baseline_session_id and b.validation_status='VALID' and b.source_pk is not null
    and not exists(
      select 1 from ops.shadow_import_rows f
      where f.session_id=v_reh.final_session_id and f.entity_key=b.entity_key and f.source_pk=b.source_pk and f.validation_status='VALID'
    );

  select count(*) filter(where change_type='INSERT') as inserts,
         count(*) filter(where change_type='UPDATE') as updates,
         count(*) filter(where change_type='SOURCE_REMOVED') as removed,
         count(*) filter(where change_type='UNCHANGED') as unchanged,
         count(*) filter(where change_type='INVALID_SOURCE') as invalids,
         count(*) filter(where change_type='UNSUPPORTED') as unsupported
  into v_counts from ops.delta_rows where delta_batch_id=v_batch;

  update ops.delta_batches
  set insert_count=v_counts.inserts,update_count=v_counts.updates,source_removed_count=v_counts.removed,unchanged_count=v_counts.unchanged,
      invalid_count=v_counts.invalids,unsupported_count=v_counts.unsupported,
      status=case when v_counts.invalids>0 or v_counts.unsupported>0 or v_counts.removed>0 then 'REVIEW_REQUIRED' else 'PLANNED' end,
      updated_at=now()
  where delta_batch_id=v_batch;
  update ops.cutover_rehearsals set status='DELTA_READY',updated_at=now() where rehearsal_id=p_rehearsal_id;
  return v_batch;
end;$$;

create or replace function ops.apply_delta_batch_to_rehearsal_target(p_delta_batch_id uuid,p_actor text)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_batch ops.delta_batches; r record; v_applied int:=0; v_archived int:=0;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  if config.setting_is_true('migration_target_apply_enabled') or config.setting_is_true('migration_cutover_enabled') or config.setting_is_true('production_cutover_approved') then
    raise exception 'scratch apply requires all real target/cutover gates to remain disabled';
  end if;
  select * into v_batch from ops.delta_batches where delta_batch_id=p_delta_batch_id for update;
  if not found then raise exception 'unknown delta batch'; end if;
  for r in select * from ops.delta_rows where delta_batch_id=p_delta_batch_id order by entity_key,source_pk nulls last loop
    if r.change_type in ('INSERT','UPDATE','UNCHANGED') and r.source_pk is not null then
      insert into ops.rehearsal_target_rows(rehearsal_id,entity_key,source_pk,normalized_record,row_hash,is_archived,applied_from,applied_at)
      values(v_batch.rehearsal_id,r.entity_key,r.source_pk,coalesce(r.final_record,'{}'::jsonb),coalesce(r.final_hash,md5(coalesce(r.final_record,'{}'::jsonb)::text)),false,'DELTA',now())
      on conflict(rehearsal_id,entity_key,source_pk) do update set normalized_record=excluded.normalized_record,row_hash=excluded.row_hash,is_archived=false,applied_from='DELTA',applied_at=now();
      v_applied:=v_applied+1;
    elsif r.change_type='SOURCE_REMOVED' and r.source_pk is not null then
      update ops.rehearsal_target_rows set is_archived=true,applied_from='DELTA',applied_at=now()
      where rehearsal_id=v_batch.rehearsal_id and entity_key=r.entity_key and source_pk=r.source_pk;
      v_archived:=v_archived+1;
    end if;
  end loop;
  update ops.delta_batches set status='APPLIED_TO_SCRATCH',updated_at=now() where delta_batch_id=p_delta_batch_id;
  update ops.cutover_rehearsals set status='DELTA_APPLIED_TO_SCRATCH',updated_at=now() where rehearsal_id=v_batch.rehearsal_id;
  return jsonb_build_object('delta_batch_id',p_delta_batch_id,'scratch_rows_applied',v_applied,'scratch_rows_archived',v_archived,'real_master_rows_written',0,'actor',p_actor);
end;$$;

revoke all on function ops.create_cutover_rehearsal(text,uuid,text,text) from public,anon,authenticated;
revoke all on function ops.load_baseline_into_rehearsal_target(uuid) from public,anon,authenticated;
revoke all on function ops.begin_write_freeze_rehearsal(uuid,text,text) from public,anon,authenticated;
revoke all on function ops.record_final_backup_checkpoint(uuid,text,text) from public,anon,authenticated;
revoke all on function ops.attach_final_shadow_session(uuid,uuid,text,text) from public,anon,authenticated;
revoke all on function ops.build_delta_batch(uuid,text) from public,anon,authenticated;
revoke all on function ops.apply_delta_batch_to_rehearsal_target(uuid,text) from public,anon,authenticated;
grant execute on function ops.create_cutover_rehearsal(text,uuid,text,text) to service_role;
grant execute on function ops.load_baseline_into_rehearsal_target(uuid) to service_role;
grant execute on function ops.begin_write_freeze_rehearsal(uuid,text,text) to service_role;
grant execute on function ops.record_final_backup_checkpoint(uuid,text,text) to service_role;
grant execute on function ops.attach_final_shadow_session(uuid,uuid,text,text) to service_role;
grant execute on function ops.build_delta_batch(uuid,text) to service_role;
grant execute on function ops.apply_delta_batch_to_rehearsal_target(uuid,text) to service_role;
