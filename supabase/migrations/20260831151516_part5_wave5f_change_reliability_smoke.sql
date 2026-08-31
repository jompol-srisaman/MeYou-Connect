do $$
declare
 c1 uuid; c2 uuid; c3 uuid; r uuid; s text;
begin
 insert into ops.change_requests(change_key,environment,title,risk_key,change_scope,source_control_ref,requested_by)
 values('SMOKE-5F-STANDARD','TEST','Standard TEST change','STANDARD','Synthetic acceptance','github:test-standard','PART5F_SMOKE') returning change_pk into c1;
 r:=ops.evaluate_change_readiness(c1,'PART5F_SMOKE');
 select status into s from ops.change_readiness_runs where readiness_run_pk=r;
 if s<>'NOT_READY' then raise exception 'STANDARD_MISSING_EVIDENCE_SHOULD_NOT_READY'; end if;
 insert into ops.change_evidence(change_pk,evidence_type,status,evidence_ref,summary,recorded_by) values
 (c1,'TEST_PASS','PASS','smoke:test','TEST passed','PART5F_SMOKE'),
 (c1,'SECURITY_REVIEW','PASS','smoke:security','Security review passed','PART5F_SMOKE'),
 (c1,'ROLLBACK_PLAN','PASS','smoke:rollback','Rollback plan present','PART5F_SMOKE');
 r:=ops.evaluate_change_readiness(c1,'PART5F_SMOKE'); select status into s from ops.change_readiness_runs where readiness_run_pk=r;
 if s<>'PASS' then raise exception 'STANDARD_COMPLETE_EVIDENCE_SHOULD_PASS'; end if;
 if (select status from ops.change_requests where change_pk=c1)<>'READY' then raise exception 'STANDARD_CHANGE_NOT_READY'; end if;

 insert into ops.change_requests(change_key,environment,title,risk_key,change_scope,source_control_ref,requested_by,architect_review_status)
 values('SMOKE-5F-RLS','TEST','High risk RLS change','RLS_PERMISSION','Synthetic RLS acceptance','github:test-rls','PART5F_SMOKE','PENDING') returning change_pk into c2;
 insert into ops.change_evidence(change_pk,evidence_type,status,evidence_ref,summary,recorded_by) values
 (c2,'TEST_PASS','PASS','smoke:test','TEST passed','PART5F_SMOKE'),
 (c2,'SECURITY_REVIEW','PASS','smoke:security','Security review passed','PART5F_SMOKE'),
 (c2,'ROLLBACK_PLAN','PASS','smoke:rollback','Rollback plan present','PART5F_SMOKE');
 r:=ops.evaluate_change_readiness(c2,'PART5F_SMOKE'); select status into s from ops.change_readiness_runs where readiness_run_pk=r;
 if s<>'NOT_READY' then raise exception 'HIGH_RISK_INCOMPLETE_SHOULD_NOT_READY'; end if;
 update ops.change_requests set architect_review_status='APPROVED' where change_pk=c2;
 insert into ops.change_evidence(change_pk,evidence_type,status,evidence_ref,summary,recorded_by) values
 (c2,'RLS_ALLOW','PASS','smoke:rls-allow','RLS ALLOW passed','PART5F_SMOKE'),
 (c2,'RLS_DENY','PASS','smoke:rls-deny','RLS DENY passed','PART5F_SMOKE'),
 (c2,'FRESH_BACKUP','PASS','smoke:backup','Fresh backup evidence present','PART5F_SMOKE'),
 (c2,'DEPLOY_IDENTITY','PASS','smoke:deploy-id','Controlled deploy identity verified','PART5F_SMOKE');
 r:=ops.evaluate_change_readiness(c2,'PART5F_SMOKE'); select status into s from ops.change_readiness_runs where readiness_run_pk=r;
 if s<>'PASS' then raise exception 'HIGH_RISK_COMPLETE_SHOULD_PASS'; end if;

 insert into ops.change_requests(change_key,environment,title,risk_key,change_scope,source_control_ref,requested_by,architect_review_status,founder_approval_status)
 values('SMOKE-5F-PROD','PROD','Critical production auth change','AUTH_CONFIGURATION','Synthetic production gate test','github:test-prod','PART5F_SMOKE','APPROVED','APPROVED') returning change_pk into c3;
 insert into ops.change_evidence(change_pk,evidence_type,status,evidence_ref,summary,recorded_by) values
 (c3,'TEST_PASS','PASS','smoke:test','TEST passed','PART5F_SMOKE'),
 (c3,'RLS_ALLOW','PASS','smoke:rls-allow','RLS ALLOW passed','PART5F_SMOKE'),
 (c3,'RLS_DENY','PASS','smoke:rls-deny','RLS DENY passed','PART5F_SMOKE'),
 (c3,'SECURITY_REVIEW','PASS','smoke:security','Security review passed','PART5F_SMOKE'),
 (c3,'ROLLBACK_PLAN','PASS','smoke:rollback','Rollback plan present','PART5F_SMOKE'),
 (c3,'FRESH_BACKUP','PASS','smoke:backup','Fresh backup evidence present','PART5F_SMOKE'),
 (c3,'DEPLOY_IDENTITY','PASS','smoke:deploy-id','Controlled deploy identity verified','PART5F_SMOKE');
 r:=ops.evaluate_change_readiness(c3,'PART5F_SMOKE'); select status into s from ops.change_readiness_runs where readiness_run_pk=r;
 if s<>'NOT_READY' then raise exception 'PROD_MUST_REMAIN_NOT_READY'; end if;
 if not exists(select 1 from ops.change_readiness_results where readiness_run_pk=r and check_key='PROD_ENVIRONMENT_VERIFIED' and status='NOT_READY') then raise exception 'PROD_ENVIRONMENT_GATE_NOT_ENFORCED'; end if;
 if not exists(select 1 from ops.change_readiness_results where readiness_run_pk=r and check_key='GLOBAL_PROD_SECURITY_GATE' and status='NOT_READY') then raise exception 'GLOBAL_PROD_GATE_NOT_ENFORCED'; end if;

 delete from ops.change_readiness_results where readiness_run_pk in (select readiness_run_pk from ops.change_readiness_runs where change_pk in (c1,c2,c3));
 delete from ops.change_readiness_runs where change_pk in (c1,c2,c3);
 delete from ops.change_evidence where change_pk in (c1,c2,c3);
 delete from ops.change_requests where change_pk in (c1,c2,c3);
end $$;