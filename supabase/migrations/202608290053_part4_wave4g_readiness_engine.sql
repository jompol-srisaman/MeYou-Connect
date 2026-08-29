create or replace function ops.count_rehearsal_fk_orphans(p_rehearsal_id uuid)
returns integer
language plpgsql security definer set search_path=''
as $$
declare v_final uuid; r record; v_count int:=0;
begin
  select final_session_id into v_final from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id;
  if v_final is null then return 0; end if;
  for r in
    select fr.rule_key,fr.child_entity_key,fr.child_json_key,fr.parent_entity_key,sr.source_pk as child_pk,
           nullif(btrim(sr.normalized_record->>fr.child_json_key),'') as parent_pk
    from ops.migration_fk_rules fr
    join ops.shadow_import_rows sr on sr.session_id=v_final and sr.entity_key=fr.child_entity_key and sr.validation_status='VALID'
    where fr.active=true and nullif(btrim(sr.normalized_record->>fr.child_json_key),'') is not null
  loop
    if not exists(
      select 1 from ops.rehearsal_target_rows t
      where t.rehearsal_id=p_rehearsal_id and t.entity_key=r.parent_entity_key and t.source_pk=r.parent_pk and t.is_archived=false
    ) then
      v_count:=v_count+1;
    end if;
  end loop;
  return v_count;
end;$$;

create or replace function ops.reconcile_rehearsal_target(p_rehearsal_id uuid,p_created_by text)
returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_reh ops.cutover_rehearsals; v_batch ops.delta_batches; v_run uuid; r record; t ops.rehearsal_target_rows; v_counts record; v_status text;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  select * into v_reh from ops.cutover_rehearsals where rehearsal_id=p_rehearsal_id for update;
  if not found or v_reh.final_session_id is null then raise exception 'rehearsal/final session not ready'; end if;
  select * into v_batch from ops.delta_batches where rehearsal_id=p_rehearsal_id and status='APPLIED_TO_SCRATCH' order by batch_version desc limit 1;
  if not found then raise exception 'no applied scratch delta batch found'; end if;
  insert into ops.rehearsal_reconciliation_runs(rehearsal_id,final_session_id,delta_batch_id,created_by)
  values(p_rehearsal_id,v_reh.final_session_id,v_batch.delta_batch_id,p_created_by) returning rehearsal_reconcile_id into v_run;

  for r in
    select sr.*,m.target_ready from ops.shadow_import_rows sr join ops.migration_entity_map m using(entity_key)
    where sr.session_id=v_reh.final_session_id order by sr.entity_key,sr.source_row_number
  loop
    if r.validation_status='INVALID' then
      insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type,detail,review_required)
      values(v_run,p_rehearsal_id,r.entity_key,r.source_pk,'INVALID_SOURCE',jsonb_build_object('validation_issues',r.validation_issues),true);
    elsif r.validation_status='SKIPPED' or not r.target_ready then
      insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type,detail,review_required)
      values(v_run,p_rehearsal_id,r.entity_key,r.source_pk,'UNSUPPORTED',jsonb_build_object('validation_issues',r.validation_issues),true);
    else
      select * into t from ops.rehearsal_target_rows
      where rehearsal_id=p_rehearsal_id and entity_key=r.entity_key and source_pk=r.source_pk;
      if not found then
        insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type,detail,review_required)
        values(v_run,p_rehearsal_id,r.entity_key,r.source_pk,'SOURCE_ONLY',jsonb_build_object('reason','SCRATCH_TARGET_MISSING'),true);
      elsif t.is_archived then
        insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type,detail,review_required)
        values(v_run,p_rehearsal_id,r.entity_key,r.source_pk,'FIELD_MISMATCH',jsonb_build_object('reason','SCRATCH_TARGET_ARCHIVED_BUT_SOURCE_PRESENT'),true);
      elsif t.row_hash=r.row_hash then
        insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type)
        values(v_run,p_rehearsal_id,r.entity_key,r.source_pk,'MATCH');
      else
        insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type,detail,review_required)
        values(v_run,p_rehearsal_id,r.entity_key,r.source_pk,'FIELD_MISMATCH',jsonb_build_object('source_hash',r.row_hash,'scratch_hash',t.row_hash),true);
      end if;
    end if;
  end loop;

  for t in select * from ops.rehearsal_target_rows where rehearsal_id=p_rehearsal_id loop
    if not exists(
      select 1 from ops.shadow_import_rows sr
      where sr.session_id=v_reh.final_session_id and sr.entity_key=t.entity_key and sr.source_pk=t.source_pk and sr.validation_status='VALID'
    ) then
      if t.is_archived then
        insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type,detail)
        values(v_run,p_rehearsal_id,t.entity_key,t.source_pk,'ARCHIVE_MATCH',jsonb_build_object('reason','SOURCE_REMOVED_REHEARSED_AS_ARCHIVE'));
      else
        insert into ops.rehearsal_reconciliation_results(rehearsal_reconcile_id,rehearsal_id,entity_key,source_pk,result_type,detail,review_required)
        values(v_run,p_rehearsal_id,t.entity_key,t.source_pk,'TARGET_ONLY',jsonb_build_object('reason','NON_ARCHIVED_SCRATCH_ROW_NOT_IN_FINAL_SOURCE'),true);
      end if;
    end if;
  end loop;

  select count(*) filter(where result_type='MATCH') as matches,
         count(*) filter(where result_type='ARCHIVE_MATCH') as archive_matches,
         count(*) filter(where result_type='SOURCE_ONLY') as source_only,
         count(*) filter(where result_type='TARGET_ONLY') as target_only,
         count(*) filter(where result_type='FIELD_MISMATCH') as mismatches,
         count(*) filter(where result_type='INVALID_SOURCE') as invalids,
         count(*) filter(where result_type='UNSUPPORTED') as unsupported
  into v_counts from ops.rehearsal_reconciliation_results where rehearsal_reconcile_id=v_run;
  v_status:=case when v_counts.source_only=0 and v_counts.target_only=0 and v_counts.mismatches=0 and v_counts.invalids=0 and v_counts.unsupported=0 then 'PASS' else 'REVIEW_REQUIRED' end;
  update ops.rehearsal_reconciliation_runs set status=v_status,match_count=v_counts.matches,archive_match_count=v_counts.archive_matches,
    source_only_count=v_counts.source_only,target_only_count=v_counts.target_only,mismatch_count=v_counts.mismatches,invalid_count=v_counts.invalids,unsupported_count=v_counts.unsupported,finished_at=now()
  where rehearsal_reconcile_id=v_run;
  update ops.delta_batches set status='RECONCILED',updated_at=now() where delta_batch_id=v_batch.delta_batch_id;
  update ops.cutover_rehearsals set status='RECONCILED',freeze_ended_at=coalesce(freeze_ended_at,now()),updated_at=now() where rehearsal_id=p_rehearsal_id;
  return v_run;
end;$$;

create or replace function ops.record_cutover_manual_check(
  p_rehearsal_id uuid,
  p_check_key text,
  p_status text,
  p_observed_value jsonb,
  p_evidence_ref text,
  p_evaluated_by text
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_mode text; v_critical boolean; v_id uuid;
begin
  if not config.setting_is_true('migration_rehearsal_enabled') then raise exception 'migration rehearsal gate is disabled'; end if;
  select check_mode,critical into v_mode,v_critical from ops.cutover_check_catalog where check_key=p_check_key and active=true;
  if not found then raise exception 'unknown cutover check'; end if;
  if v_mode='AUTO' then raise exception 'AUTO check cannot be manually overridden'; end if;
  if p_status not in ('PASS','FAIL','NOT_READY','NOT_APPLICABLE') then raise exception 'invalid check status'; end if;
  if v_critical and p_status='PASS' and nullif(btrim(p_evidence_ref),'') is null then raise exception 'critical manual PASS requires evidence_ref'; end if;
  insert into ops.cutover_check_results(rehearsal_id,check_key,status,observed_value,evidence_ref,evaluated_by,evaluated_at)
  values(p_rehearsal_id,p_check_key,p_status,coalesce(p_observed_value,'{}'::jsonb),p_evidence_ref,p_evaluated_by,now())
  on conflict(rehearsal_id,check_key) do update set status=excluded.status,observed_value=excluded.observed_value,evidence_ref=excluded.evidence_ref,evaluated_by=excluded.evaluated_by,evaluated_at=now()
  returning check_result_id into v_id;
  return v_id;
end;$$;

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
  select * into v_latest_recon from ops.rehearsal_reconciliation_runs where rehearsal_id=p_rehearsal_id order by started_at desc limit 1;
  select * into v_latest_batch from ops.delta_batches where rehearsal_id=p_rehearsal_id order by batch_version desc limit 1;

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
    jsonb_build_object('reconcile_id',v_latest_recon.rehearsal_reconcile_id,'status',v_latest_recon.status,'source_only',v_latest_recon.source_only_count,'target_only',v_latest_recon.target_only_count,'mismatch',v_latest_recon.mismatch_count,'invalid',v_latest_recon.invalid_count,'unsupported',v_latest_recon.unsupported_count),p_evaluated_by)
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

create or replace view ops.cutover_readiness_v as
select r.rehearsal_id,r.rehearsal_name,r.status,r.source_system,r.baseline_source_revision,r.final_source_revision,r.freeze_acknowledged,r.final_backup_recorded,
       count(c.check_key) filter(where c.critical and c.active) as critical_total,
       count(c.check_key) filter(where c.critical and c.active and cr.status='PASS') as critical_pass,
       count(c.check_key) filter(where c.critical and c.active and coalesce(cr.status,'NOT_READY')<>'PASS') as critical_not_pass,
       coalesce(jsonb_object_agg(c.check_key,coalesce(cr.status,'NOT_READY')) filter(where c.active),'{}'::jsonb) as check_statuses,
       r.updated_at
from ops.cutover_rehearsals r
cross join ops.cutover_check_catalog c
left join ops.cutover_check_results cr on cr.rehearsal_id=r.rehearsal_id and cr.check_key=c.check_key
group by r.rehearsal_id;

revoke all on function ops.count_rehearsal_fk_orphans(uuid) from public,anon,authenticated;
revoke all on function ops.reconcile_rehearsal_target(uuid,text) from public,anon,authenticated;
revoke all on function ops.record_cutover_manual_check(uuid,text,text,jsonb,text,text) from public,anon,authenticated;
revoke all on function ops.evaluate_cutover_readiness(uuid,text) from public,anon,authenticated;
grant execute on function ops.count_rehearsal_fk_orphans(uuid) to service_role;
grant execute on function ops.reconcile_rehearsal_target(uuid,text) to service_role;
grant execute on function ops.record_cutover_manual_check(uuid,text,text,jsonb,text,text) to service_role;
grant execute on function ops.evaluate_cutover_readiness(uuid,text) to service_role;
revoke all on ops.cutover_readiness_v from anon,authenticated;
grant select on ops.cutover_readiness_v to service_role;
