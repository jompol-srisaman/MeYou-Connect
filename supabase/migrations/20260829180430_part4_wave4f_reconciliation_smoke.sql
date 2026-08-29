begin;

do $$
declare
  v_session uuid; v_run uuid; v_count int; v_failed boolean:=false; v_summary jsonb;
begin
  begin
    perform ops.open_shadow_import_session('TEST','test-file','Part4F Smoke',null,now(),false,array['Partner','Content'],'{}','part4f-smoke');
  exception when others then
    if position('shadow write gate is disabled' in sqlerrm)>0 then v_failed:=true; else raise; end if;
  end;
  if not v_failed then raise exception 'shadow gate did not block session creation'; end if;

  update config.system_settings set setting_value='true'::jsonb where setting_key='migration_shadow_write_enabled';
  if config.setting_is_true('migration_target_apply_enabled') then raise exception 'target apply gate unexpectedly enabled'; end if;
  if config.setting_is_true('migration_cutover_enabled') then raise exception 'cutover gate unexpectedly enabled'; end if;

  insert into core.partners(partner_id,partner_name,partner_type,status,started_at) values
    ('WC-P-9001','Match Partner','Sourcing Partner','ACTIVE','2026-08-29T00:00:00+00'),
    ('WC-P-9004','Target Only Partner','Sourcing Partner','ACTIVE','2026-08-29T00:00:00+00'),
    ('WC-P-9005','Target Name','Sourcing Partner','ACTIVE','2026-08-29T00:00:00+00');

  v_session:=ops.open_shadow_import_session('TEST','test-file','Part4F Smoke','rev-test',now(),false,array['Partner','Content'],jsonb_build_object('purpose','transactional smoke'),'part4f-smoke');

  perform ops.stage_shadow_row(v_session,'Partner',2,'WC-P-9001',jsonb_build_object('Partner ID','WC-P-9001','ชื่อ Partner','Match Partner'),jsonb_build_object('partner_id','WC-P-9001','partner_name','Match Partner','partner_type','Sourcing Partner','status','ACTIVE'));
  perform ops.stage_shadow_row(v_session,'Partner',3,'WC-P-9002',jsonb_build_object('Partner ID','WC-P-9002','ชื่อ Partner','Source Only'),jsonb_build_object('partner_id','WC-P-9002','partner_name','Source Only','partner_type','Sourcing Partner','status','ACTIVE'));
  perform ops.stage_shadow_row(v_session,'Partner',4,'MYC-P-9003',jsonb_build_object('Partner ID','MYC-P-9003','ชื่อ Partner','Invalid Prefix'),jsonb_build_object('partner_id','MYC-P-9003','partner_name','Invalid Prefix','partner_type','Sourcing Partner','status','ACTIVE'));
  perform ops.stage_shadow_row(v_session,'Partner',5,'WC-P-9005',jsonb_build_object('Partner ID','WC-P-9005','ชื่อ Partner','Source Name'),jsonb_build_object('partner_id','WC-P-9005','partner_name','Source Name','partner_type','Sourcing Partner','status','ACTIVE'));
  perform ops.stage_shadow_row(v_session,'Content',2,'WC-CT-009999',jsonb_build_object('Content ID','WC-CT-009999'),jsonb_build_object('content_id','WC-CT-009999'));

  perform ops.stage_shadow_row(v_session,'Partner',3,'WC-P-9002',jsonb_build_object('Partner ID','WC-P-9002','ชื่อ Partner','Source Only'),jsonb_build_object('partner_id','WC-P-9002','partner_name','Source Only','partner_type','Sourcing Partner','status','ACTIVE'));
  select count(*) into v_count from ops.shadow_import_rows where session_id=v_session and entity_key='Partner' and source_row_number=3;
  if v_count<>1 then raise exception 'stage idempotency failed'; end if;

  v_summary:=ops.validate_shadow_session(v_session);
  if (v_summary->>'valid')::int<>3 or (v_summary->>'invalid')::int<>1 or (v_summary->>'skipped')::int<>1 then raise exception 'validation counts wrong: %',v_summary; end if;

  v_run:=ops.reconcile_shadow_session(v_session,'part4f-smoke');
  select count(*) into v_count from ops.reconciliation_results where run_id=v_run;
  if v_count<>6 then raise exception 'expected 6 reconciliation results, got %',v_count; end if;
  if (select count(*) from ops.reconciliation_results where run_id=v_run and result_type='MATCH')<>1 then raise exception 'MATCH count failed'; end if;
  if (select count(*) from ops.reconciliation_results where run_id=v_run and result_type='SOURCE_ONLY')<>1 then raise exception 'SOURCE_ONLY count failed'; end if;
  if (select count(*) from ops.reconciliation_results where run_id=v_run and result_type='TARGET_ONLY')<>1 then raise exception 'TARGET_ONLY count failed'; end if;
  if (select count(*) from ops.reconciliation_results where run_id=v_run and result_type='FIELD_MISMATCH')<>1 then raise exception 'FIELD_MISMATCH count failed'; end if;
  if (select count(*) from ops.reconciliation_results where run_id=v_run and result_type='INVALID_SOURCE')<>1 then raise exception 'INVALID_SOURCE count failed'; end if;
  if (select count(*) from ops.reconciliation_results where run_id=v_run and result_type='UNSUPPORTED')<>1 then raise exception 'UNSUPPORTED count failed'; end if;
  if not exists(select 1 from ops.reconciliation_results where run_id=v_run and source_pk='MYC-P-9003' and issue_code='SOURCE_VALIDATION_FAILED' and field_diffs::text like '%ID_PATTERN_MISMATCH%') then raise exception 'ID pattern mismatch not surfaced'; end if;
  if not exists(select 1 from ops.reconciliation_results where run_id=v_run and source_pk='WC-P-9005' and field_diffs ? 'partner_name') then raise exception 'field diff not captured'; end if;
  if (select status from ops.reconciliation_runs where run_id=v_run)<>'REVIEW_REQUIRED' then raise exception 'run should require review'; end if;

  if (select count(*) from core.partners where partner_id in ('WC-P-9001','WC-P-9004','WC-P-9005'))<>3 then raise exception 'reconciliation mutated target unexpectedly'; end if;
  if config.setting_is_true('migration_target_apply_enabled') or config.setting_is_true('migration_cutover_enabled') then raise exception 'unsafe migration gate changed'; end if;
end $$;

rollback;