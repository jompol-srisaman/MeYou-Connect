do $$
declare
  v_test jsonb;
  v_prod jsonb;
  v_test_run uuid;
  v_prod_run uuid;
  v_gate boolean;
  v_source text;
begin
  perform ops.record_part4_evidence('PART4_REPOSITORY_OUTPUTS','PASS','SMOKE://repository','{"synthetic":true}'::jsonb,'Part4H Smoke');
  perform ops.record_part4_evidence('PART4_SECURITY_ADVISOR','PASS','SMOKE://security-advisor','{"synthetic":true}'::jsonb,'Part4H Smoke');

  v_test:=ops.evaluate_part4_closeout('TEST_IMPLEMENTATION','Part4H Smoke');
  if v_test->>'status' <> 'PASS' then
    raise exception 'Part4H TEST closeout smoke expected PASS, got %',v_test;
  end if;
  v_test_run:=(v_test->>'closeout_run_id')::uuid;

  v_prod:=ops.evaluate_part4_closeout('PRODUCTION_READINESS','Part4H Smoke');
  if v_prod->>'status' <> 'NOT_READY' then
    raise exception 'Part4H Production readiness smoke expected NOT_READY, got %',v_prod;
  end if;
  v_prod_run:=(v_prod->>'closeout_run_id')::uuid;

  select config.setting_is_true('production_cutover_approved') into v_gate;
  if v_gate then raise exception 'Production cutover approval gate changed during smoke'; end if;
  select config.setting_is_true('migration_cutover_enabled') into v_gate;
  if v_gate then raise exception 'Migration cutover gate changed during smoke'; end if;
  select config.setting_is_true('migration_target_apply_enabled') into v_gate;
  if v_gate then raise exception 'Migration target apply gate changed during smoke'; end if;

  select setting_value #>> '{}' into v_source from config.system_settings where setting_key='current_operational_source';
  if v_source <> 'GOOGLE_SHEETS_DRIVE' then raise exception 'Operational Source of Truth changed during smoke: %',v_source; end if;

  if not exists(select 1 from ops.part4_closeout_results where closeout_run_id=v_test_run and check_key='T_REPOSITORY_OUTPUTS' and status='PASS') then
    raise exception 'Repository evidence check did not PASS in TEST smoke';
  end if;
  if not exists(select 1 from ops.part4_closeout_results where closeout_run_id=v_prod_run and check_key='P_FOUNDER_APPROVAL' and status='NOT_READY') then
    raise exception 'Founder approval must remain NOT_READY in Production smoke';
  end if;

  delete from ops.part4_closeout_runs where closeout_run_id in (v_test_run,v_prod_run);
  delete from ops.part4_evidence_records where evidence_key in ('PART4_REPOSITORY_OUTPUTS','PART4_SECURITY_ADVISOR') and recorded_by='Part4H Smoke';

  update config.system_settings set setting_value='false'::jsonb,source_ref='Part4H smoke cleanup',updated_at=now() where setting_key='part4_test_implementation_closed';
  update config.system_settings set setting_value='"NOT_READY"'::jsonb,source_ref='Part4H smoke cleanup',updated_at=now() where setting_key='part4_production_readiness_status';
end;
$$;
