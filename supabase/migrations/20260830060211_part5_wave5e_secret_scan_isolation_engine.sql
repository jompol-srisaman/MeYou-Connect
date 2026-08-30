create or replace function ops.register_secret_scan_run(
  p_scan_key text,p_environment text,p_scope_type text,p_scope_ref text,p_scan_method text,p_recorded_by text,p_notes text default null
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_pk uuid;
begin
 if p_scan_key is null or btrim(p_scan_key)='' then raise exception 'SCAN_KEY_REQUIRED'; end if;
 if p_environment not in ('TEST','PROD','SHARED') then raise exception 'INVALID_ENVIRONMENT'; end if;
 if p_scope_type not in ('GITHUB_REPOSITORY','GOOGLE_DRIVE','FRONTEND_BUILD','PROMPT_HISTORY','DATABASE_METADATA','OTHER') then raise exception 'INVALID_SCOPE_TYPE'; end if;
 if p_scope_ref is null or btrim(p_scope_ref)='' then raise exception 'SCOPE_REF_REQUIRED'; end if;
 if p_recorded_by is null or btrim(p_recorded_by)='' then raise exception 'RECORDED_BY_REQUIRED'; end if;
 insert into ops.secret_scan_runs(scan_key,environment,scope_type,scope_ref,scan_method,recorded_by,notes)
 values(p_scan_key,p_environment,p_scope_type,p_scope_ref,p_scan_method,p_recorded_by,p_notes)
 returning scan_run_pk into v_pk;
 return v_pk;
end $$;

create or replace function ops.record_secret_scan_finding(
 p_scan_run_pk uuid,p_finding_class text,p_severity text,p_detector text,p_location_ref text,p_summary text,
 p_remediation_status text default 'OPEN',p_evidence_ref text default null,p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_pk uuid; v_result text;
begin
 select result into v_result from ops.secret_scan_runs where scan_run_pk=p_scan_run_pk for update;
 if not found then raise exception 'SCAN_RUN_NOT_FOUND'; end if;
 if v_result<>'RUNNING' then raise exception 'SCAN_RUN_NOT_RUNNING'; end if;
 if p_finding_class not in ('ACTIVE_SECRET','POTENTIAL_SECRET','KNOWN_EXPOSURE','REFERENCE_ONLY','SECRET_NAME_ONLY') then raise exception 'INVALID_FINDING_CLASS'; end if;
 if p_severity not in ('SEV0','SEV1','SEV2','SEV3') then raise exception 'INVALID_SEVERITY'; end if;
 if p_remediation_status not in ('OPEN','REVIEWED','FALSE_POSITIVE','ROTATION_REQUIRED','REMEDIATED') then raise exception 'INVALID_REMEDIATION_STATUS'; end if;
 if coalesce(p_metadata,'{}'::jsonb) ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key'] then raise exception 'SECRET_MATERIAL_NOT_ALLOWED'; end if;
 insert into ops.secret_scan_findings(scan_run_pk,finding_class,severity,detector,location_ref,remediation_status,evidence_ref,summary,metadata)
 values(p_scan_run_pk,p_finding_class,p_severity,p_detector,p_location_ref,p_remediation_status,p_evidence_ref,p_summary,coalesce(p_metadata,'{}'::jsonb))
 returning finding_pk into v_pk;
 return v_pk;
end $$;

create or replace function ops.finalize_secret_scan_run(
 p_scan_run_pk uuid,p_objects_scanned integer,p_detector_count integer,p_coverage_complete boolean,p_evidence_ref text default null,p_notes text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare v_active int;v_potential int;v_ref int;v_total int;v_unresolved int;v_result text;
begin
 if p_objects_scanned<0 or p_detector_count<0 then raise exception 'INVALID_SCAN_COUNTS'; end if;
 perform 1 from ops.secret_scan_runs where scan_run_pk=p_scan_run_pk and result='RUNNING' for update;
 if not found then raise exception 'SCAN_RUN_NOT_RUNNING'; end if;
 select count(*),
   count(*) filter(where finding_class='ACTIVE_SECRET'),
   count(*) filter(where finding_class='POTENTIAL_SECRET'),
   count(*) filter(where finding_class in ('REFERENCE_ONLY','SECRET_NAME_ONLY')),
   count(*) filter(where finding_class in ('ACTIVE_SECRET','POTENTIAL_SECRET','KNOWN_EXPOSURE') and remediation_status not in ('FALSE_POSITIVE','REMEDIATED'))
 into v_total,v_active,v_potential,v_ref,v_unresolved
 from ops.secret_scan_findings where scan_run_pk=p_scan_run_pk;
 v_result:=case when v_unresolved>0 then 'FAIL' when not p_coverage_complete then 'PARTIAL' else 'PASS' end;
 update ops.secret_scan_runs set completed_at=now(),objects_scanned=p_objects_scanned,detector_count=p_detector_count,
 findings_total=v_total,active_secret_hits=v_active,potential_hits=v_potential,reference_only_hits=v_ref,
 coverage_complete=p_coverage_complete,result=v_result,evidence_ref=p_evidence_ref,notes=coalesce(p_notes,notes)
 where scan_run_pk=p_scan_run_pk;
 return jsonb_build_object('scan_run_pk',p_scan_run_pk,'result',v_result,'findings_total',v_total,'unresolved_sensitive_findings',v_unresolved,'coverage_complete',p_coverage_complete);
end $$;

create or replace function ops.register_credential_binding(
 p_credential_ref text,p_system_name text,p_environment text,p_secret_inventory_ref text,p_purpose text,
 p_secret_store_type text,p_store_reference text,p_scope_summary text,p_status text,p_evidence_ref text default null,p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_pk uuid;
begin
 if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
 if p_status not in ('NOT_CREATED','REGISTERED','VERIFIED','REVOKED') then raise exception 'INVALID_BINDING_STATUS'; end if;
 if p_secret_store_type not in ('ENVIRONMENT_SECRET_STORE','SUPABASE_SECRET_STORE','CI_CD_SECRET_STORE','N8N_CREDENTIALS','PROVIDER_SECRET_STORE','NOT_CREATED') then raise exception 'INVALID_SECRET_STORE_TYPE'; end if;
 if coalesce(p_metadata,'{}'::jsonb) ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key'] then raise exception 'SECRET_MATERIAL_NOT_ALLOWED'; end if;
 insert into ops.credential_bindings(credential_ref,system_name,environment,secret_inventory_ref,purpose,secret_store_type,store_reference,scope_summary,status,last_reviewed_at,evidence_ref,metadata)
 values(p_credential_ref,p_system_name,p_environment,p_secret_inventory_ref,p_purpose,p_secret_store_type,p_store_reference,p_scope_summary,p_status,case when p_status='VERIFIED' then now() end,p_evidence_ref,coalesce(p_metadata,'{}'::jsonb))
 returning binding_pk into v_pk;
 return v_pk;
end $$;

create or replace view ops.credential_separation_v as
with req as (
 select * from ops.credential_requirements where active and required_in_test and required_in_prod
), b as (
 select system_name,
  max(credential_ref) filter(where environment='TEST' and status='VERIFIED') as test_credential_ref,
  max(secret_inventory_ref) filter(where environment='TEST' and status='VERIFIED') as test_secret_inventory_ref,
  max(store_reference) filter(where environment='TEST' and status='VERIFIED') as test_store_reference,
  max(credential_ref) filter(where environment='PROD' and status='VERIFIED') as prod_credential_ref,
  max(secret_inventory_ref) filter(where environment='PROD' and status='VERIFIED') as prod_secret_inventory_ref,
  max(store_reference) filter(where environment='PROD' and status='VERIFIED') as prod_store_reference
 from ops.credential_bindings group by system_name
)
select r.system_name,r.scope_expectation,
 b.test_credential_ref,b.prod_credential_ref,
 case
  when b.test_credential_ref is null or b.prod_credential_ref is null then 'NOT_READY'
  when b.test_credential_ref=b.prod_credential_ref then 'FAIL'
  when b.test_secret_inventory_ref is not null and b.test_secret_inventory_ref=b.prod_secret_inventory_ref then 'FAIL'
  when b.test_store_reference is not null and b.test_store_reference=b.prod_store_reference then 'FAIL'
  else 'PASS'
 end as separation_status
from req r left join b using(system_name);

create or replace view ops.secret_scan_readiness_v as
with scopes(scope_type,required_now) as (values
 ('GITHUB_REPOSITORY'::text,true),('GOOGLE_DRIVE'::text,true),('PROMPT_HISTORY'::text,true),('FRONTEND_BUILD'::text,false)
), latest as (
 select distinct on (scope_type) scope_type,scan_key,result,coverage_complete,completed_at,evidence_ref
 from ops.secret_scan_runs where environment in ('TEST','SHARED') and completed_at is not null
 order by scope_type,completed_at desc
)
select s.scope_type,s.required_now,l.scan_key,l.result,l.coverage_complete,l.completed_at,l.evidence_ref,
 case when not s.required_now then 'NOT_REQUIRED'
      when l.scan_key is null then 'NOT_READY'
      when l.result='PASS' and l.coverage_complete then 'PASS'
      when l.result='FAIL' then 'FAIL'
      else 'NOT_READY' end as readiness_status
from scopes s left join latest l using(scope_type);

create or replace function ops.part5e_readiness()
returns jsonb language sql security definer set search_path=''
as $$
 select jsonb_build_object(
  'required_scan_pass',coalesce((select bool_and(readiness_status='PASS') from ops.secret_scan_readiness_v where required_now),false),
  'scan_fail_count',(select count(*) from ops.secret_scan_readiness_v where required_now and readiness_status='FAIL'),
  'credential_separation_pass',coalesce((select bool_and(separation_status='PASS') from ops.credential_separation_v),false),
  'credential_not_ready_count',(select count(*) from ops.credential_separation_v where separation_status='NOT_READY'),
  'credential_fail_count',(select count(*) from ops.credential_separation_v where separation_status='FAIL'),
  'prod_environment_verified',coalesce((select verified from ops.security_environments where environment='PROD'),false),
  'production_cutover_approved',config.setting_is_true('production_cutover_approved')
 )
$$;

revoke all on function ops.register_secret_scan_run(text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function ops.record_secret_scan_finding(uuid,text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function ops.finalize_secret_scan_run(uuid,integer,integer,boolean,text,text) from public,anon,authenticated;
revoke all on function ops.register_credential_binding(text,text,text,text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function ops.part5e_readiness() from public,anon,authenticated;
grant execute on function ops.register_secret_scan_run(text,text,text,text,text,text,text) to service_role;
grant execute on function ops.record_secret_scan_finding(uuid,text,text,text,text,text,text,text,jsonb) to service_role;
grant execute on function ops.finalize_secret_scan_run(uuid,integer,integer,boolean,text,text) to service_role;
grant execute on function ops.register_credential_binding(text,text,text,text,text,text,text,text,text,text,jsonb) to service_role;
grant execute on function ops.part5e_readiness() to service_role;
revoke all on ops.credential_separation_v,ops.secret_scan_readiness_v from public,anon,authenticated;
grant select on ops.credential_separation_v,ops.secret_scan_readiness_v to service_role;