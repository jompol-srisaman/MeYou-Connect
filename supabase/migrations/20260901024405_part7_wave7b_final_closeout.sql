do $closeout$
declare
  v_count integer;
begin
  select count(*) into v_count from ops.part7b_acceptance_catalog where status='PASS';
  if v_count<>10 or (select count(*) from ops.part7b_acceptance_catalog)<>10 then
    raise exception 'PART7B_ACCEPTANCE_NOT_COMPLETE';
  end if;

  if (select count(*) from ops.portal_acceptance_catalog where status='PASS')<>7
     or (select count(*) from ops.portal_acceptance_catalog where status='NOT_RUN')<>7
     or (select count(*) from ops.portal_acceptance_catalog)<>14 then
    raise exception 'CANONICAL_PORTAL_ACCEPTANCE_STATE_UNEXPECTED';
  end if;

  if exists (
    select 1 from config.system_settings
    where setting_key in (
      'portal_external_access_enabled','portal_candidate_enabled','portal_partner_enabled','portal_client_enabled',
      'province_scale_activation_enabled','marketplace_enabled'
    ) and coalesce((setting_value #>> '{}')::boolean,false)=true
  ) then
    raise exception 'EXTERNAL_PORTAL_OR_SCALE_SWITCH_MUST_REMAIN_OFF';
  end if;

  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source'),'')<>'GOOGLE_SHEETS_DRIVE' then
    raise exception 'OPERATIONAL_SOURCE_OF_TRUTH_CHANGED';
  end if;

  if coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='part7a_foundation_closed'),false) is not true then
    raise exception 'PART7A_MUST_REMAIN_CLOSED';
  end if;

  if exists(select 1 from core.clients where client_id in ('MYC-B2B-9993','MYC-B2B-9992','MYC-B2B-9991'))
     or exists(select 1 from core.partners where partner_id in ('MYC-P-9996','MYC-P-9995'))
     or exists(select 1 from core.candidates where candidate_id in ('MYC-C-999901','MYC-C-999902'))
     or exists(select 1 from core.jobs where job_id in ('MYC-J-999901','MYC-J-999902'))
     or exists(select 1 from core.placements where placement_id in ('MYC-PL-999901','MYC-PL-999902'))
     or exists(select 1 from finance.accounts_receivable where ar_id in ('MYC-AR-999901','MYC-AR-999902'))
     or exists(select 1 from finance.revenue where revenue_id in ('P7B-REV-A','P7B-REV-B'))
     or exists(select 1 from finance.commissions where commission_id in ('P7B-COM-A','P7B-COM-B'))
     or exists(select 1 from authz.client_candidate_purpose_access where placement_id in ('MYC-PL-999901','MYC-PL-999902')) then
    raise exception 'PART7B_SYNTHETIC_RESIDUE_DETECTED';
  end if;

  insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
    ('part7b_foundation_closed','true'::jsonb,'Part 7B purpose-specific read projections and cross-scope acceptance closed in TEST. Remaining canonical PT cases stay NOT_RUN until their write/event/admin implementations exist.','Part7B',now()),
    ('portal_production_readiness_status','"NOT_READY"'::jsonb,'External portal Production readiness remains blocked; Part 7B is TEST read-projection foundation only.','Part7B',now())
  on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
end
$closeout$;