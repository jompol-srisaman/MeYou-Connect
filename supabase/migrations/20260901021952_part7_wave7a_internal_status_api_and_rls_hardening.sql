insert into authz.role_capabilities(role_key,capability_key) values
('founder','portal_scale_read'),('secretary','portal_scale_read'),('data_audit','portal_scale_read')
on conflict do nothing;

do $policies$
declare r record; p text;
begin
  for r in select * from (values
    ('geo','provinces'),('geo','service_areas'),
    ('authz','organizations'),('authz','organization_members'),('authz','candidate_user_links'),
    ('core','job_service_areas'),('core','partner_service_areas'),('core','dorm_service_areas'),('core','transport_service_areas'),
    ('ops','region_assignments'),('ops','scale_gate_catalog'),('ops','province_scale_state'),('ops','province_scale_gate_results'),
    ('ops','portal_feature_flags'),('ops','portal_acceptance_catalog'),('ops','part7a_acceptance_catalog')
  ) as x(s,t)
  loop
    p:='deny_client_'||r.s||'_'||r.t;
    execute format('drop policy if exists %I on %I.%I',p,r.s,r.t);
    execute format('create policy %I on %I.%I as restrictive for all to anon,authenticated using (false) with check (false)',p,r.s,r.t);
  end loop;
end
$policies$;

create or replace function api.part7a_foundation_status()
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  perform authz.require_capability('portal_scale_read');
  return jsonb_build_object(
    'province_master_rows',(select count(*) from geo.provinces),
    'service_area_rows',(select count(*) from geo.service_areas),
    'organization_rows',(select count(*) from authz.organizations),
    'organization_member_rows',(select count(*) from authz.organization_members),
    'candidate_user_link_rows',(select count(*) from authz.candidate_user_links),
    'scale_gate_count',(select count(*) from ops.scale_gate_catalog where active),
    'portal_acceptance_total',(select count(*) from ops.portal_acceptance_catalog),
    'portal_acceptance_pass',(select count(*) from ops.portal_acceptance_catalog where status='PASS'),
    'part7a_acceptance_total',(select count(*) from ops.part7a_acceptance_catalog),
    'part7a_acceptance_pass',(select count(*) from ops.part7a_acceptance_catalog where status='PASS'),
    'external_portal_enabled',coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='portal_external_access_enabled'),false),
    'candidate_portal_enabled',coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='portal_candidate_enabled'),false),
    'partner_portal_enabled',coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='portal_partner_enabled'),false),
    'client_portal_enabled',coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='portal_client_enabled'),false),
    'province_activation_enabled',coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='province_scale_activation_enabled'),false),
    'marketplace_enabled',coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='marketplace_enabled'),false)
  );
end
$function$;

create or replace function api.portal_feature_flag_status()
returns table(feature_key text,rollout_wave text,environment text,scope_type text,enabled boolean)
language plpgsql security definer set search_path=''
as $function$
begin
  perform authz.require_capability('portal_scale_read');
  return query select f.feature_key,f.rollout_wave,f.environment,case when f.org_id is not null then 'ORGANIZATION' when f.service_area_id is not null then 'SERVICE_AREA' else 'GLOBAL' end,f.enabled from ops.portal_feature_flags f order by f.rollout_wave,f.feature_key,f.environment;
end
$function$;

create or replace function api.portal_acceptance_status()
returns table(test_id text,actor text,scenario text,expected_behavior text,critical boolean,status text,evidence_ref text,last_tested_at timestamptz)
language plpgsql security definer set search_path=''
as $function$
begin
  perform authz.require_capability('portal_scale_read');
  return query select a.test_id,a.actor,a.scenario,a.expected_behavior,a.critical,a.status,a.evidence_ref,a.last_tested_at from ops.portal_acceptance_catalog a order by a.test_id;
end
$function$;

create or replace function api.province_scale_status(p_province_code text)
returns jsonb language plpgsql security definer set search_path=''
as $function$
begin
  perform authz.require_capability('portal_scale_read');
  return ops.province_scale_readiness(p_province_code);
end
$function$;

revoke all on function api.part7a_foundation_status() from public,anon; revoke all on function api.portal_feature_flag_status() from public,anon; revoke all on function api.portal_acceptance_status() from public,anon; revoke all on function api.province_scale_status(text) from public,anon;
grant execute on function api.part7a_foundation_status() to authenticated,service_role; grant execute on function api.portal_feature_flag_status() to authenticated,service_role; grant execute on function api.portal_acceptance_status() to authenticated,service_role; grant execute on function api.province_scale_status(text) to authenticated,service_role;