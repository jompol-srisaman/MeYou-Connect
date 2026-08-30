create or replace function api.security_api_surface_inventory()
returns table(object_type text,object_name text,object_subtype text,return_type text,rls_enabled boolean)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_audit_read');
  return query select v.object_type::text,v.object_name::text,v.object_subtype::text,v.return_type::text,v.rls_enabled from ops.api_surface_inventory_v v order by v.object_type::text,v.object_name::text;
end $$;

create or replace function api.security_rls_inventory()
returns table(schema_name text,table_name text,rls_enabled boolean,force_rls boolean,policy_count integer)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_audit_read');
  return query select v.schema_name::text,v.table_name::text,v.rls_enabled,v.force_rls,v.policy_count from ops.rls_inventory_v v order by v.schema_name::text,v.table_name::text;
end $$;