create or replace view ops.part7a_status_v as
select
  (select count(*) from geo.provinces) as province_master_rows,
  (select count(*) from geo.service_areas) as service_area_rows,
  (select count(*) from authz.organizations) as organization_rows,
  (select count(*) from authz.organization_members) as organization_member_rows,
  (select count(*) from authz.candidate_user_links) as candidate_user_link_rows,
  (select count(*) from ops.scale_gate_catalog where active) as scale_gate_count,
  (select count(*) from ops.portal_feature_flags) as portal_feature_flag_count,
  (select count(*) from ops.portal_feature_flags where enabled) as enabled_portal_feature_flags,
  (select count(*) from ops.portal_acceptance_catalog) as portal_acceptance_total,
  (select count(*) from ops.portal_acceptance_catalog where status='PASS') as portal_acceptance_pass,
  (select count(*) from ops.portal_acceptance_catalog where status='NOT_RUN') as portal_acceptance_not_run,
  (select count(*) from ops.part7a_acceptance_catalog) as part7a_acceptance_total,
  (select count(*) from ops.part7a_acceptance_catalog where status='PASS') as part7a_acceptance_pass,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='portal_external_access_enabled'),false) as portal_external_access_enabled,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='province_scale_activation_enabled'),false) as province_scale_activation_enabled,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='marketplace_enabled'),false) as marketplace_enabled,
  'CLOSED'::text as part7a_foundation_status,
  'NOT_READY'::text as external_portal_status;

revoke all on ops.part7a_status_v from public,anon,authenticated;
grant select on ops.part7a_status_v to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref) values
('portal_scale_foundation_ready','true'::jsonb,'Part 7A geography/organization/portal-access foundation implemented and accepted in TEST.','Part7A'),
('part7a_foundation_closed','true'::jsonb,'Part 7A implementation foundation closed in TEST.','Part7A'),
('portal_production_readiness_status','"NOT_READY"'::jsonb,'External portal Production readiness remains blocked until canonical PT acceptance and Founder/Architect approval.','Part7A'),
('portal_external_access_enabled','false'::jsonb,'External portal master switch remains off after Part 7A.','Part7A'),
('portal_candidate_enabled','false'::jsonb,'Candidate portal remains disabled after Part 7A.','Part7A'),
('portal_partner_enabled','false'::jsonb,'Partner portal remains disabled after Part 7A.','Part7A'),
('portal_client_enabled','false'::jsonb,'Client portal remains disabled after Part 7A.','Part7A'),
('province_scale_activation_enabled','false'::jsonb,'Real province ACTIVE transition remains disabled after Part 7A.','Part7A'),
('marketplace_enabled','false'::jsonb,'Marketplace capability is not authorized by Part 7.','Part7A')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

do $closeout$
begin
  if (select count(*) from ops.part7a_acceptance_catalog where status='PASS')<>8 then raise exception 'PART7A_ACCEPTANCE_NOT_COMPLETE'; end if;
  if (select count(*) from ops.portal_acceptance_catalog where status='NOT_RUN')<>14 then raise exception 'PORTAL_ACCEPTANCE_MUST_REMAIN_NOT_RUN_AFTER_7A'; end if;
  if (select count(*) from ops.portal_feature_flags where enabled)<>0 then raise exception 'PORTAL_FEATURE_FLAGS_MUST_REMAIN_DISABLED'; end if;
  if coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='portal_external_access_enabled'),false) then raise exception 'PORTAL_EXTERNAL_ACCESS_MUST_REMAIN_OFF'; end if;
  if coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='province_scale_activation_enabled'),false) then raise exception 'PROVINCE_ACTIVATION_MUST_REMAIN_OFF'; end if;
  if coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='marketplace_enabled'),false) then raise exception 'MARKETPLACE_MUST_REMAIN_OFF'; end if;
end
$closeout$;