alter table ops.backup_policy_catalog enable row level security;
alter table ops.backup_runs enable row level security;
alter table ops.backup_artifacts enable row level security;
alter table ops.restore_test_runs enable row level security;
alter table ops.recovery_monitor_snapshots enable row level security;

drop policy if exists backup_policy_client_deny on ops.backup_policy_catalog;
create policy backup_policy_client_deny on ops.backup_policy_catalog for all to anon,authenticated using (false) with check (false);
drop policy if exists backup_runs_client_deny on ops.backup_runs;
create policy backup_runs_client_deny on ops.backup_runs for all to anon,authenticated using (false) with check (false);
drop policy if exists backup_artifacts_client_deny on ops.backup_artifacts;
create policy backup_artifacts_client_deny on ops.backup_artifacts for all to anon,authenticated using (false) with check (false);
drop policy if exists restore_test_client_deny on ops.restore_test_runs;
create policy restore_test_client_deny on ops.restore_test_runs for all to anon,authenticated using (false) with check (false);
drop policy if exists recovery_snapshot_client_deny on ops.recovery_monitor_snapshots;
create policy recovery_snapshot_client_deny on ops.recovery_monitor_snapshots for all to anon,authenticated using (false) with check (false);

revoke all on ops.backup_policy_catalog,ops.backup_runs,ops.backup_artifacts,ops.restore_test_runs,ops.recovery_monitor_snapshots from anon,authenticated;
revoke all on ops.backup_freshness_v,ops.restore_readiness_v,ops.recovery_readiness_v from anon,authenticated;
grant select,insert,update,delete on ops.backup_policy_catalog,ops.backup_runs,ops.backup_artifacts,ops.restore_test_runs,ops.recovery_monitor_snapshots to service_role;
grant select on ops.backup_freshness_v,ops.restore_readiness_v,ops.recovery_readiness_v to service_role;

create or replace function api.recovery_foundation_status() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_test jsonb; v_google jsonb;
begin
 perform authz.require_capability('security_read');
 select to_jsonb(r) into v_test from ops.recovery_readiness_v r where environment='TEST';
 select to_jsonb(r) into v_google from ops.recovery_readiness_v r where environment='GOOGLE';
 return jsonb_build_object('foundation_ready',config.setting_is_true('security_recovery_foundation_ready'),'monitoring_enabled',config.setting_is_true('security_recovery_monitoring_enabled'),'backup_automation_enabled',config.setting_is_true('security_backup_automation_enabled'),'restore_automation_enabled',config.setting_is_true('security_restore_automation_enabled'),'test',coalesce(v_test,'{}'::jsonb),'google',coalesce(v_google,'{}'::jsonb));
end $$;

create or replace function api.backup_policy_status() returns setof ops.backup_freshness_v language plpgsql stable security definer set search_path='' as $$ begin perform authz.require_capability('security_read'); return query select * from ops.backup_freshness_v order by environment,policy_key; end $$;
create or replace function api.restore_readiness() returns setof ops.restore_readiness_v language plpgsql stable security definer set search_path='' as $$ begin perform authz.require_capability('security_read'); return query select * from ops.restore_readiness_v order by completed_at desc; end $$;
create or replace function api.recovery_monitor_history(p_environment text default 'TEST',p_limit integer default 50) returns setof ops.recovery_monitor_snapshots language plpgsql stable security definer set search_path='' as $$ begin perform authz.require_capability('security_audit_read'); if p_environment not in ('TEST','PROD','GOOGLE') then raise exception 'INVALID_ENVIRONMENT'; end if; return query select * from ops.recovery_monitor_snapshots where environment=p_environment order by captured_at desc limit least(greatest(coalesce(p_limit,50),1),200); end $$;

revoke all on function api.recovery_foundation_status() from public,anon;
revoke all on function api.backup_policy_status() from public,anon;
revoke all on function api.restore_readiness() from public,anon;
revoke all on function api.recovery_monitor_history(text,integer) from public,anon;
grant execute on function api.recovery_foundation_status(),api.backup_policy_status(),api.restore_readiness(),api.recovery_monitor_history(text,integer) to authenticated,service_role;