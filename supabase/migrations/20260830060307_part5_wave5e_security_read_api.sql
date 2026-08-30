create or replace function api.security_scan_readiness()
returns table(scope_type text,required_now boolean,result text,coverage_complete boolean,completed_at timestamptz,readiness_status text)
language plpgsql security definer set search_path=''
as $$
begin
 perform authz.require_capability('security_read');
 return query select v.scope_type,v.required_now,v.result,v.coverage_complete,v.completed_at,v.readiness_status from ops.secret_scan_readiness_v v order by v.scope_type;
end $$;

create or replace function api.environment_separation_readiness()
returns table(system_name text,test_registered boolean,prod_registered boolean,separation_status text)
language plpgsql security definer set search_path=''
as $$
begin
 perform authz.require_capability('security_audit_read');
 return query select v.system_name,(v.test_credential_ref is not null),(v.prod_credential_ref is not null),v.separation_status from ops.credential_separation_v v order by v.system_name;
end $$;

create or replace function api.part5e_readiness_status()
returns jsonb language plpgsql security definer set search_path=''
as $$
begin
 perform authz.require_capability('security_read');
 return ops.part5e_readiness();
end $$;

revoke all on function api.security_scan_readiness(),api.environment_separation_readiness(),api.part5e_readiness_status() from public,anon;
grant execute on function api.security_scan_readiness(),api.environment_separation_readiness(),api.part5e_readiness_status() to authenticated,service_role;