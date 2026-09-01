create or replace function api.portal_client_jobs(p_org_id uuid)
returns table(
  job_id text,
  workplace_name text,
  province text,
  area text,
  position_name text,
  headcount integer,
  wage numeric,
  shift text,
  start_date date,
  status text,
  last_confirmed_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_client_id text;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  if not authz.is_active_org_member(p_org_id) then raise exception 'ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_admin') or authz.has_portal_role(p_org_id,'client_recruiter')) then
    raise exception 'CLIENT_RECRUITMENT_ROLE_REQUIRED';
  end if;
  select o.business_party_id into v_client_id
  from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORGANIZATION_REQUIRED'; end if;

  return query
  select j.job_id,j.workplace_name,j.province,j.area,j.position_name,j.headcount,j.wage,j.shift,
         j.start_date,j.status,j.last_confirmed_at,j.updated_at
  from core.jobs j where j.client_id=v_client_id
  order by j.updated_at desc,j.job_id;
end
$$;

revoke all on function api.portal_client_jobs(uuid) from public, anon, authenticated;
grant execute on function api.portal_client_jobs(uuid) to authenticated, service_role;

do $role_test$
declare
  u_fin uuid:=gen_random_uuid();
  v_org uuid;
  v_failed boolean:=false;
  old_external jsonb;
  old_client jsonb;
begin
  select setting_value into old_external from config.system_settings where setting_key='portal_external_access_enabled';
  select setting_value into old_client from config.system_settings where setting_key='portal_client_enabled';
  update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key in ('portal_external_access_enabled','portal_client_enabled');

  delete from authz.organization_members where org_id in (select org_id from authz.organizations where business_party_id='MYC-B2B-9991');
  delete from authz.organizations where business_party_id='MYC-B2B-9991';
  delete from core.clients where client_id='MYC-B2B-9991';
  insert into core.clients(client_id,client_type,company_name,crm_status,verification_status) values('MYC-B2B-9991','TEST','Part7B Finance Role Test','ACTIVE','VERIFIED');
  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9991','ACTIVE') returning org_id into v_org;
  insert into auth.users(id) values(u_fin);
  insert into authz.organization_members(org_id,auth_user_id,portal_role,membership_status,active_from,created_by)
    values(v_org,u_fin,'client_finance','ACTIVE',now()-interval '1 minute','PART7B_ROLE_TEST');

  perform set_config('request.jwt.claim.sub',u_fin::text,true);
  execute 'set local role authenticated';
  begin
    perform 1 from api.portal_client_jobs(v_org) limit 1;
  exception when others then
    if position('CLIENT_RECRUITMENT_ROLE_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if;
  end;
  execute 'reset role';
  if not v_failed then raise exception 'P7B_CLIENT_FINANCE_JOB_ACCESS_NOT_DENIED'; end if;

  perform set_config('request.jwt.claim.sub','',true);
  delete from authz.organization_members where org_id=v_org;
  delete from authz.organizations where org_id=v_org;
  delete from core.clients where client_id='MYC-B2B-9991';
  delete from auth.users where id=u_fin;
  update config.system_settings set setting_value=coalesce(old_external,'false'::jsonb),updated_at=now() where setting_key='portal_external_access_enabled';
  update config.system_settings set setting_value=coalesce(old_client,'false'::jsonb),updated_at=now() where setting_key='portal_client_enabled';
end
$role_test$;