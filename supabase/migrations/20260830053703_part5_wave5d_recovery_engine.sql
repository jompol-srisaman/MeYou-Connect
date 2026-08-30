create or replace view ops.backup_freshness_v as
with latest as (
  select distinct on (policy_key) policy_key, backup_run_pk, completed_at, source_snapshot_at, independent_copy, result, verification_status, target_provider, target_location_ref
  from ops.backup_runs
  where completed_at is not null and result in ('PASS','PASS_WITH_ISSUES') and verification_status in ('PASS','PASS_WITH_ISSUES')
  order by policy_key, completed_at desc
)
select p.policy_key,p.environment,p.asset_scope,p.tier,p.rpo_minutes,p.rto_minutes,p.restore_test_interval_days,p.independent_copy_required,
       l.backup_run_pk,l.completed_at,l.source_snapshot_at,l.independent_copy,l.target_provider,l.target_location_ref,
       case when l.completed_at is null then null else floor(extract(epoch from (now()-coalesce(l.source_snapshot_at,l.completed_at)))/60)::int end as backup_age_minutes,
       case
         when l.completed_at is null then 'NO_BACKUP'
         when p.rpo_minutes is not null and now()-coalesce(l.source_snapshot_at,l.completed_at) > make_interval(mins=>p.rpo_minutes) then 'STALE'
         when p.independent_copy_required and not l.independent_copy then 'FRESH_ROLLBACK_ONLY'
         else 'FRESH_INDEPENDENT'
       end as freshness_status
from ops.backup_policy_catalog p
left join latest l on l.policy_key=p.policy_key
where p.active;

create or replace view ops.restore_readiness_v as
with latest as (
 select distinct on (coalesce(br.policy_key,'EXTERNAL:'||r.external_backup_run_ref),r.environment)
        coalesce(br.policy_key,'EXTERNAL:'||r.external_backup_run_ref) as policy_key,r.*
 from ops.restore_test_runs r
 left join ops.backup_runs br on br.backup_run_pk=r.backup_run_pk
 where r.completed_at is not null
 order by coalesce(br.policy_key,'EXTERNAL:'||r.external_backup_run_ref),r.environment,r.completed_at desc
)
select l.*,
 case when l.result='PASS' and l.reconciliation_status='PASS'
           and coalesce(l.stable_ids_ok,false)
           and coalesce(l.candidate_sample_ok,false)
           and coalesce(l.placement_sample_ok,false)
           and coalesce(l.finance_evidence_sample_ok,false)
           and coalesce(l.canonical_doc_sample_ok,false)
      then 'RESTORE_VERIFIED'
      when l.result='FAIL' or l.reconciliation_status='FAIL' then 'RESTORE_FAILED'
      else 'PARTIAL_OR_NOT_VERIFIED' end as restore_acceptance_status
from latest l;

create or replace view ops.recovery_readiness_v as
select p.environment,
 count(*) filter(where p.tier='A')::int as active_tier_a_policies,
 count(*) filter(where p.tier='A' and f.freshness_status in ('FRESH_ROLLBACK_ONLY','FRESH_INDEPENDENT'))::int as fresh_backup_policies,
 count(*) filter(where p.tier='A' and f.freshness_status='FRESH_INDEPENDENT')::int as fresh_independent_policies,
 count(*) filter(where p.tier='A' and exists (
   select 1 from ops.restore_readiness_v r where r.environment=p.environment and r.policy_key=p.policy_key and r.restore_acceptance_status='RESTORE_VERIFIED'
   and (p.restore_test_interval_days is null or r.completed_at >= now()-make_interval(days=>p.restore_test_interval_days))
 ))::int as restore_verified_policies,
 count(*) filter(where p.tier='A' and f.freshness_status in ('NO_BACKUP','STALE','FRESH_ROLLBACK_ONLY'))::int as stale_or_missing_policies,
 case when count(*) filter(where p.tier='A')=0 then 'NOT_READY'
      when count(*) filter(where p.tier='A' and f.freshness_status='FRESH_INDEPENDENT') < count(*) filter(where p.tier='A') then 'NOT_READY'
      else 'PASS' end as backup_status
from ops.backup_policy_catalog p
join ops.backup_freshness_v f on f.policy_key=p.policy_key
where p.active
group by p.environment;

create or replace function ops.register_backup_run(p_policy_key text,p_started_at timestamptz,p_source_snapshot_at timestamptz,p_target_provider text,p_target_location_ref text,p_backup_layer smallint,p_independent_copy boolean,p_expected_assets integer,p_performed_by text,p_external_run_ref text default null,p_source_ref text default null,p_metadata jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_policy ops.backup_policy_catalog; v_pk uuid;
begin
 select * into v_policy from ops.backup_policy_catalog where policy_key=p_policy_key and active=true;
 if not found then raise exception 'BACKUP_POLICY_NOT_FOUND'; end if;
 if p_backup_layer not between 1 and 3 then raise exception 'INVALID_BACKUP_LAYER'; end if;
 if p_expected_assets<0 then raise exception 'INVALID_EXPECTED_ASSETS'; end if;
 insert into ops.backup_runs(policy_key,environment,external_run_ref,started_at,source_snapshot_at,target_provider,target_location_ref,backup_layer,independent_copy,expected_assets,performed_by,source_ref,metadata)
 values(p_policy_key,v_policy.environment,p_external_run_ref,coalesce(p_started_at,now()),p_source_snapshot_at,p_target_provider,p_target_location_ref,p_backup_layer,p_independent_copy,p_expected_assets,p_performed_by,p_source_ref,coalesce(p_metadata,'{}'::jsonb)) returning backup_run_pk into v_pk;
 return v_pk;
end $$;

create or replace function ops.register_backup_artifact(p_backup_run_pk uuid,p_asset_key text,p_provider text,p_storage_class text,p_location_ref text,p_checksum_sha256 text default null,p_size_bytes bigint default null,p_encrypted boolean default null,p_immutable_snapshot boolean default false,p_source_modified_at timestamptz default null,p_metadata jsonb default '{}'::jsonb)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_pk uuid;
begin
 if not exists(select 1 from ops.backup_runs where backup_run_pk=p_backup_run_pk and result='IN_PROGRESS') then raise exception 'BACKUP_RUN_NOT_OPEN'; end if;
 insert into ops.backup_artifacts(backup_run_pk,asset_key,provider,storage_class,location_ref,checksum_sha256,size_bytes,encrypted,immutable_snapshot,source_modified_at,metadata)
 values(p_backup_run_pk,p_asset_key,p_provider,p_storage_class,p_location_ref,p_checksum_sha256,p_size_bytes,p_encrypted,p_immutable_snapshot,p_source_modified_at,coalesce(p_metadata,'{}'::jsonb)) returning artifact_pk into v_pk;
 return v_pk;
end $$;

create or replace function ops.finalize_backup_run(p_backup_run_pk uuid,p_result text,p_completed_assets integer,p_failed_assets integer,p_verification_status text,p_verification_summary text,p_manifest_checksum_sha256 text default null,p_bytes_total bigint default null,p_completed_at timestamptz default now())
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_run ops.backup_runs; v_artifacts int;
begin
 select * into v_run from ops.backup_runs where backup_run_pk=p_backup_run_pk for update;
 if not found then raise exception 'BACKUP_RUN_NOT_FOUND'; end if;
 if v_run.result<>'IN_PROGRESS' then raise exception 'BACKUP_RUN_ALREADY_FINAL'; end if;
 if p_result not in ('PASS','PASS_WITH_ISSUES','FAIL','CANCELLED') then raise exception 'INVALID_BACKUP_RESULT'; end if;
 if p_verification_status not in ('PASS','PASS_WITH_ISSUES','FAIL') then raise exception 'INVALID_VERIFICATION_STATUS'; end if;
 if p_completed_assets<0 or p_failed_assets<0 or p_completed_assets+p_failed_assets>v_run.expected_assets then raise exception 'INVALID_ASSET_COUNTS'; end if;
 select count(*) into v_artifacts from ops.backup_artifacts where backup_run_pk=p_backup_run_pk;
 if p_result='PASS' and (p_failed_assets<>0 or p_completed_assets<>v_run.expected_assets or v_artifacts<p_completed_assets or p_verification_status<>'PASS') then raise exception 'PASS_REQUIRES_COMPLETE_VERIFIED_ARTIFACTS'; end if;
 update ops.backup_runs set completed_at=coalesce(p_completed_at,now()),result=p_result,completed_assets=p_completed_assets,failed_assets=p_failed_assets,verification_status=p_verification_status,verification_summary=p_verification_summary,manifest_checksum_sha256=p_manifest_checksum_sha256,bytes_total=p_bytes_total,updated_at=now() where backup_run_pk=p_backup_run_pk returning * into v_run;
 return jsonb_build_object('backup_run_pk',v_run.backup_run_pk,'result',v_run.result,'independent_copy',v_run.independent_copy,'artifact_count',v_artifacts);
end $$;

create or replace function ops.record_restore_test(p_environment text,p_scenario text,p_restore_target text,p_started_at timestamptz,p_completed_at timestamptz,p_result text,p_reconciliation_status text,p_performed_by text,p_backup_run_pk uuid default null,p_external_backup_run_ref text default null,p_external_restore_test_ref text default null,p_rto_seconds integer default null,p_stable_ids_ok boolean default null,p_candidate_sample_ok boolean default null,p_placement_sample_ok boolean default null,p_finance_evidence_sample_ok boolean default null,p_canonical_doc_sample_ok boolean default null,p_row_counts_ok boolean default null,p_finance_balanced_ok boolean default null,p_evidence_links_ok boolean default null,p_source_ref text default null,p_evidence_ref text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_pk uuid;
begin
 if p_environment not in ('TEST','PROD','GOOGLE') then raise exception 'INVALID_ENVIRONMENT'; end if;
 if p_backup_run_pk is null and p_external_backup_run_ref is null then raise exception 'BACKUP_REFERENCE_REQUIRED'; end if;
 insert into ops.restore_test_runs(environment,backup_run_pk,external_backup_run_ref,external_restore_test_ref,scenario,restore_target,started_at,completed_at,result,reconciliation_status,rto_seconds,stable_ids_ok,candidate_sample_ok,placement_sample_ok,finance_evidence_sample_ok,canonical_doc_sample_ok,row_counts_ok,finance_balanced_ok,evidence_links_ok,source_ref,evidence_ref,performed_by,notes)
 values(p_environment,p_backup_run_pk,p_external_backup_run_ref,p_external_restore_test_ref,p_scenario,p_restore_target,p_started_at,p_completed_at,p_result,p_reconciliation_status,p_rto_seconds,p_stable_ids_ok,p_candidate_sample_ok,p_placement_sample_ok,p_finance_evidence_sample_ok,p_canonical_doc_sample_ok,p_row_counts_ok,p_finance_balanced_ok,p_evidence_links_ok,p_source_ref,p_evidence_ref,p_performed_by,p_notes) returning restore_test_pk into v_pk;
 return v_pk;
end $$;

create or replace function ops.capture_recovery_snapshot(p_environment text,p_now timestamptz default now()) returns uuid language plpgsql security definer set search_path='' as $$
declare v_pk uuid; v_rec record; v_oldest int; v_restore_age int;
begin
 if p_environment not in ('TEST','PROD','GOOGLE') then raise exception 'INVALID_ENVIRONMENT'; end if;
 select * into v_rec from ops.recovery_readiness_v where environment=p_environment;
 select max(backup_age_minutes) into v_oldest from ops.backup_freshness_v where environment=p_environment and tier='A';
 select floor(extract(epoch from (p_now-max(completed_at)))/86400)::int into v_restore_age from ops.restore_test_runs where environment=p_environment and completed_at is not null;
 insert into ops.recovery_monitor_snapshots(environment,captured_at,active_tier_a_policies,fresh_backup_policies,fresh_independent_policies,restore_verified_policies,stale_or_missing_policies,oldest_required_backup_age_minutes,latest_restore_age_days,overall_status,details)
 values(p_environment,p_now,coalesce(v_rec.active_tier_a_policies,0),coalesce(v_rec.fresh_backup_policies,0),coalesce(v_rec.fresh_independent_policies,0),coalesce(v_rec.restore_verified_policies,0),coalesce(v_rec.stale_or_missing_policies,0),v_oldest,v_restore_age,coalesce(v_rec.backup_status,'NOT_READY'),jsonb_build_object('monitor_only',true)) returning recovery_snapshot_pk into v_pk;
 return v_pk;
end $$;

revoke all on function ops.register_backup_run(text,timestamptz,timestamptz,text,text,smallint,boolean,integer,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function ops.register_backup_artifact(uuid,text,text,text,text,text,bigint,boolean,boolean,timestamptz,jsonb) from public,anon,authenticated;
revoke all on function ops.finalize_backup_run(uuid,text,integer,integer,text,text,text,bigint,timestamptz) from public,anon,authenticated;
revoke all on function ops.record_restore_test(text,text,text,timestamptz,timestamptz,text,text,text,uuid,text,text,integer,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,text,text) from public,anon,authenticated;
revoke all on function ops.capture_recovery_snapshot(text,timestamptz) from public,anon,authenticated;
grant execute on function ops.register_backup_run(text,timestamptz,timestamptz,text,text,smallint,boolean,integer,text,text,text,jsonb) to service_role;
grant execute on function ops.register_backup_artifact(uuid,text,text,text,text,text,bigint,boolean,boolean,timestamptz,jsonb) to service_role;
grant execute on function ops.finalize_backup_run(uuid,text,integer,integer,text,text,text,bigint,timestamptz) to service_role;
grant execute on function ops.record_restore_test(text,text,text,timestamptz,timestamptz,text,text,text,uuid,text,text,integer,boolean,boolean,boolean,boolean,boolean,boolean,boolean,boolean,text,text,text) to service_role;
grant execute on function ops.capture_recovery_snapshot(text,timestamptz) to service_role;