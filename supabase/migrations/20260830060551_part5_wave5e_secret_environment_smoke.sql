do $$
declare v_status text; v_blocked boolean:=false; v_bad_meta boolean:=false; v_test uuid; v_prod uuid; v_scan uuid;
begin
 select separation_status into v_status from ops.credential_separation_v where system_name='Supabase';
 if v_status<>'NOT_READY' then raise exception 'EXPECTED_CURRENT_CREDENTIAL_NOT_READY'; end if;
 if not exists(select 1 from ops.secret_scan_readiness_v where scope_type='PROMPT_HISTORY' and readiness_status='FAIL') then raise exception 'KNOWN_PROMPT_EXPOSURE_NOT_VISIBLE'; end if;
 if not exists(select 1 from ops.secret_scan_readiness_v where scope_type='GITHUB_REPOSITORY' and readiness_status='NOT_READY') then raise exception 'GITHUB_PARTIAL_NOT_VISIBLE'; end if;

 begin
   perform ops.register_credential_binding('SMOKE-CRED-PRE','Supabase','PROD',null,'smoke','SUPABASE_SECRET_STORE','smoke-pre','smoke','VERIFIED','smoke','{}'::jsonb);
 exception when others then
   if sqlerrm like '%ENVIRONMENT_NOT_VERIFIED%' then v_blocked:=true; else raise; end if;
 end;
 if not v_blocked then raise exception 'UNVERIFIED_PROD_ENV_NOT_BLOCKED'; end if;

 v_scan:=ops.register_secret_scan_run('part5e-smoke-meta','TEST','OTHER','synthetic','SMOKE','SMOKE','synthetic');
 begin
   perform ops.record_secret_scan_finding(v_scan,'POTENTIAL_SECRET','SEV2','SMOKE','synthetic','synthetic','OPEN',null,jsonb_build_object('api_key','redacted-placeholder'));
 exception when others then
   if sqlerrm like '%SECRET_MATERIAL_NOT_ALLOWED%' then v_bad_meta:=true; else raise; end if;
 end;
 if not v_bad_meta then raise exception 'SECRET_METADATA_NOT_BLOCKED'; end if;
 perform ops.finalize_secret_scan_run(v_scan,0,1,true,'smoke','no secret stored');

 update ops.security_environments set lifecycle_status='ACTIVE',verified=true,verified_at=clock_timestamp(),evidence_ref='SMOKE',updated_at=clock_timestamp() where environment='PROD';
 v_test:=ops.register_credential_binding('SMOKE-CRED-TEST','Supabase','TEST',null,'smoke','SUPABASE_SECRET_STORE','smoke-test-ref','test scope','VERIFIED','SMOKE','{}'::jsonb);
 v_prod:=ops.register_credential_binding('SMOKE-CRED-PROD','Supabase','PROD',null,'smoke','SUPABASE_SECRET_STORE','smoke-prod-ref','prod scope','VERIFIED','SMOKE','{}'::jsonb);
 select separation_status into v_status from ops.credential_separation_v where system_name='Supabase';
 if v_status<>'PASS' then raise exception 'DISTINCT_CREDENTIALS_DID_NOT_PASS'; end if;

 update ops.credential_bindings set store_reference='smoke-test-ref',updated_at=clock_timestamp() where binding_pk=v_prod;
 select separation_status into v_status from ops.credential_separation_v where system_name='Supabase';
 if v_status<>'FAIL' then raise exception 'REUSED_STORE_REFERENCE_NOT_DETECTED'; end if;
 update ops.credential_bindings set store_reference='smoke-prod-ref',updated_at=clock_timestamp() where binding_pk=v_prod;

 perform ops.record_credential_rotation('SMOKE-CRED-TEST','Supabase','TEST','EXPOSURE_DECLARED','SMOKE','synthetic exposure','SMOKE','{}'::jsonb);
 if not exists(select 1 from ops.rotation_readiness_v where credential_ref='SMOKE-CRED-TEST' and rotation_status='ROTATION_REQUIRED') then raise exception 'ROTATION_REQUIRED_NOT_DETECTED'; end if;
 perform pg_sleep(0.02);
 perform ops.record_credential_rotation('SMOKE-CRED-TEST','Supabase','TEST','ROTATED','SMOKE','synthetic rotation','SMOKE','{}'::jsonb);
 if not exists(select 1 from ops.rotation_readiness_v where credential_ref='SMOKE-CRED-TEST' and rotation_status='REMEDIATED') then raise exception 'ROTATION_REMEDIATION_NOT_DETECTED'; end if;

 delete from ops.credential_rotation_events where credential_ref like 'SMOKE-CRED-%';
 delete from ops.credential_bindings where credential_ref like 'SMOKE-CRED-%';
 delete from ops.secret_scan_findings where scan_run_pk=v_scan;
 delete from ops.secret_scan_runs where scan_run_pk=v_scan;
 update ops.security_environments set lifecycle_status='NOT_CREATED',verified=false,verified_at=null,evidence_ref=null,updated_at=clock_timestamp() where environment='PROD';

 if exists(select 1 from ops.credential_bindings where credential_ref like 'SMOKE-CRED-%') then raise exception 'SMOKE_CREDENTIAL_RESIDUE'; end if;
 if exists(select 1 from ops.secret_scan_runs where scan_key='part5e-smoke-meta') then raise exception 'SMOKE_SCAN_RESIDUE'; end if;
end $$;