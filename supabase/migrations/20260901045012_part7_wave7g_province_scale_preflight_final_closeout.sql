do $closeout$
declare v_total integer; v_pass integer;
begin
  select count(*),count(*) filter(where status='PASS') into v_total,v_pass from ops.part7g_acceptance_catalog;
  if v_total<>6 or v_pass<>6 then raise exception 'PART7G_ACCEPTANCE_NOT_6_OF_6:%/%',v_pass,v_total; end if;
  if (select count(*) from geo.provinces)<>0 then raise exception 'PART7G_MUST_NOT_AUTO_CREATE_PROVINCES'; end if;
  if (select count(*) from geo.service_areas)<>0 then raise exception 'PART7G_MUST_NOT_AUTO_CREATE_SERVICE_AREAS'; end if;
  if (select count(*) from ops.region_assignments)<>0 then raise exception 'PART7G_MUST_NOT_AUTO_CREATE_REGION_ASSIGNMENTS'; end if;
  if (select count(*) from ops.province_scale_gate_results)<>0 then raise exception 'PART7G_MUST_NOT_AUTO_CREATE_SCALE_GATE_RESULTS'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='province_scale_target_status'),'')<>'TARGET_NOT_SELECTED' then raise exception 'PART7G_TARGET_STATUS_MUST_BE_NOT_SELECTED'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='province_scale_readiness_status'),'')<>'NOT_READY' then raise exception 'PART7G_PROVINCE_READINESS_MUST_BE_NOT_READY'; end if;
  if config.setting_is_true('province_scale_activation_enabled') then raise exception 'PART7G_PROVINCE_ACTIVATION_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_external_access_enabled') then raise exception 'PART7G_PORTAL_EXTERNAL_MUST_REMAIN_OFF'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='portal_production_readiness_status'),'')<>'NOT_READY' then raise exception 'PART7G_PORTAL_PRODUCTION_MUST_REMAIN_NOT_READY'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then raise exception 'PART7G_OPERATIONAL_SOURCE_MUST_REMAIN_GOOGLE_SHEETS_DRIVE'; end if;

  insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
    ('part7g_foundation_closed','true'::jsonb,'Part 7G S10 Province Scale preflight CLOSED/PASS. No target province was selected or activated because explicit target authorization and SG evidence are absent.','Part7G',now()),
    ('province_scale_preflight_status','"CLOSED_TARGET_NOT_SELECTED"'::jsonb,'Province preflight completed; observed demand signal is retained as evidence only and does not authorize target selection.','Part7G',now()),
    ('part7_technical_completion_status','"TEST_TECHNICAL_COMPLETE_EXTERNAL_ACTIVATION_BLOCKED"'::jsonb,'Part 7 technical TEST scope including pilot, Production readiness evaluation, and province preflight is complete. External activation remains blocked by real-world Production/province gates.','Part7G',now())
  on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
end
$closeout$;