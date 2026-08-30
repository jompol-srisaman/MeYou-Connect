do $$
declare t text;
begin
  foreach t in array array['security_control_catalog','security_gate_catalog','security_evidence_records','privileged_identity_registry','secret_inventory','security_events','security_gate_runs','security_gate_results'] loop
    execute format('alter table ops.%I enable row level security',t);
    execute format('drop policy if exists %I on ops.%I','p5a_'||t||'_deny_clients',t);
    execute format('create policy %I on ops.%I for all to anon, authenticated using (false) with check (false)','p5a_'||t||'_deny_clients',t);
    execute format('revoke all on table ops.%I from public, anon, authenticated',t);
    execute format('grant select,insert,update,delete on table ops.%I to service_role',t);
  end loop;
end $$;

revoke all on ops.api_surface_inventory_v from public,anon,authenticated;
revoke all on ops.security_definer_inventory_v from public,anon,authenticated;
revoke all on ops.rls_inventory_v from public,anon,authenticated;
revoke all on ops.storage_security_v from public,anon,authenticated;
revoke all on ops.security_latest_gate_v from public,anon,authenticated;
grant select on ops.api_surface_inventory_v,ops.security_definer_inventory_v,ops.rls_inventory_v,ops.storage_security_v,ops.security_latest_gate_v to service_role;

insert into authz.role_capabilities(role_key,capability_key) values
('founder','security_read'),('founder','security_audit_read'),
('secretary','security_read'),
('data_audit','security_read'),('data_audit','security_audit_read')
on conflict do nothing;

create or replace function api.security_foundation_status() returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_read');
  return ops.part5a_foundation_status();
end $$;

create or replace function api.security_control_summary()
returns table(control_id text,domain text,control_name text,critical boolean,source_status text,owner_role text,evidence_required text)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_read');
  return query select c.control_id,c.domain,c.control_name,c.critical,c.source_status,c.owner_role,c.evidence_required from ops.security_control_catalog c order by c.control_id;
end $$;

create or replace function api.security_gate_status(p_environment text default 'PROD')
returns table(gate_id text,gate_name text,status text,expected text,observed text,evidence_ref text,notes text,run_pk uuid,evaluated_at timestamptz)
language plpgsql
security definer
set search_path=''
as $$
declare v_run uuid;
begin
  perform authz.require_capability('security_read');
  if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
  select r.run_pk into v_run from ops.security_gate_runs r where r.environment=p_environment and r.status<>'RUNNING' order by r.started_at desc,r.run_pk desc limit 1;
  if v_run is null then return; end if;
  return query
  select c.gate_id,c.gate_name,x.status,x.expected,x.observed,x.evidence_ref,x.notes,x.run_pk,r.completed_at
  from ops.security_gate_results x
  join ops.security_gate_catalog c on c.gate_id=x.gate_id
  join ops.security_gate_runs r on r.run_pk=x.run_pk
  where x.run_pk=v_run
  order by c.gate_id;
end $$;

create or replace function api.security_gate_issues(p_environment text default 'PROD')
returns table(gate_id text,gate_name text,status text,observed text,evidence_ref text,notes text)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_read');
  return query select s.gate_id,s.gate_name,s.status,s.observed,s.evidence_ref,s.notes from api.security_gate_status(p_environment) s where s.status<>'PASS' order by s.gate_id;
end $$;

create or replace function api.security_api_surface_inventory()
returns table(object_type text,object_name text,object_subtype text,return_type text,rls_enabled boolean)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_audit_read');
  return query select v.object_type,v.object_name,v.object_subtype,v.return_type,v.rls_enabled from ops.api_surface_inventory_v v order by v.object_type,v.object_name;
end $$;

create or replace function api.security_rls_inventory()
returns table(schema_name text,table_name text,rls_enabled boolean,force_rls boolean,policy_count integer)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_audit_read');
  return query select v.schema_name,v.table_name,v.rls_enabled,v.force_rls,v.policy_count from ops.rls_inventory_v v order by v.schema_name,v.table_name;
end $$;

create or replace function api.security_privileged_identity_summary()
returns table(environment text,active_identities bigint,named_verified bigint,mfa_verified bigint)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_audit_read');
  return query
  select x.environment,
         count(*) filter(where x.status='ACTIVE')::bigint,
         count(*) filter(where x.status='ACTIVE' and x.named_identity_verified)::bigint,
         count(*) filter(where x.status='ACTIVE' and x.mfa_status in ('VERIFIED','NOT_APPLICABLE'))::bigint
  from ops.privileged_identity_registry x
  group by x.environment
  order by x.environment;
end $$;

revoke all on function api.security_foundation_status() from public,anon;
revoke all on function api.security_control_summary() from public,anon;
revoke all on function api.security_gate_status(text) from public,anon;
revoke all on function api.security_gate_issues(text) from public,anon;
revoke all on function api.security_api_surface_inventory() from public,anon;
revoke all on function api.security_rls_inventory() from public,anon;
revoke all on function api.security_privileged_identity_summary() from public,anon;
grant usage on schema api to authenticated,service_role;
grant execute on function api.security_foundation_status(),api.security_control_summary(),api.security_gate_status(text),api.security_gate_issues(text),api.security_api_surface_inventory(),api.security_rls_inventory(),api.security_privileged_identity_summary() to authenticated,service_role;