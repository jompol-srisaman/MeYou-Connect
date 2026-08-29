create or replace function ops.record_part4_evidence(
  p_evidence_key text,
  p_status text,
  p_evidence_ref text,
  p_details jsonb,
  p_recorded_by text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  if p_evidence_key is null or btrim(p_evidence_key)='' then raise exception 'evidence_key required'; end if;
  if p_status not in ('PASS','FAIL','NOT_READY','INFO') then raise exception 'invalid evidence status'; end if;
  if p_recorded_by is null or btrim(p_recorded_by)='' then raise exception 'recorded_by required'; end if;

  insert into ops.part4_evidence_records(evidence_key,evidence_status,evidence_ref,details,recorded_by,recorded_at)
  values(p_evidence_key,p_status,p_evidence_ref,coalesce(p_details,'{}'::jsonb),p_recorded_by,now())
  on conflict(evidence_key) do update set
    evidence_status=excluded.evidence_status,
    evidence_ref=excluded.evidence_ref,
    details=excluded.details,
    recorded_by=excluded.recorded_by,
    recorded_at=excluded.recorded_at;

  return jsonb_build_object('evidence_key',p_evidence_key,'status',p_status,'evidence_ref',p_evidence_ref);
end;
$$;

create or replace function ops.evaluate_part4_closeout(
  p_scope text,
  p_created_by text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  c record;
  v_run uuid;
  v_status text;
  v_evidence record;
  v_details jsonb;
  v_pass boolean;
  v_total int;
  v_pass_count int;
  v_fail_count int;
  v_not_ready_count int;
  v_final_status text;
  v_cnt int;
  v_cnt2 int;
begin
  if p_scope not in ('TEST_IMPLEMENTATION','PRODUCTION_READINESS') then raise exception 'invalid Part 4 closeout scope'; end if;
  if p_created_by is null or btrim(p_created_by)='' then raise exception 'created_by required'; end if;

  insert into ops.part4_closeout_runs(scope,status,created_by)
  values(p_scope,'NOT_READY',p_created_by)
  returning closeout_run_id into v_run;

  for c in
    select * from ops.part4_closeout_check_catalog where scope=p_scope order by check_order
  loop
    v_status:='NOT_READY';
    v_details:='{}'::jsonb;
    v_pass:=false;

    if c.check_mode='EVIDENCE' then
      select * into v_evidence from ops.part4_evidence_records where evidence_key=c.evidence_key;
      if found then
        v_status:=case when v_evidence.evidence_status='PASS' then 'PASS' when v_evidence.evidence_status='FAIL' then 'FAIL' else 'NOT_READY' end;
        v_details:=jsonb_build_object('evidence_status',v_evidence.evidence_status,'recorded_at',v_evidence.recorded_at,'details',v_evidence.details);
        insert into ops.part4_closeout_results(closeout_run_id,check_key,status,evidence_ref,details)
        values(v_run,c.check_key,v_status,v_evidence.evidence_ref,v_details);
      else
        insert into ops.part4_closeout_results(closeout_run_id,check_key,status,details)
        values(v_run,c.check_key,'NOT_READY',jsonb_build_object('reason','required evidence not recorded','evidence_key',c.evidence_key));
      end if;
      continue;
    end if;

    if c.check_key='T_SCHEMA_SET' then
      select count(*) into v_cnt from information_schema.schemata where schema_name in ('core','private','privacy','docs','ops','finance','authz','config','api');
      v_pass:=(v_cnt=9);
      v_details:=jsonb_build_object('schemas_found',v_cnt,'required',9);
    elsif c.check_key='T_PART4_MIGRATIONS' then
      select
        (case when exists(select 1 from supabase_migrations.schema_migrations where name like 'part4_wave4a%') then 1 else 0 end)+
        (case when exists(select 1 from supabase_migrations.schema_migrations where name like 'part4_wave4b%') then 1 else 0 end)+
        (case when exists(select 1 from supabase_migrations.schema_migrations where name like 'part4_wave4c%') then 1 else 0 end)+
        (case when exists(select 1 from supabase_migrations.schema_migrations where name like 'part4_wave4d%') then 1 else 0 end)+
        (case when exists(select 1 from supabase_migrations.schema_migrations where name like 'part4_wave4e%') then 1 else 0 end)+
        (case when exists(select 1 from supabase_migrations.schema_migrations where name like 'part4_wave4f%') then 1 else 0 end)+
        (case when exists(select 1 from supabase_migrations.schema_migrations where name like 'part4_wave4g%') then 1 else 0 end)
      into v_cnt;
      v_pass:=(v_cnt=7);
      v_details:=jsonb_build_object('waves_present',v_cnt,'required',7);
    elsif c.check_key='T_CANONICAL_MYC_IDS' then
      select count(*) into v_cnt from config.system_settings where setting_key='canonical_business_id_namespace' and setting_value=to_jsonb('MYC'::text);
      v_pass:=(v_cnt=1);
      v_details:=jsonb_build_object('canonical_namespace','MYC','matched',v_pass);
    elsif c.check_key='T_SOURCE_OF_TRUTH_UNCHANGED' then
      select count(*) into v_cnt from config.system_settings where setting_key='current_operational_source' and setting_value=to_jsonb('GOOGLE_SHEETS_DRIVE'::text);
      v_pass:=(v_cnt=1);
      v_details:=jsonb_build_object('expected','GOOGLE_SHEETS_DRIVE','matched',v_pass);
    elsif c.check_key='T_SAFETY_GATES_OFF' then
      select count(*), count(*) filter(where setting_value='false'::jsonb)
      into v_cnt,v_cnt2
      from config.system_settings
      where setting_key in ('business_master_apply_enabled','migration_target_apply_enabled','migration_cutover_enabled','production_cutover_approved','external_channel_webhooks_enabled','finance_external_payment_execution_enabled');
      v_pass:=(v_cnt=6 and v_cnt2=6);
      v_details:=jsonb_build_object('gates_found',v_cnt,'gates_false',v_cnt2,'required',6);
    elsif c.check_key='T_STORAGE_PRIVATE' then
      select count(*), count(*) filter(where public=false)
      into v_cnt,v_cnt2
      from storage.buckets
      where id in ('raw-inbox-private','evidence-private','business-private','content-public');
      v_pass:=(v_cnt=4 and v_cnt2=4);
      v_details:=jsonb_build_object('expected_buckets',4,'found',v_cnt,'private',v_cnt2);
    elsif c.check_key='T_PART3_INTEGRATION' then
      select count(*) into v_cnt from ops.routing_rules where active=true;
      select count(*) into v_cnt2 from ops.worker_registry where enabled=true;
      v_pass:=(v_cnt>=20 and v_cnt2>=20 and (select count(*) from ops.domain_worker_contracts where active=true)>=8 and (select count(*) from ops.master_apply_contracts where active=true)>=8);
      v_details:=jsonb_build_object('routing_rules',v_cnt,'workers',v_cnt2,'domain_contracts',(select count(*) from ops.domain_worker_contracts where active=true),'apply_contracts',(select count(*) from ops.master_apply_contracts where active=true));
    elsif c.check_key='T_RLS_ENABLED' then
      select count(*) into v_cnt
      from pg_class pc join pg_namespace pn on pn.oid=pc.relnamespace
      where pn.nspname in ('core','private','privacy','docs','finance','authz') and pc.relkind='r';
      select count(*) into v_cnt2
      from pg_class pc join pg_namespace pn on pn.oid=pc.relnamespace
      where pn.nspname in ('core','private','privacy','docs','finance','authz') and pc.relkind='r' and not pc.relrowsecurity;
      v_pass:=(v_cnt>0 and v_cnt2=0);
      v_details:=jsonb_build_object('base_tables',v_cnt,'without_rls',v_cnt2);
    elsif c.check_key='T_REQUIRED_OUTPUT_CATALOG' then
      select count(*) into v_cnt from ops.part4_output_catalog where required_for_test=true;
      v_pass:=(v_cnt>=10);
      v_details:=jsonb_build_object('required_outputs_cataloged',v_cnt,'minimum',10);
    elsif c.check_key='P_FOUNDER_APPROVAL' then
      select count(*) into v_cnt from config.system_settings where setting_key='production_cutover_approved' and setting_value='true'::jsonb;
      v_pass:=(v_cnt=1);
      if v_pass then v_status:='PASS'; else v_status:='NOT_READY'; end if;
      v_details:=jsonb_build_object('production_cutover_approved',v_pass);
      insert into ops.part4_closeout_results(closeout_run_id,check_key,status,details) values(v_run,c.check_key,v_status,v_details);
      continue;
    elsif c.check_key='P_CUTOVER_REHEARSAL' then
      select count(*) into v_cnt from ops.cutover_readiness_v where critical_not_pass=0 and freeze_acknowledged=true and final_backup_recorded=true;
      v_pass:=(v_cnt>0);
      if v_pass then v_status:='PASS'; else v_status:='NOT_READY'; end if;
      v_details:=jsonb_build_object('persisted_ready_rehearsals',v_cnt);
      insert into ops.part4_closeout_results(closeout_run_id,check_key,status,details) values(v_run,c.check_key,v_status,v_details);
      continue;
    else
      v_status:='NOT_READY';
      v_details:=jsonb_build_object('reason','auto evaluator not implemented for check');
      insert into ops.part4_closeout_results(closeout_run_id,check_key,status,details) values(v_run,c.check_key,v_status,v_details);
      continue;
    end if;

    v_status:=case when v_pass then 'PASS' else 'FAIL' end;
    insert into ops.part4_closeout_results(closeout_run_id,check_key,status,details)
    values(v_run,c.check_key,v_status,v_details);
  end loop;

  select count(*),count(*) filter(where status='PASS'),count(*) filter(where status='FAIL'),count(*) filter(where status='NOT_READY')
  into v_total,v_pass_count,v_fail_count,v_not_ready_count
  from ops.part4_closeout_results where closeout_run_id=v_run;

  v_final_status:=case when v_fail_count>0 then 'FAIL' when v_not_ready_count>0 then 'NOT_READY' else 'PASS' end;

  update ops.part4_closeout_runs set
    status=v_final_status,total_checks=v_total,passed_checks=v_pass_count,failed_checks=v_fail_count,not_ready_checks=v_not_ready_count
  where closeout_run_id=v_run;

  if p_scope='TEST_IMPLEMENTATION' then
    update config.system_settings set setting_value=to_jsonb(v_final_status='PASS'),updated_at=now(),source_ref='Part4H evaluator' where setting_key='part4_test_implementation_closed';
  else
    update config.system_settings set setting_value=to_jsonb(v_final_status),updated_at=now(),source_ref='Part4H evaluator' where setting_key='part4_production_readiness_status';
  end if;

  return jsonb_build_object('closeout_run_id',v_run,'scope',p_scope,'status',v_final_status,'total',v_total,'pass',v_pass_count,'fail',v_fail_count,'not_ready',v_not_ready_count);
end;
$$;

create or replace view ops.part4_latest_closeout_v as
select distinct on (r.scope)
  r.closeout_run_id,r.scope,r.status,r.total_checks,r.passed_checks,r.failed_checks,r.not_ready_checks,r.created_by,r.notes,r.created_at
from ops.part4_closeout_runs r
order by r.scope,r.created_at desc,r.closeout_run_id desc;

create or replace function api.part4_closeout_status(p_scope text default null)
returns table(scope text,status text,total_checks integer,passed_checks integer,failed_checks integer,not_ready_checks integer,created_at timestamptz)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('migration_reconcile_read');
  return query
  select v.scope,v.status,v.total_checks,v.passed_checks,v.failed_checks,v.not_ready_checks,v.created_at
  from ops.part4_latest_closeout_v v
  where p_scope is null or v.scope=p_scope
  order by v.scope;
end;
$$;

create or replace function api.part4_closeout_issues(p_scope text)
returns table(check_key text,status text,description text,evidence_ref text,details jsonb)
language plpgsql
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('migration_reconcile_read');
  return query
  select res.check_key,res.status,cat.description,res.evidence_ref,res.details
  from ops.part4_latest_closeout_v latest
  join ops.part4_closeout_results res on res.closeout_run_id=latest.closeout_run_id
  join ops.part4_closeout_check_catalog cat on cat.check_key=res.check_key
  where latest.scope=p_scope and res.status<>'PASS'
  order by cat.check_order;
end;
$$;

revoke execute on function ops.record_part4_evidence(text,text,text,jsonb,text) from public,anon,authenticated;
revoke execute on function ops.evaluate_part4_closeout(text,text) from public,anon,authenticated;
grant execute on function ops.record_part4_evidence(text,text,text,jsonb,text) to service_role;
grant execute on function ops.evaluate_part4_closeout(text,text) to service_role;

revoke execute on function api.part4_closeout_status(text) from public,anon;
revoke execute on function api.part4_closeout_issues(text) from public,anon;
grant execute on function api.part4_closeout_status(text) to authenticated;
grant execute on function api.part4_closeout_issues(text) to authenticated;
