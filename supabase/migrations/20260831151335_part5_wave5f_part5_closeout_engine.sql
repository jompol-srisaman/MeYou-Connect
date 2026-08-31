create or replace function ops.add_part5_closeout_result(p_run uuid,p_key text,p_status text,p_observed text,p_ref text default null)
returns void language sql security definer set search_path=''
as $$
 insert into ops.part5_closeout_results(closeout_run_pk,check_key,status,observed,evidence_ref)
 values(p_run,p_key,p_status,p_observed,p_ref)
$$;

create or replace function ops.evaluate_part5_closeout(p_actor text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
 v_run uuid; vp int; vf int; vn int; overall text; prod_gate text; test_gate text; b boolean;
begin
 if p_actor is null or btrim(p_actor)='' then raise exception 'ACTOR_REQUIRED'; end if;
 insert into ops.part5_closeout_runs(environment,evaluated_by,status) values('TEST',p_actor,'NOT_READY') returning closeout_run_pk into v_run;

 b:=config.setting_is_true('part5a_foundation_closed'); perform ops.add_part5_closeout_result(v_run,'5A_FOUNDATION',case when b then 'PASS' else 'NOT_READY' end,'5A foundation closed='||b,null);
 b:=config.setting_is_true('part5b_foundation_closed') and config.setting_is_true('security_webhook_enforcement_ready'); perform ops.add_part5_closeout_result(v_run,'5B_FOUNDATION',case when b then 'PASS' else 'NOT_READY' end,'5B foundation + webhook guard ready='||b,null);
 b:=config.setting_is_true('part5c_foundation_closed') and config.setting_is_true('security_observability_foundation_ready'); perform ops.add_part5_closeout_result(v_run,'5C_FOUNDATION',case when b then 'PASS' else 'NOT_READY' end,'5C foundation + observability ready='||b,null);
 b:=config.setting_is_true('part5d_foundation_closed') and config.setting_is_true('security_recovery_foundation_ready'); perform ops.add_part5_closeout_result(v_run,'5D_FOUNDATION',case when b then 'PASS' else 'NOT_READY' end,'5D foundation + recovery control ready='||b,null);
 b:=config.setting_is_true('part5e_foundation_closed') and config.setting_is_true('security_secret_environment_foundation_ready'); perform ops.add_part5_closeout_result(v_run,'5E_FOUNDATION',case when b then 'PASS' else 'NOT_READY' end,'5E foundation + secret/environment control ready='||b,null);
 b:=config.setting_is_true('security_change_control_ready'); perform ops.add_part5_closeout_result(v_run,'5F_CHANGE_CONTROL',case when b then 'PASS' else 'NOT_READY' end,'5F change control ready='||b,null);

 select status into test_gate from ops.security_gate_runs where environment='TEST' and completed_at is not null order by completed_at desc limit 1;
 select status into prod_gate from ops.security_gate_runs where environment='PROD' and completed_at is not null order by completed_at desc limit 1;
 perform ops.add_part5_closeout_result(v_run,'TEST_GATE_NO_FAILURE',case when test_gate='FAIL' then 'FAIL' else 'PASS' end,'Latest TEST gate='||coalesce(test_gate,'NONE'),null);

 b:=config.setting_is_true('production_cutover_approved'); perform ops.add_part5_closeout_result(v_run,'CUTOVER_REMAINS_OFF',case when not b then 'PASS' else 'FAIL' end,'production_cutover_approved='||b,null);
 b:=config.setting_is_true('security_production_gate_enabled'); perform ops.add_part5_closeout_result(v_run,'PRODUCTION_GATE_REMAINS_OFF',case when not b then 'PASS' else 'FAIL' end,'security_production_gate_enabled='||b,null);
 b:=config.setting_is_true('security_external_alert_delivery_enabled'); perform ops.add_part5_closeout_result(v_run,'EXTERNAL_ALERT_REMAINS_OFF',case when not b then 'PASS' else 'FAIL' end,'external alert delivery enabled='||b,null);
 b:=config.setting_is_true('security_backup_automation_enabled'); perform ops.add_part5_closeout_result(v_run,'AUTO_BACKUP_REMAINS_OFF',case when not b then 'PASS' else 'FAIL' end,'automatic backup enabled='||b,null);
 b:=config.setting_is_true('security_restore_automation_enabled'); perform ops.add_part5_closeout_result(v_run,'AUTO_RESTORE_REMAINS_OFF',case when not b then 'PASS' else 'FAIL' end,'automatic restore enabled='||b,null);
 b:=config.setting_is_true('security_deployment_execution_enabled'); perform ops.add_part5_closeout_result(v_run,'DEPLOY_EXECUTION_REMAINS_OFF',case when not b then 'PASS' else 'FAIL' end,'deployment execution enabled='||b,null);

 select count(*) filter(where status='PASS'),count(*) filter(where status='FAIL'),count(*) filter(where status='NOT_READY') into vp,vf,vn from ops.part5_closeout_results where closeout_run_pk=v_run;
 overall:=case when vf>0 then 'FAIL' when vn>0 then 'NOT_READY' else 'PASS' end;
 update ops.part5_closeout_runs set status=overall,pass_count=vp,fail_count=vf,not_ready_count=vn,production_readiness=coalesce(prod_gate,'NOT_READY'),notes='Part 5 foundation closeout is separate from deployment readiness.' where closeout_run_pk=v_run;
 return v_run;
end $$;

create or replace view ops.part5_latest_closeout_v as
select r.* from ops.part5_closeout_runs r where r.evaluated_at=(select max(x.evaluated_at) from ops.part5_closeout_runs x);

create or replace view ops.production_security_blockers_v as
select g.gate_id,c.gate_name,g.status,g.observed,g.evidence_ref
from ops.security_gate_results g
join ops.security_gate_catalog c on c.gate_id=g.gate_id
join ops.security_gate_runs r on r.run_pk=g.run_pk
where r.run_pk=(select run_pk from ops.security_gate_runs where environment='PROD' and completed_at is not null order by completed_at desc limit 1)
  and g.status<>'PASS';

revoke all on function ops.add_part5_closeout_result(uuid,text,text,text,text),ops.evaluate_part5_closeout(text) from public,anon,authenticated;
grant execute on function ops.add_part5_closeout_result(uuid,text,text,text,text),ops.evaluate_part5_closeout(text) to service_role;
revoke all on ops.part5_latest_closeout_v,ops.production_security_blockers_v from public,anon,authenticated;
grant select on ops.part5_latest_closeout_v,ops.production_security_blockers_v to service_role;