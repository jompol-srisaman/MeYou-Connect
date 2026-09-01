do $closeout$
declare
  v_total integer;
  v_pass integer;
  v_latest uuid;
  v_status text;
  v_nr integer;
begin
  select count(*),count(*) filter(where status='PASS') into v_total,v_pass from ops.part7f_acceptance_catalog;
  if v_total<>6 or v_pass<>6 then raise exception 'PART7F_ACCEPTANCE_NOT_6_OF_6:%/%',v_pass,v_total; end if;
  select run_pk,overall_status,not_ready_count into v_latest,v_status,v_nr from ops.portal_production_readiness_runs order by evaluated_at desc limit 1;
  if v_latest is null then raise exception 'PART7F_READINESS_RUN_MISSING'; end if;
  if v_status<>'NOT_READY' or v_nr<=0 then raise exception 'PART7F_EXPECTED_NOT_READY_WITH_BLOCKERS:%/%',v_status,v_nr; end if;
  if (select count(*) from ops.portal_production_gate_results where run_pk=v_latest)<>16 then raise exception 'PART7F_GATE_RESULT_COUNT_NOT_16'; end if;
  if config.setting_is_true('portal_external_access_enabled') then raise exception 'PORTAL_EXTERNAL_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_candidate_enabled') or config.setting_is_true('portal_partner_enabled') or config.setting_is_true('portal_client_enabled') then raise exception 'PORTAL_SUBSYSTEMS_MUST_REMAIN_OFF'; end if;
  if (select count(*) from ops.portal_feature_flags where enabled)<>0 then raise exception 'PORTAL_FEATURE_FLAGS_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('province_scale_activation_enabled') then raise exception 'PROVINCE_ACTIVATION_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('marketplace_enabled') then raise exception 'MARKETPLACE_MUST_REMAIN_OFF'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then raise exception 'OPERATIONAL_SOURCE_MUST_REMAIN_GOOGLE_SHEETS_DRIVE'; end if;

  insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
    ('part7f_foundation_closed','true'::jsonb,'Part 7F Production readiness evaluation CLOSED/PASS as an evaluation wave. Production Portal itself remains NOT_READY because required Production evidence is missing.','Part7F run '||v_latest::text,now()),
    ('part7f_readiness_evaluation_status','"CLOSED_NOT_READY"'::jsonb,'Production readiness evaluation completed correctly with explicit blockers; this is not a Production approval.','Part7F run '||v_latest::text,now()),
    ('portal_production_readiness_status','"NOT_READY"'::jsonb,'Production Portal remains blocked until all PPG gates have sufficient Production/approval evidence.','Part7F run '||v_latest::text,now())
  on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
end
$closeout$;