do $closeout$
declare
  v_total integer; v_pass integer; v_portal_total integer; v_portal_pass integer;
begin
  select count(*),count(*) filter(where status='PASS') into v_total,v_pass from ops.part7d_acceptance_catalog;
  if v_total<>8 or v_pass<>8 then raise exception 'PART7D_ACCEPTANCE_NOT_8_OF_8:%/%',v_pass,v_total; end if;

  select count(*),count(*) filter(where status='PASS') into v_portal_total,v_portal_pass from ops.portal_acceptance_catalog;
  if v_portal_total<>14 or v_portal_pass<>14 then raise exception 'PORTAL_ACCEPTANCE_NOT_14_OF_14:%/%',v_portal_pass,v_portal_total; end if;

  if config.setting_is_true('portal_external_access_enabled') then raise exception 'PORTAL_EXTERNAL_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_candidate_enabled') then raise exception 'PORTAL_CANDIDATE_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_partner_enabled') then raise exception 'PORTAL_PARTNER_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('portal_client_enabled') then raise exception 'PORTAL_CLIENT_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('province_scale_activation_enabled') then raise exception 'PROVINCE_SCALE_ACTIVATION_MUST_REMAIN_OFF'; end if;
  if config.setting_is_true('marketplace_enabled') then raise exception 'MARKETPLACE_MUST_REMAIN_OFF'; end if;
  if (select count(*) from ops.portal_feature_flags where enabled)<>0 then raise exception 'PORTAL_FEATURE_FLAGS_MUST_ALL_BE_OFF'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then raise exception 'OPERATIONAL_SOURCE_MUST_REMAIN_GOOGLE_SHEETS_DRIVE'; end if;
  if not config.setting_is_true('part7a_foundation_closed') then raise exception 'PART7A_MUST_REMAIN_CLOSED'; end if;
  if not config.setting_is_true('part7b_foundation_closed') then raise exception 'PART7B_MUST_REMAIN_CLOSED'; end if;
  if not config.setting_is_true('part7c_foundation_closed') then raise exception 'PART7C_MUST_REMAIN_CLOSED'; end if;

  if exists(select 1 from ops.portal_action_requests) then raise exception 'PORTAL_ACTION_SYNTHETIC_RESIDUE'; end if;
  if exists(select 1 from ops.portal_support_access_audit) then raise exception 'SUPPORT_ACCESS_SYNTHETIC_RESIDUE'; end if;
  if exists(select 1 from core.clients where client_id in ('MYC-B2B-9971','MYC-B2B-9972')) then raise exception 'SYNTHETIC_CLIENT_RESIDUE'; end if;
  if exists(select 1 from core.partners where partner_id in ('MYC-P-9971','MYC-P-9972')) then raise exception 'SYNTHETIC_PARTNER_RESIDUE'; end if;
  if exists(select 1 from finance.accounts_receivable where ar_id in ('MYC-AR-999921','MYC-AR-999922')) then raise exception 'SYNTHETIC_AR_RESIDUE'; end if;
  if exists(select 1 from finance.revenue where revenue_id in ('P7D-REV-A','P7D-REV-B')) then raise exception 'SYNTHETIC_REVENUE_RESIDUE'; end if;

  insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
    ('part7d_foundation_closed','true'::jsonb,'Part 7D S7 MFA/step-up protected Portal controls CLOSED/PASS in TEST; canonical PT acceptance 14/14 PASS.','Part7D',now()),
    ('portal_production_readiness_status','"NOT_READY"'::jsonb,'Part 7 TEST acceptance is complete, but Production external Portal remains NOT_READY until Founder-approved pilot trigger and Production gates/evidence are satisfied.','Part7D',now())
  on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
end
$closeout$;