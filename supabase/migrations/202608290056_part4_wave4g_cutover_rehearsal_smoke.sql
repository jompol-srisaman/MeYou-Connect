do $$
declare
  v_base uuid; v_final uuid; v_reh uuid; v_batch1 uuid; v_batch2 uuid; v_rec1 uuid; v_rec2 uuid;
  v_readiness jsonb; v_cnt int; v_status text;
begin
  update config.system_settings set setting_value='true'::jsonb,updated_at=now()
  where setting_key in ('migration_shadow_write_enabled','migration_rehearsal_enabled','migration_freeze_rehearsal_enabled','migration_delta_capture_enabled');
  update config.system_settings set setting_value='false'::jsonb,updated_at=now()
  where setting_key in ('migration_target_apply_enabled','migration_cutover_enabled','production_cutover_approved','business_master_apply_enabled');

  insert into ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
  values('GOOGLE_SHEETS_DRIVE','SMOKE-DATAHUB','SMOKE_DATA_HUB','BASE-1',now(),'OPEN',true,array['Client'],'{"smoke":true,"phase":"baseline"}'::jsonb,'PART4G_SMOKE')
  returning session_id into v_base;

  perform ops.stage_shadow_row(v_base,'Client',2,'WC-B2B-9001','{"client_id":"WC-B2B-9001","company_name":"Alpha","crm_status":"LEAD"}'::jsonb,'{"client_id":"WC-B2B-9001","company_name":"Alpha","crm_status":"LEAD"}'::jsonb);
  perform ops.stage_shadow_row(v_base,'Client',3,'WC-B2B-9002','{"client_id":"WC-B2B-9002","company_name":"Beta","crm_status":"LEAD"}'::jsonb,'{"client_id":"WC-B2B-9002","company_name":"Beta","crm_status":"LEAD"}'::jsonb);
  perform ops.stage_shadow_row(v_base,'Client',4,'WC-B2B-9003','{"client_id":"WC-B2B-9003","company_name":"Gamma","crm_status":"ACTIVE"}'::jsonb,'{"client_id":"WC-B2B-9003","company_name":"Gamma","crm_status":"ACTIVE"}'::jsonb);
  perform ops.validate_shadow_session(v_base);

  v_reh:=ops.create_cutover_rehearsal('PART4G_SMOKE_REHEARSAL',v_base,'PART4G_SMOKE','Synthetic cutover rehearsal only');
  perform ops.load_baseline_into_rehearsal_target(v_reh);
  perform ops.begin_write_freeze_rehearsal(v_reh,'FREEZE-REV-1','PART4G_SMOKE');
  perform ops.record_final_backup_checkpoint(v_reh,'SMOKE-FINAL-BACKUP-REF','PART4G_SMOKE');

  insert into ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
  values('GOOGLE_SHEETS_DRIVE','SMOKE-DATAHUB','SMOKE_DATA_HUB','FINAL-1',now(),'OPEN',true,array['Client'],'{"smoke":true,"phase":"final"}'::jsonb,'PART4G_SMOKE')
  returning session_id into v_final;

  perform ops.stage_shadow_row(v_final,'Client',2,'WC-B2B-9001','{"client_id":"WC-B2B-9001","company_name":"Alpha","crm_status":"LEAD"}'::jsonb,'{"client_id":"WC-B2B-9001","company_name":"Alpha","crm_status":"LEAD"}'::jsonb);
  perform ops.stage_shadow_row(v_final,'Client',3,'WC-B2B-9002','{"client_id":"WC-B2B-9002","company_name":"Beta Updated","crm_status":"ACTIVE"}'::jsonb,'{"client_id":"WC-B2B-9002","company_name":"Beta Updated","crm_status":"ACTIVE"}'::jsonb);
  perform ops.stage_shadow_row(v_final,'Client',4,'WC-B2B-9004','{"client_id":"WC-B2B-9004","company_name":"Delta","crm_status":"LEAD"}'::jsonb,'{"client_id":"WC-B2B-9004","company_name":"Delta","crm_status":"LEAD"}'::jsonb);
  perform ops.stage_shadow_row(v_final,'Client',5,'MYC-B2B-9005','{"client_id":"MYC-B2B-9005","company_name":"Invalid Prefix","crm_status":"LEAD"}'::jsonb,'{"client_id":"MYC-B2B-9005","company_name":"Invalid Prefix","crm_status":"LEAD"}'::jsonb);
  perform ops.validate_shadow_session(v_final);
  perform ops.attach_final_shadow_session(v_reh,v_final,'FINAL-1','PART4G_SMOKE');

  v_batch1:=ops.build_delta_batch(v_reh,'PART4G_SMOKE');
  select status into v_status from ops.delta_batches where delta_batch_id=v_batch1;
  if v_status<>'REVIEW_REQUIRED' then raise exception 'expected first delta batch REVIEW_REQUIRED, got %',v_status; end if;
  perform ops.apply_delta_batch_to_rehearsal_target(v_batch1,'PART4G_SMOKE');
  v_rec1:=ops.reconcile_rehearsal_target(v_reh,'PART4G_SMOKE');
  select status into v_status from ops.rehearsal_reconciliation_runs where rehearsal_reconcile_id=v_rec1;
  if v_status<>'REVIEW_REQUIRED' then raise exception 'expected first scratch reconciliation REVIEW_REQUIRED, got %',v_status; end if;
  v_readiness:=ops.evaluate_cutover_readiness(v_reh,'PART4G_SMOKE');
  if v_readiness->>'readiness'<>'NOT_READY' then raise exception 'expected first readiness NOT_READY, got %',v_readiness; end if;

  perform ops.stage_shadow_row(v_final,'Client',5,'WC-B2B-9005','{"client_id":"WC-B2B-9005","company_name":"Epsilon","crm_status":"LEAD"}'::jsonb,'{"client_id":"WC-B2B-9005","company_name":"Epsilon","crm_status":"LEAD"}'::jsonb);
  perform ops.validate_shadow_session(v_final);
  perform ops.attach_final_shadow_session(v_reh,v_final,'FINAL-2','PART4G_SMOKE');
  v_batch2:=ops.build_delta_batch(v_reh,'PART4G_SMOKE');

  if (select insert_count from ops.delta_batches where delta_batch_id=v_batch2)<>2 then raise exception 'expected 2 inserts'; end if;
  if (select update_count from ops.delta_batches where delta_batch_id=v_batch2)<>1 then raise exception 'expected 1 update'; end if;
  if (select source_removed_count from ops.delta_batches where delta_batch_id=v_batch2)<>1 then raise exception 'expected 1 source removal'; end if;
  if (select unchanged_count from ops.delta_batches where delta_batch_id=v_batch2)<>1 then raise exception 'expected 1 unchanged'; end if;
  if (select invalid_count from ops.delta_batches where delta_batch_id=v_batch2)<>0 then raise exception 'expected 0 invalid after correction'; end if;

  perform ops.apply_delta_batch_to_rehearsal_target(v_batch2,'PART4G_SMOKE');
  v_rec2:=ops.reconcile_rehearsal_target(v_reh,'PART4G_SMOKE');
  select status into v_status from ops.rehearsal_reconciliation_runs where rehearsal_reconcile_id=v_rec2;
  if v_status<>'PASS' then raise exception 'expected second scratch reconciliation PASS, got %',v_status; end if;

  perform ops.record_cutover_manual_check(v_reh,'source_removals_reviewed','PASS','{"source_removed_count":1,"decision":"ARCHIVE_IN_REHEARSAL"}'::jsonb,'SMOKE-ARCHIVE-REVIEW','PART4G_SMOKE');
  perform ops.record_cutover_manual_check(v_reh,'file_checksum_mismatch_zero','PASS','{"mismatch_count":0}'::jsonb,'SMOKE-CHECKSUM-EVIDENCE','PART4G_SMOKE');
  perform ops.record_cutover_manual_check(v_reh,'finance_totals_reconcile','PASS','{"variance":0}'::jsonb,'SMOKE-FINANCE-RECON','PART4G_SMOKE');
  perform ops.record_cutover_manual_check(v_reh,'consent_history_intact','PASS','{"history_breaks":0}'::jsonb,'SMOKE-CONSENT-CHECK','PART4G_SMOKE');
  perform ops.record_cutover_manual_check(v_reh,'rls_allow_deny_tests_pass','PASS','{"result":"PASS"}'::jsonb,'PART4D-AUTHZ-RLS-SMOKE','PART4G_SMOKE');
  perform ops.record_cutover_manual_check(v_reh,'part3_idempotency_tests_pass','PASS','{"result":"PASS"}'::jsonb,'PART3-END-TO-END-IDEMPOTENCY-SMOKE','PART4G_SMOKE');

  v_readiness:=ops.evaluate_cutover_readiness(v_reh,'PART4G_SMOKE');
  if v_readiness->>'readiness'<>'READY_TEST' then raise exception 'expected READY_TEST after all checks, got %',v_readiness; end if;
  if config.setting_is_true('migration_target_apply_enabled') or config.setting_is_true('migration_cutover_enabled') or config.setting_is_true('production_cutover_approved') then raise exception 'real migration/cutover gates must remain disabled'; end if;
  if (select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source')<>'GOOGLE_SHEETS_DRIVE' then raise exception 'operational source changed unexpectedly'; end if;
  select count(*) into v_cnt from core.clients where client_id in ('WC-B2B-9001','WC-B2B-9002','WC-B2B-9003','WC-B2B-9004','WC-B2B-9005');
  if v_cnt<>0 then raise exception 'real core master was mutated by rehearsal'; end if;
  select count(*) into v_cnt from ops.rehearsal_target_rows where rehearsal_id=v_reh and is_archived=false;
  if v_cnt<>4 then raise exception 'expected 4 active scratch target rows, got %',v_cnt; end if;
  select count(*) into v_cnt from ops.rehearsal_target_rows where rehearsal_id=v_reh and is_archived=true;
  if v_cnt<>1 then raise exception 'expected 1 archived scratch target row, got %',v_cnt; end if;

  delete from ops.cutover_rehearsals where rehearsal_id=v_reh;
  delete from ops.shadow_import_rows where session_id in (v_base,v_final);
  delete from ops.shadow_import_sessions where session_id in (v_base,v_final);
  update config.system_settings set setting_value='false'::jsonb,updated_at=now()
  where setting_key in ('migration_shadow_write_enabled','migration_rehearsal_enabled','migration_freeze_rehearsal_enabled','migration_delta_capture_enabled','migration_target_apply_enabled','migration_cutover_enabled','production_cutover_approved');
end $$;
