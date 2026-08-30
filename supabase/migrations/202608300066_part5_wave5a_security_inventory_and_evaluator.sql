alter table ops.security_evidence_records
  drop constraint if exists security_evidence_no_secret_material,
  add constraint security_evidence_no_secret_material check (
    not (details ?| array['password','password_value','secret','secret_value','service_role_key','api_key','access_token','refresh_token'])
  );

alter table ops.security_events
  drop constraint if exists security_events_no_secret_material,
  add constraint security_events_no_secret_material check (
    not (metadata ?| array['password','password_value','secret','secret_value','service_role_key','api_key','access_token','refresh_token'])
  );

create or replace view ops.api_surface_inventory_v as
select
  'ROUTINE'::text as object_type,
  r.routine_name as object_name,
  r.routine_type as object_subtype,
  r.data_type as return_type,
  null::boolean as rls_enabled
from information_schema.routines r
where r.routine_schema='api'
union all
select
  t.table_type::text as object_type,
  t.table_name as object_name,
  t.table_type::text as object_subtype,
  null::text as return_type,
  c.relrowsecurity as rls_enabled
from information_schema.tables t
join pg_namespace n on n.nspname=t.table_schema
join pg_class c on c.relnamespace=n.oid and c.relname=t.table_name
where t.table_schema='api';

create or replace view ops.security_definer_inventory_v as
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as identity_arguments,
  pg_get_userbyid(p.proowner) as owner_name,
  p.prosecdef as security_definer,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_execute,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as authenticated_execute,
  has_function_privilege('service_role',p.oid,'EXECUTE') as service_role_execute
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where p.prosecdef
  and n.nspname not in ('pg_catalog','information_schema')
order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);

create or replace view ops.rls_inventory_v as
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled,
  c.relforcerowsecurity as force_rls,
  count(pol.policyname)::integer as policy_count
from pg_class c
join pg_namespace n on n.oid=c.relnamespace
left join pg_policies pol on pol.schemaname=n.nspname and pol.tablename=c.relname
where c.relkind='r'
  and n.nspname in ('core','private','privacy','docs','finance','authz','ops')
group by n.nspname,c.relname,c.relrowsecurity,c.relforcerowsecurity
order by n.nspname,c.relname;

create or replace view ops.storage_security_v as
select
  b.id as bucket_id,
  b.name as bucket_name,
  b.public,
  case
    when b.id in ('raw-inbox-private','evidence-private','business-private','backup-private') then 'PRIVATE_REQUIRED'
    when b.id='content-public' then 'PUBLIC_SAFE_ONLY'
    else 'REVIEW_REQUIRED'
  end as expected_class,
  case
    when b.id in ('raw-inbox-private','evidence-private','business-private','backup-private') and b.public then 'VIOLATION'
    when b.id='content-public' and b.public then 'PUBLIC_ENABLED'
    when b.id='content-public' and not b.public then 'SAFE_LOCKED'
    else 'PASS'
  end as security_status
from storage.buckets b
order by b.id;

create or replace view ops.security_latest_gate_v as
with latest as (
  select distinct on (environment) run_pk,environment,status,started_at,completed_at,evaluated_by,pass_count,fail_count,not_ready_count
  from ops.security_gate_runs
  where status<>'RUNNING'
  order by environment,started_at desc,run_pk desc
)
select l.environment,l.run_pk,l.status as overall_status,l.started_at,l.completed_at,l.evaluated_by,l.pass_count,l.fail_count,l.not_ready_count,
       r.gate_id,c.gate_name,r.status,r.expected,r.observed,r.evidence_ref,r.notes
from latest l
join ops.security_gate_results r on r.run_pk=l.run_pk
join ops.security_gate_catalog c on c.gate_id=r.gate_id;

create or replace function ops.record_security_evidence(
  p_evidence_key text,
  p_environment text,
  p_evidence_type text,
  p_status text,
  p_source_type text,
  p_source_ref text,
  p_summary text,
  p_recorded_by text,
  p_control_id text default null,
  p_gate_id text default null,
  p_details jsonb default '{}'::jsonb,
  p_observed_at timestamptz default now(),
  p_expires_at timestamptz default null
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_pk uuid;
begin
  if p_environment not in ('TEST','PROD','GOOGLE','SHARED') then raise exception 'INVALID_ENVIRONMENT'; end if;
  if p_status not in ('PASS','FAIL','NOT_READY','INFO') then raise exception 'INVALID_STATUS'; end if;
  if p_evidence_key is null or btrim(p_evidence_key)='' then raise exception 'EVIDENCE_KEY_REQUIRED'; end if;
  if p_summary is null or btrim(p_summary)='' then raise exception 'SUMMARY_REQUIRED'; end if;
  insert into ops.security_evidence_records(evidence_key,environment,control_id,gate_id,evidence_type,status,source_type,source_ref,summary,details,observed_at,expires_at,recorded_by)
  values(p_evidence_key,p_environment,p_control_id,p_gate_id,p_evidence_type,p_status,p_source_type,p_source_ref,p_summary,coalesce(p_details,'{}'::jsonb),coalesce(p_observed_at,now()),p_expires_at,p_recorded_by)
  returning evidence_pk into v_pk;
  return v_pk;
end $$;

create or replace function ops.record_security_event(
  p_environment text,
  p_severity text,
  p_event_type text,
  p_summary text,
  p_actor_ref text default null,
  p_service_ref text default null,
  p_entity_type text default null,
  p_entity_id text default null,
  p_trace_id text default null,
  p_event_id text default null,
  p_result text default null,
  p_evidence_ref text default null,
  p_metadata jsonb default '{}'::jsonb,
  p_status text default 'OPEN'
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare v_pk uuid;
begin
  insert into ops.security_events(environment,severity,event_type,actor_ref,service_ref,entity_type,entity_id,trace_id,event_id,result,summary,evidence_ref,metadata,status)
  values(p_environment,p_severity,p_event_type,p_actor_ref,p_service_ref,p_entity_type,p_entity_id,p_trace_id,p_event_id,p_result,p_summary,p_evidence_ref,coalesce(p_metadata,'{}'::jsonb),p_status)
  returning security_event_pk into v_pk;
  return v_pk;
end $$;

create or replace function ops.evaluate_security_gates(
  p_environment text,
  p_actor text
) returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_run uuid;
  g record;
  v_status text;
  v_observed text;
  v_evidence text;
  v_notes text;
  v_pass integer;
  v_fail integer;
  v_not_ready integer;
  v_overall text;
  v_count integer;
begin
  if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
  if p_actor is null or btrim(p_actor)='' then raise exception 'ACTOR_REQUIRED'; end if;

  insert into ops.security_gate_runs(environment,evaluated_by) values(p_environment,p_actor) returning run_pk into v_run;

  for g in select * from ops.security_gate_catalog order by gate_id loop
    v_status := null; v_observed := null; v_evidence := null; v_notes := null;

    if g.gate_id in ('PG-001','PG-002','PG-003','PG-004','PG-005','PG-006','PG-009','PG-010','PG-012','PG-013','PG-015') then
      select e.status,e.source_ref,e.summary
      into v_status,v_evidence,v_notes
      from ops.security_evidence_records e
      where e.evidence_key = case g.gate_id
        when 'PG-001' then 'rls_allow_tests'
        when 'PG-002' then 'rls_deny_tests'
        when 'PG-003' then 'api_inventory_review'
        when 'PG-004' then 'secret_scan_review'
        when 'PG-005' then 'credential_separation'
        when 'PG-006' then 'webhook_signature_replay'
        when 'PG-009' then 'fresh_backup'
        when 'PG-010' then 'restore_test'
        when 'PG-012' then 'incident_runbook'
        when 'PG-013' then 'alert_routing_test'
        when 'PG-015' then 'production_approval'
      end
      and e.environment in (p_environment,'SHARED')
      and (e.expires_at is null or e.expires_at>now())
      order by case when e.environment=p_environment then 0 else 1 end,e.observed_at desc
      limit 1;
      if v_status is null then v_status:='NOT_READY'; v_observed:='Required evidence not recorded';
      else v_observed:='Evidence status='||v_status; end if;

    elsif g.gate_id='PG-007' then
      select count(*) into v_count from supabase_migrations.schema_migrations where name='part3_wave3f_end_to_end_closeout_smoke';
      if v_count=1 then v_status:='PASS'; v_observed:='Part 3 end-to-end closeout smoke migration present'; v_evidence:='part3_wave3f_end_to_end_closeout_smoke';
      else v_status:='NOT_READY'; v_observed:='Part 3 closeout smoke not found'; end if;

    elsif g.gate_id='PG-008' then
      select count(*) into v_count from supabase_migrations.schema_migrations where name='part4_wave4e_finance_accounting_smoke';
      if v_count=1 then v_status:='PASS'; v_observed:='Finance/accounting smoke migration present'; v_evidence:='part4_wave4e_finance_accounting_smoke';
      else v_status:='NOT_READY'; v_observed:='Finance smoke not found'; end if;

    elsif g.gate_id='PG-011' then
      if p_environment='TEST' then
        select count(*) into v_count from storage.buckets where id in ('raw-inbox-private','evidence-private','business-private','backup-private') and public=true;
        if v_count>0 then v_status:='FAIL'; v_observed:=v_count||' required-private bucket(s) are public';
        else
          select count(*) into v_count from storage.buckets where id in ('raw-inbox-private','evidence-private','business-private','backup-private');
          if v_count=4 then v_status:='PASS'; v_observed:='All required TEST private buckets exist and are non-public';
          else v_status:='NOT_READY'; v_observed:='Missing required TEST private bucket(s)'; end if;
        end if;
      else
        select e.status,e.source_ref,e.summary into v_status,v_evidence,v_notes
        from ops.security_evidence_records e
        where e.evidence_key='private_storage_test' and e.environment in ('PROD','SHARED') and (e.expires_at is null or e.expires_at>now())
        order by case when e.environment='PROD' then 0 else 1 end,e.observed_at desc limit 1;
        if v_status is null then v_status:='NOT_READY'; v_observed:='Production storage exposure evidence not recorded'; else v_observed:='Evidence status='||v_status; end if;
      end if;

    elsif g.gate_id='PG-014' then
      if p_environment='TEST' then
        select count(*) into v_count from supabase_migrations.schema_migrations where name='part4_wave4g_cutover_rehearsal_smoke';
        if v_count=1 then v_status:='PASS'; v_observed:='Part 4G rollback/cutover rehearsal smoke migration present'; v_evidence:='part4_wave4g_cutover_rehearsal_smoke';
        else v_status:='NOT_READY'; v_observed:='TEST rollback rehearsal not found'; end if;
      else
        select e.status,e.source_ref,e.summary into v_status,v_evidence,v_notes
        from ops.security_evidence_records e
        where e.evidence_key='rollback_drill' and e.environment in ('PROD','SHARED') and (e.expires_at is null or e.expires_at>now())
        order by case when e.environment='PROD' then 0 else 1 end,e.observed_at desc limit 1;
        if v_status is null then v_status:='NOT_READY'; v_observed:='Production rollback drill evidence not recorded'; else v_observed:='Evidence status='||v_status; end if;
      end if;
    end if;

    if v_status='INFO' then v_status:='NOT_READY'; end if;
    insert into ops.security_gate_results(run_pk,gate_id,status,expected,observed,evidence_ref,notes)
    values(v_run,g.gate_id,v_status,g.evidence_required,v_observed,v_evidence,v_notes);
  end loop;

  select count(*) filter(where status='PASS'),count(*) filter(where status='FAIL'),count(*) filter(where status='NOT_READY')
  into v_pass,v_fail,v_not_ready from ops.security_gate_results where run_pk=v_run;
  v_overall:=case when v_fail>0 then 'FAIL' when v_not_ready>0 then 'NOT_READY' else 'PASS' end;
  update ops.security_gate_runs set status=v_overall,completed_at=now(),pass_count=v_pass,fail_count=v_fail,not_ready_count=v_not_ready where run_pk=v_run;
  return v_run;
end $$;

create or replace function ops.part5a_foundation_status() returns jsonb
language sql
security definer
set search_path=''
as $$
select jsonb_build_object(
  'foundation_ready',
    (select count(*)=16 from ops.security_control_catalog)
    and (select count(*)=15 from ops.security_gate_catalog)
    and to_regclass('ops.privileged_identity_registry') is not null
    and to_regclass('ops.secret_inventory') is not null
    and to_regclass('ops.security_events') is not null
    and to_regclass('ops.security_gate_runs') is not null
    and (select coalesce(setting_value,'false'::jsonb)='false'::jsonb from config.system_settings where setting_key='production_cutover_approved')
    and (select coalesce(setting_value,'false'::jsonb)='false'::jsonb from config.system_settings where setting_key='migration_cutover_enabled'),
  'real_auth_users',(select count(*) from auth.users),
  'registered_privileged_identities',(select count(*) from ops.privileged_identity_registry where status='ACTIVE'),
  'active_secret_inventory_items',(select count(*) from ops.secret_inventory where status='ACTIVE'),
  'private_bucket_violations',(select count(*) from storage.buckets where id in ('raw-inbox-private','evidence-private','business-private','backup-private') and public=true),
  'production_cutover_approved',(select setting_value from config.system_settings where setting_key='production_cutover_approved'),
  'current_operational_source',(select setting_value from config.system_settings where setting_key='current_operational_source'),
  'part4_test_implementation_closed',(select setting_value from config.system_settings where setting_key='part4_test_implementation_closed')
)
$$;

revoke all on function ops.record_security_evidence(text,text,text,text,text,text,text,text,text,text,jsonb,timestamptz,timestamptz) from public,anon,authenticated;
revoke all on function ops.record_security_event(text,text,text,text,text,text,text,text,text,text,text,text,jsonb,text) from public,anon,authenticated;
revoke all on function ops.evaluate_security_gates(text,text) from public,anon,authenticated;
revoke all on function ops.part5a_foundation_status() from public,anon,authenticated;
grant execute on function ops.record_security_evidence(text,text,text,text,text,text,text,text,text,text,jsonb,timestamptz,timestamptz) to service_role;
grant execute on function ops.record_security_event(text,text,text,text,text,text,text,text,text,text,text,text,jsonb,text) to service_role;
grant execute on function ops.evaluate_security_gates(text,text) to service_role;
grant execute on function ops.part5a_foundation_status() to service_role;