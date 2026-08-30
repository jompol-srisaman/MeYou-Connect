do $$
declare v_run uuid; v_restore uuid; v_status text; v_restore_status text; v_ready record; v_failed boolean:=false; v_bad uuid;
begin
 select freshness_status into v_status from ops.backup_freshness_v where policy_key='GOOGLE_TIER_A_STRUCTURED';
 if v_status not in ('FRESH_ROLLBACK_ONLY','STALE') then raise exception 'GOOGLE_SAME_ACCOUNT_CLASSIFICATION_FAILED:%',v_status; end if;
 select restore_acceptance_status into v_restore_status from ops.restore_readiness_v where environment='GOOGLE' and external_restore_test_ref='MYC-RT-000001';
 if v_restore_status<>'PARTIAL_OR_NOT_VERIFIED' then raise exception 'PARTIAL_RESTORE_CLASSIFICATION_FAILED:%',v_restore_status; end if;

 v_run:=ops.register_backup_run('TEST_DATABASE_CRITICAL'::text,now()-interval '2 minutes',now()-interval '2 minutes','TEST_INDEPENDENT_STORAGE'::text,'wave5d/synthetic/backup.sql'::text,3::smallint,true,1,'PART5D_SMOKE'::text,null::text,'part5_wave5d_backup_restore_smoke'::text,'{"synthetic":true}'::jsonb);
 perform ops.register_backup_artifact(v_run,'POSTGRESQL_LOGICAL_DUMP'::text,'TEST_INDEPENDENT_STORAGE'::text,'INDEPENDENT'::text,'wave5d/synthetic/backup.sql'::text,repeat('a',64),1024::bigint,true,true,now()-interval '2 minutes','{"synthetic":true}'::jsonb);
 perform ops.finalize_backup_run(v_run,'PASS'::text,1,0,'PASS'::text,'Synthetic independent artifact verified'::text,repeat('b',64),1024::bigint,now()-interval '1 minute');
 v_restore:=ops.record_restore_test('TEST'::text,'Synthetic isolated restore acceptance'::text,'ISOLATED_TEST_SCHEMA'::text,now()-interval '50 seconds',now()-interval '10 seconds','PASS'::text,'PASS'::text,'PART5D_SMOKE'::text,v_run,null::text,null::text,40,true,true,true,true,true,true,true,true,'part5_wave5d_backup_restore_smoke'::text,'synthetic-evidence'::text,'Synthetic acceptance only; cleaned before commit'::text);
 select * into v_ready from ops.recovery_readiness_v where environment='TEST';
 if v_ready.fresh_independent_policies<1 then raise exception 'INDEPENDENT_BACKUP_NOT_RECOGNIZED'; end if;
 if not exists(select 1 from ops.restore_readiness_v where restore_test_pk=v_restore and restore_acceptance_status='RESTORE_VERIFIED') then raise exception 'FULL_RESTORE_NOT_VERIFIED'; end if;

 begin
   v_bad:=ops.register_backup_run('TEST_DATABASE_CRITICAL'::text,now(),now(),'TEST_SANDBOX'::text,'invalid/pass'::text,3::smallint,true,1,'PART5D_SMOKE'::text,null::text,null::text,'{}'::jsonb);
   perform ops.finalize_backup_run(v_bad,'PASS'::text,1,0,'PASS'::text,'Should fail without artifact'::text,null::text,null::bigint,now());
 exception when others then v_failed:=true; end;
 if not v_failed then raise exception 'PASS_WITHOUT_ARTIFACT_WAS_ACCEPTED'; end if;

 delete from ops.restore_test_runs where restore_test_pk=v_restore;
 delete from ops.backup_artifacts where backup_run_pk=v_run;
 delete from ops.backup_runs where backup_run_pk=v_run;
 delete from ops.backup_runs where performed_by='PART5D_SMOKE';
end $$;