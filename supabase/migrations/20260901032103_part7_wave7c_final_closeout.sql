do $closeout$
declare
  v_total integer;
  v_pass integer;
  v_portal_pass integer;
  v_portal_not_run integer;
begin
  select count(*),count(*) filter(where status='PASS') into v_total,v_pass from ops.part7c_acceptance_catalog;
  if v_total<>8 or v_pass<>8 then raise exception 'PART7C_ACCEPTANCE_NOT_8_OF_8:%/%',v_pass,v_total; end if;

  select count(*) filter(where status='PASS'),count(*) filter(where status='NOT_RUN')
    into v_portal_pass,v_portal_not_run from ops.portal_acceptance_catalog;
  if v_portal_pass<>11 or v_portal_not_run<>3 then raise exception 'PORTAL_ACCEPTANCE_EXPECTED_11_PASS_3_NOT_RUN:%/%',v_portal_pass,v_portal_not_run; end if;
  if (select array_agg(test_id order by test_id) from ops.portal_acceptance_catalog where status='NOT_RUN') is distinct from array['PT-006','PT-009','PT-014']::text[] then
    raise exception 'PORTAL_NOT_RUN_SET_UNEXPECTED';
  end if;

  if config.setting_is_true('portal_external_access_enabled') then raise exception 'PORTAL_EXTERNAL_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_candidate_enabled') then raise exception 'PORTAL_CANDIDATE_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_partner_enabled') then raise exception 'PORTAL_PARTNER_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_client_enabled') then raise exception 'PORTAL_CLIENT_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('province_scale_activation_enabled') then raise exception 'PROVINCE_SCALE_ACTIVATION_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('marketplace_enabled') then raise exception 'MARKETPLACE_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('business_master_apply_enabled') then raise exception 'BUSINESS_MASTER_APPLY_MUST_REMAIN_OFF'; end if;
  if (select count(*) from ops.portal_feature_flags where enabled)<>0 then raise exception 'PORTAL_FEATURE_FLAGS_MUST_ALL_BE_OFF'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then
    raise exception 'OPERATIONAL_SOURCE_MUST_REMAIN_GOOGLE_SHEETS_DRIVE';
  end if;
  if not config.setting_is_true('part7a_foundation_closed') then raise exception 'PART7A_MUST_REMAIN_CLOSED'; end if;
  if not config.setting_is_true('part7b_foundation_closed') then raise exception 'PART7B_MUST_REMAIN_CLOSED'; end if;

  if exists(select 1 from ops.portal_action_requests) then raise exception 'PORTAL_ACTION_SYNTHETIC_RESIDUE'; end if;
  if exists(select 1 from core.candidates where candidate_id in ('MYC-C-999911','MYC-C-999912')) then raise exception 'SYNTHETIC_CANDIDATE_RESIDUE'; end if;
  if exists(select 1 from core.placements where placement_id in ('MYC-PL-999911','MYC-PL-999912')) then raise exception 'SYNTHETIC_PLACEMENT_RESIDUE'; end if;
  if exists(select 1 from core.jobs where job_id='MYC-J-999911') then raise exception 'SYNTHETIC_JOB_RESIDUE'; end if;
  if exists(select 1 from core.clients where client_id='MYC-B2B-9981') then raise exception 'SYNTHETIC_CLIENT_RESIDUE'; end if;
  if exists(select 1 from core.partners where partner_id='MYC-P-9981') then raise exception 'SYNTHETIC_PARTNER_RESIDUE'; end if;
  if exists(select 1 from private.candidate_contacts where candidate_id in ('MYC-C-999911','MYC-C-999912')) then raise exception 'SYNTHETIC_CONTACT_RESIDUE'; end if;

  insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
    ('part7c_foundation_closed','true'::jsonb,'Part 7C S5 Portal Command/Event + Candidate controlled write/report foundation CLOSED/PASS in TEST.','Part7C',now()),
    ('portal_production_readiness_status','"NOT_READY"'::jsonb,'External Portal Production remains NOT_READY after Part 7C; PT-006/PT-009/PT-014 and S7 remain.','Part7C',now())
  on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
end
$closeout$;