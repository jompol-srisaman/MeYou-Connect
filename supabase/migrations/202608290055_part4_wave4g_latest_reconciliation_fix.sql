create or replace function ops.evaluate_cutover_readiness(p_rehearsal_id uuid,p_evaluated_by text)
returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_reh ops.cutover_rehearsals; v_source text; v_latest_recon record; v_latest_batch record; v_bad_validation int; v_dup int; v_fk int; v_unbalanced int; v_total int; v_pass int; v_status text; v_existing text;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  select * into v_reh from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id for update;
  if not found then raise exception 'unknown rehearsal'; end if;
  select setting_value #>> '{}' into v_source from config.system_settings where setting_key='current_operational_source';
  select b.* into v_latest_batch from ops.delta_batches b where b.rehearsal_id=p_rehearsal_id order by b.batch_version desc limit 1;
  if v_latest_batch.delta_batch_id is not null then
    select rr.* into v_latest_recon from ops.rehearsal_reconciliation_runs rr
    where rr.rehearsal_id=p_rehearsal_id and rr.delta_batch_id=v_latest_batch.delta_batch_id
    order by rr.rehearsal_reconcile_id desc limit 1;
  end if;

  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'one_writable_master_guard',
    case when v_source='GOOGLE_SHEETS_DRIVE' and not config.setting_is_true('migration_target_apply_enabled') and not config.setting_is_true('migration_cutover_enabled') and not config.setting_is_true('production_cutover_approved') then 'PASS' else 'FAIL' end,
    jsonb_build_object('current_operational_source',v_source,'migration_target_apply_enabled',config.setting_is_true('migration_target_apply_enabled'),'migration_cutover_enabled',config.setting_is_true('migration_cutover_enabled'),'production_cutover_approved',config.setting_is_true('production_cutover_approved')),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'write_freeze_rehearsed',case when v_reh.freeze_acknowledged and v_reh.freeze_started_at is not null and v_reh.freeze_ended_at is not null then 'PASS' else 'NOT_READY' end,
    jsonb_build_object('freeze_acknowledged',v_reh.freeze_acknowledged,'started_at',v_reh.freeze_started_at,'ended_at',v_reh.freeze_ended_at,'actual_source_lock_performed',false),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'final_backup_recorded',case when v_reh.final_backup_recorded and nullif(btrim(v_reh.final_backup_ref),'') is not null then 'PASS' else 'NOT_READY' end,
    jsonb_build_object('recorded',v_reh.final_backup_recorded,'backup_ref',v_reh.final_backup_ref),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'delta_rehearsal_reconciled',case when v_latest_recon.status='PASS' then 'PASS' else 'NOT_READY' end,
    jsonb_build_object('reconcile_id',v_latest_recon.rehearsal_reconcile_id,'delta_batch_id',v_latest_batch.delta_batch_id,'batch_version',v_latest_batch.batch_version,'status',v_latest_recon.status,'source_only',v_latest_recon.source_only_count,'target_only',v_latest_recon.target_only_count,'mismatch',v_latest_recon.mismatch_count,'invalid',v_latest_recon.invalid_count,'unsupported',v_latest_recon.unsupported_count),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  select count(*) into v_bad_validation from ops.shadow_import_rows where session_id=v_reh.final_session_id and validation_status<>'VALID';
  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'source_validation_clean',case when v_reh.final_session_id is not null and v_bad_validation=0 then 'PASS' else 'NOT_READY' end,jsonb_build_object('non_valid_rows',v_bad_validation),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  select count(*) into v_dup from ops.shadow_import_rows where session_id=v_reh.final_session_id and validation_issues @> '[{"code":"DUPLICATE_SOURCE_PK"}]'::jsonb;
  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'duplicate_ids_zero',case when v_reh.final_session_id is not null and v_dup=0 then 'PASS' else 'FAIL' end,jsonb_build_object('duplicate_rows',v_dup),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  v_fk:=ops.count_rehearsal_fk_orphans(p_rehearsal_id);
  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'fk_orphan_zero',case when v_fk=0 then 'PASS' else 'FAIL' end,jsonb_build_object('fk_orphan_count',v_fk),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  if coalesce(v_latest_batch.source_removed_count,0)=0 then
    insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
    values(p_rehearsal_id,'source_removals_reviewed','PASS',jsonb_build_object('source_removed_count',0),p_evaluated_by)
    on conflict(rehearsal_id,check_key) do update set status='PASS',observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();
  else
    select status into v_existing from ops.cutover_check_results where rehearsal_id=p_rehearsal_id and check_key='source_removals_reviewed';
    if v_existing is distinct from 'PASS' then
      insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
      values(p_rehearsal_id,'source_removals_reviewed','NOT_READY',jsonb_build_object('source_removed_count',v_latest_batch.source_removed_count,'action','REVIEW_ARCHIVE_CANDIDATES'),p_evaluated_by)
      on conflict(rehearsal_id,check_key) do update set status='NOT_READY',observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();
    end if;
  end if;

  select count(*) into v_unbalanced from (
    select b.journal_batch_id
    from finance.journal_batches b left join finance.journal_lines l on l.journal_batch_id=b.journal_batch_id
    where b.status='POSTED'
    group by b.journal_batch_id
    having coalesce(sum(l.debit),0)<>coalesce(sum(l.credit),0)
  ) q;
  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  values(p_rehearsal_id,'journal_batches_balanced',case when v_unbalanced=0 then 'PASS' else 'FAIL' end,jsonb_build_object('unbalanced_posted_batches',v_unbalanced),p_evaluated_by)
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evaluated_by=excluded.evaluated_by,evaluated_at=now();

  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evaluated_by)
  select p_rehearsal_id,c.check_key,'NOT_READY',jsonb_build_object('reason','MANUAL_EVIDENCE_REQUIRED'),p_evaluated_by
  from ops.cutover_check_catalog c
  where c.active=true and c.check_mode='MANUAL'
    and not exists(select 1 from ops.cutover_check_results x where x.rehearsal_id=p_rehearsal_id and x.check_key=c.check_key);

  select count(*) into v_total from ops.cutover_check_catalog where active=true and critical=true;
  select count(*) into v_pass from ops.cutover_check_catalog c join ops.cutover_check_results r on r.check_key=c.check_key and r.rehearsal_id=p_rehearsal_id
  where c.active=true and c.critical=true and r.status='PASS';
  v_status:=case when v_total=v_pass then 'READY_TEST' else 'NOT_READY' end;
  update ops.cutover_rehearsals set status=v_status,updated_at=now() where rehearsal_id=p_rehearsal_id;
  return jsonb_build_object('rehearsal_id',p_rehearsal_id,'readiness',v_status,'critical_total',v_total,'critical_pass',v_pass,'production_cutover_approved',config.setting_is_true('production_cutover_approved'),'migration_cutover_enabled',config.setting_is_true('migration_cutover_enabled'),'current_operational_source',v_source);
end;$$;

revoke all on function ops.evaluate_cutover_readiness(uuid,text) from public,anon,authenticated;
grant execute on function ops.evaluate_cutover_readiness(uuid,text) to service_role;
