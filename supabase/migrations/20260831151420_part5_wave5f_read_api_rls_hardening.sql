create or replace function ops.part5_closeout_status()
returns jsonb language sql security definer set search_path=''
as $$
 select jsonb_build_object(
   'foundation_status',coalesce((select status from ops.part5_latest_closeout_v limit 1),'NOT_EVALUATED'),
   'production_readiness',coalesce((select production_readiness from ops.part5_latest_closeout_v limit 1),'NOT_READY'),
   'foundation_pass_count',coalesce((select pass_count from ops.part5_latest_closeout_v limit 1),0),
   'foundation_fail_count',coalesce((select fail_count from ops.part5_latest_closeout_v limit 1),0),
   'foundation_not_ready_count',coalesce((select not_ready_count from ops.part5_latest_closeout_v limit 1),0),
   'production_blocker_count',(select count(*) from ops.production_security_blockers_v),
   'deployment_execution_enabled',config.setting_is_true('security_deployment_execution_enabled'),
   'cutover_approved',config.setting_is_true('production_cutover_approved')
 )
$$;

create or replace function api.part5_foundation_status()
returns jsonb language plpgsql security definer set search_path=''
as $$ begin perform authz.require_capability('security_read'); return ops.part5_closeout_status(); end $$;

create or replace function api.production_security_blockers()
returns table(gate_id text,gate_name text,status text,observed text,evidence_ref text)
language plpgsql security definer set search_path=''
as $$ begin
 perform authz.require_capability('security_read');
 return query select v.gate_id,v.gate_name,v.status,v.observed,v.evidence_ref from ops.production_security_blockers_v v order by v.gate_id;
end $$;

create or replace function api.change_readiness(p_change_key text)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare c ops.change_requests; r ops.change_readiness_runs;
begin
 perform authz.require_capability('security_read');
 select * into c from ops.change_requests where change_key=p_change_key;
 if not found then return jsonb_build_object('found',false); end if;
 select * into r from ops.change_readiness_runs where change_pk=c.change_pk order by evaluated_at desc limit 1;
 return jsonb_build_object('found',true,'change_key',c.change_key,'environment',c.environment,'risk_key',c.risk_key,'change_status',c.status,'readiness_status',coalesce(r.status,'NOT_EVALUATED'),'pass_count',coalesce(r.pass_count,0),'fail_count',coalesce(r.fail_count,0),'not_ready_count',coalesce(r.not_ready_count,0));
end $$;

revoke all on function ops.part5_closeout_status(),api.part5_foundation_status(),api.production_security_blockers(),api.change_readiness(text) from public,anon;
revoke all on function ops.part5_closeout_status() from authenticated;
grant execute on function ops.part5_closeout_status() to service_role;
grant execute on function api.part5_foundation_status(),api.production_security_blockers(),api.change_readiness(text) to authenticated,service_role;

create policy change_risk_catalog_deny_clients on ops.change_risk_catalog for all to anon,authenticated using(false) with check(false);
create policy change_requests_deny_clients on ops.change_requests for all to anon,authenticated using(false) with check(false);
create policy change_evidence_deny_clients on ops.change_evidence for all to anon,authenticated using(false) with check(false);
create policy change_readiness_runs_deny_clients on ops.change_readiness_runs for all to anon,authenticated using(false) with check(false);
create policy change_readiness_results_deny_clients on ops.change_readiness_results for all to anon,authenticated using(false) with check(false);
create policy part5_closeout_runs_deny_clients on ops.part5_closeout_runs for all to anon,authenticated using(false) with check(false);
create policy part5_closeout_results_deny_clients on ops.part5_closeout_results for all to anon,authenticated using(false) with check(false);