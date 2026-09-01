do $smoke$
declare
  v_preflight jsonb;
  v_failed boolean:=false;
  v_province_count integer;
  v_area_count integer;
  v_assignment_count integer;
  v_gate_result_count integer;
  v_gate_ready_count integer;
begin
  v_preflight:=ops.evaluate_province_scale_preflight();
  if v_preflight->>'status'<>'TARGET_NOT_SELECTED' then raise exception 'P7G-001_EXPECTED_TARGET_NOT_SELECTED:%',v_preflight; end if;
  if coalesce((v_preflight->>'target_selected')::boolean,true) then raise exception 'P7G-001_TARGET_MUST_NOT_BE_AUTO_SELECTED'; end if;
  if coalesce((v_preflight->>'active_transition_ready')::boolean,true) then raise exception 'P7G-001_ACTIVE_TRANSITION_MUST_BE_FALSE'; end if;
  if coalesce((v_preflight #>> '{observed_demand_signal,authorizes_target}')::boolean,true) then raise exception 'P7G-001_DEMAND_SIGNAL_MUST_NOT_AUTHORIZE_TARGET'; end if;

  select count(*) into v_province_count from geo.provinces;
  select count(*) into v_area_count from geo.service_areas;
  select count(*) into v_assignment_count from ops.region_assignments;
  select count(*) into v_gate_result_count from ops.province_scale_gate_results;
  select count(*) into v_gate_ready_count from ops.province_scale_gate_results where readiness_status='READY';
  if v_province_count<>0 or v_area_count<>0 or v_assignment_count<>0 then raise exception 'P7G-002_NO_AUTO_GEOGRAPHY_EXPECTED:%/%/%',v_province_count,v_area_count,v_assignment_count; end if;
  if v_gate_result_count<>0 or v_gate_ready_count<>0 then raise exception 'P7G-003_NO_GATE_RESULTS_EXPECTED:%/%',v_gate_result_count,v_gate_ready_count; end if;
  if config.setting_is_true('province_scale_activation_enabled') then raise exception 'P7G-004_PROVINCE_ACTIVATION_MUST_REMAIN_OFF'; end if;

  begin
    perform ops.set_province_lifecycle('TH-14','DEMAND_VALIDATION','PART7G_SMOKE','Missing target master must fail');
  exception when foreign_key_violation then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'P7G-005_MISSING_TARGET_LIFECYCLE_NOT_DENIED'; end if;
  if exists(select 1 from ops.province_scale_state where province_code='TH-14') then raise exception 'P7G-005_FAILED_LIFECYCLE_LEFT_RESIDUE'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then raise exception 'P7G-006_OPERATIONAL_SOURCE_CHANGED'; end if;

  update ops.part7g_acceptance_catalog set status='PASS',evidence_ref='part7_wave7g_province_scale_preflight_acceptance_smoke',last_tested_at=now(),updated_at=now();
end
$smoke$;