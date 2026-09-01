do $closeout$
declare v_total integer; v_pass integer;
begin
  select count(*),count(*) filter(where status='PASS') into v_total,v_pass from ops.part7e_acceptance_catalog;
  if v_total<>8 or v_pass<>8 then raise exception 'PART7E_ACCEPTANCE_NOT_8_OF_8:%/%',v_pass,v_total; end if;
  if config.setting_is_true('portal_external_access_enabled') then raise exception 'PORTAL_EXTERNAL_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_client_enabled') then raise exception 'PORTAL_CLIENT_MUST_REMAIN_OFF'; end if;
  if (select count(*) from ops.portal_feature_flags where enabled)<>0 then raise exception 'PORTAL_FEATURE_FLAGS_MUST_ALL_BE_OFF'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then raise exception 'OPERATIONAL_SOURCE_MUST_REMAIN_GOOGLE_SHEETS_DRIVE'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='part7_pilot_selected'),'')<>'P1B_CLIENT_DEMAND_LITE' then raise exception 'P1B_PILOT_SELECTION_REQUIRED'; end if;
  if exists(select 1 from ops.portal_action_requests) then raise exception 'PORTAL_ACTION_SYNTHETIC_RESIDUE'; end if;
  if exists(select 1 from ops.client_demand_review_queue) then raise exception 'CLIENT_DEMAND_REVIEW_SYNTHETIC_RESIDUE'; end if;
  if exists(select 1 from core.clients where client_id in ('MYC-B2B-9961','MYC-B2B-9962')) then raise exception 'SYNTHETIC_CLIENT_RESIDUE'; end if;
  if exists(select 1 from core.jobs where client_id in ('MYC-B2B-9961','MYC-B2B-9962')) then raise exception 'SYNTHETIC_JOB_RESIDUE'; end if;

  insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
    ('part7e_foundation_closed','true'::jsonb,'P1B Client Demand Lite technical pilot CLOSED/PASS in TEST; review-only write boundary proven with no Job Master effect.','Part7E',now()),
    ('part7_pilot_technical_status','"P1B_TEST_READY"'::jsonb,'P1B technical pilot capability is TEST-ready but no real external organization or Production portal is enabled.','Part7E',now()),
    ('portal_production_readiness_status','"NOT_READY"'::jsonb,'P1B TEST capability is ready; Production remains NOT_READY pending Production gates, fresh backup, named support owner/route and explicit rollout approval.','Part7E',now())
  on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
end
$closeout$;