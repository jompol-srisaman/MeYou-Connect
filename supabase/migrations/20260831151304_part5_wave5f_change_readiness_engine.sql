create or replace function ops.latest_change_evidence_status(p_change_pk uuid,p_type text)
returns table(status text,evidence_ref text,summary text)
language sql security definer set search_path=''
as $$
 select e.status,e.evidence_ref,e.summary
 from ops.change_evidence e
 where e.change_pk=p_change_pk and e.evidence_type=p_type
   and (e.expires_at is null or e.expires_at>now())
 order by e.observed_at desc,e.created_at desc limit 1
$$;

create or replace function ops.add_change_readiness_result(p_run uuid,p_key text,p_required boolean,p_status text,p_observed text,p_ref text default null)
returns void language sql security definer set search_path=''
as $$
 insert into ops.change_readiness_results(readiness_run_pk,check_key,status,required,observed,evidence_ref)
 values(p_run,p_key,p_status,p_required,p_observed,p_ref)
$$;

create or replace function ops.evaluate_change_readiness(p_change_pk uuid,p_actor text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare
 c ops.change_requests; r ops.change_risk_catalog; v_run uuid;
 s text; er text; sm text; vp int; vf int; vn int; overall text;
 global_gate text; prod_verified boolean;
begin
 if p_actor is null or btrim(p_actor)='' then raise exception 'ACTOR_REQUIRED'; end if;
 select * into c from ops.change_requests where change_pk=p_change_pk for update;
 if not found then raise exception 'CHANGE_NOT_FOUND'; end if;
 select * into r from ops.change_risk_catalog where risk_key=c.risk_key;
 insert into ops.change_readiness_runs(change_pk,evaluated_by,status) values(c.change_pk,p_actor,'NOT_READY') returning readiness_run_pk into v_run;

 if c.source_control_ref is not null and btrim(c.source_control_ref)<>'' then
   perform ops.add_change_readiness_result(v_run,'SOURCE_CONTROL',true,'PASS','Source-control reference recorded',c.source_control_ref);
 else
   select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'SOURCE_CONTROL');
   perform ops.add_change_readiness_result(v_run,'SOURCE_CONTROL',true,coalesce(s,'NOT_READY'),coalesce(sm,'Source-control evidence missing'),er);
 end if;

 if r.requires_test_pass then select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'TEST_PASS'); perform ops.add_change_readiness_result(v_run,'TEST_PASS',true,coalesce(s,'NOT_READY'),coalesce(sm,'TEST pass evidence missing'),er); end if;
 if r.requires_rls_tests then
   select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'RLS_ALLOW'); perform ops.add_change_readiness_result(v_run,'RLS_ALLOW',true,coalesce(s,'NOT_READY'),coalesce(sm,'RLS ALLOW evidence missing'),er);
   select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'RLS_DENY'); perform ops.add_change_readiness_result(v_run,'RLS_DENY',true,coalesce(s,'NOT_READY'),coalesce(sm,'RLS DENY evidence missing'),er);
 end if;
 if r.requires_security_review then select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'SECURITY_REVIEW'); perform ops.add_change_readiness_result(v_run,'SECURITY_REVIEW',true,coalesce(s,'NOT_READY'),coalesce(sm,'Security review evidence missing'),er); end if;
 if r.requires_rollback_plan then select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'ROLLBACK_PLAN'); perform ops.add_change_readiness_result(v_run,'ROLLBACK_PLAN',true,coalesce(s,'NOT_READY'),coalesce(sm,'Rollback plan evidence missing'),er); end if;
 if r.requires_fresh_backup then select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'FRESH_BACKUP'); perform ops.add_change_readiness_result(v_run,'FRESH_BACKUP',true,coalesce(s,'NOT_READY'),coalesce(sm,'Fresh backup evidence missing'),er); end if;
 if r.requires_controlled_deploy_identity then select * into s,er,sm from ops.latest_change_evidence_status(c.change_pk,'DEPLOY_IDENTITY'); perform ops.add_change_readiness_result(v_run,'DEPLOY_IDENTITY',true,coalesce(s,'NOT_READY'),coalesce(sm,'Controlled deploy identity evidence missing'),er); end if;
 if r.architect_review_required then perform ops.add_change_readiness_result(v_run,'ARCHITECT_REVIEW',true,case c.architect_review_status when 'APPROVED' then 'PASS' when 'REJECTED' then 'FAIL' else 'NOT_READY' end,'Architect review status='||c.architect_review_status,null); end if;
 if r.founder_approval_required then perform ops.add_change_readiness_result(v_run,'FOUNDER_APPROVAL',true,case c.founder_approval_status when 'APPROVED' then 'PASS' when 'REJECTED' then 'FAIL' else 'NOT_READY' end,'Founder approval status='||c.founder_approval_status,null); end if;

 if c.environment='PROD' then
   select status into global_gate from ops.security_gate_runs where environment='PROD' and completed_at is not null order by completed_at desc limit 1;
   select verified into prod_verified from ops.security_environments where environment='PROD';
   perform ops.add_change_readiness_result(v_run,'GLOBAL_PROD_SECURITY_GATE',true,case when global_gate='PASS' then 'PASS' when global_gate='FAIL' then 'FAIL' else 'NOT_READY' end,'Latest PROD security gate='||coalesce(global_gate,'NONE'),null);
   perform ops.add_change_readiness_result(v_run,'PROD_ENVIRONMENT_VERIFIED',true,case when coalesce(prod_verified,false) then 'PASS' else 'NOT_READY' end,'Production environment verified='||coalesce(prod_verified,false),null);
 end if;

 select count(*) filter(where status='PASS'),count(*) filter(where status='FAIL'),count(*) filter(where status='NOT_READY') into vp,vf,vn from ops.change_readiness_results where readiness_run_pk=v_run and required=true;
 overall:=case when vf>0 then 'FAIL' when vn>0 then 'NOT_READY' else 'PASS' end;
 update ops.change_readiness_runs set status=overall,pass_count=vp,fail_count=vf,not_ready_count=vn where readiness_run_pk=v_run;
 update ops.change_requests set status=case when overall='PASS' then 'READY' when overall='FAIL' then 'BLOCKED' else 'UNDER_REVIEW' end,updated_at=now() where change_pk=c.change_pk and status not in ('DEPLOYED','CANCELLED');
 return v_run;
end $$;

revoke all on function ops.latest_change_evidence_status(uuid,text),ops.add_change_readiness_result(uuid,text,boolean,text,text,text),ops.evaluate_change_readiness(uuid,text) from public,anon,authenticated;
grant execute on function ops.latest_change_evidence_status(uuid,text),ops.add_change_readiness_result(uuid,text,boolean,text,text,text),ops.evaluate_change_readiness(uuid,text) to service_role;