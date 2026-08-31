do $policies$
declare
  t text;
begin
  foreach t in array array['kpi_catalog','semantic_rules','dq_gate_catalog','acceptance_catalog','dim_date','stage_transition_fact','placement_milestone_fact','source_freshness']
  loop
    execute format('drop policy if exists %I on analytics.%I','deny_client_'||t,t);
    execute format('create policy %I on analytics.%I as restrictive for all to anon,authenticated using (false) with check (false)','deny_client_'||t,t);
  end loop;
end
$policies$;

create or replace function api.analytics_foundation_status()
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_publish boolean;
  v_materialize boolean;
begin
  perform authz.require_capability('analytics_read');
  select coalesce((setting_value #>> '{}')::boolean,false) into v_publish from config.system_settings where setting_key='analytics_postgres_publish_enabled';
  select coalesce((setting_value #>> '{}')::boolean,false) into v_materialize from config.system_settings where setting_key='analytics_materialization_enabled';
  return jsonb_build_object(
    'kpi_catalog_count',(select count(*) from analytics.kpi_catalog where active),
    'semantic_rule_count',(select count(*) from analytics.semantic_rules),
    'dq_gate_count',(select count(*) from analytics.dq_gate_catalog),
    'acceptance_test_count',(select count(*) from analytics.acceptance_catalog),
    'stage_transition_rows',(select count(*) from analytics.stage_transition_fact),
    'placement_milestone_rows',(select count(*) from analytics.placement_milestone_fact),
    'postgres_publish_enabled',coalesce(v_publish,false),
    'materialization_enabled',coalesce(v_materialize,false),
    'business_reporting_timezone','Asia/Bangkok',
    'official_source_status',case when coalesce(v_publish,false) then 'READY' else 'NOT_READY' end,
    'operational_source',(select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source')
  );
end
$function$;

create or replace function api.analytics_kpi_catalog()
returns table(
  kpi_id text,domain text,kpi_name text,kpi_class text,definition text,time_grain text,result_type text,
  not_ready_rule text,owner_role text,dashboard text,priority text
)
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform authz.require_capability('analytics_read');
  return query
  select k.kpi_id,k.domain,k.kpi_name,k.kpi_class,k.definition,k.time_grain,k.result_type,k.not_ready_rule,k.owner_role,k.dashboard,k.priority
  from analytics.kpi_catalog k where k.active order by k.priority,k.kpi_id;
end
$function$;

create or replace function api.analytics_kpi_result(p_kpi_id text)
returns table(
  kpi_id text,status text,as_of timestamptz,numerator numeric,denominator numeric,metric_value numeric,
  result_type text,blocked_reason text,source_object text
)
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform authz.require_capability('analytics_read');
  return query select * from analytics.evaluate_kpi(p_kpi_id,now(),false);
end
$function$;

create or replace function api.analytics_source_readiness()
returns table(
  source_key text,source_type text,last_source_at timestamptz,last_refresh_at timestamptz,
  freshness_window_minutes integer,readiness_status text,blocked_reason text,source_ref text
)
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform authz.require_capability('analytics_read');
  return query
  select v.source_key,v.source_type,v.last_source_at,v.last_refresh_at,v.freshness_window_minutes,v.readiness_status,v.blocked_reason,v.source_ref
  from analytics.source_readiness_v v order by v.source_key;
end
$function$;

create or replace function api.analytics_acceptance_status()
returns table(test_id text,scenario text,expected_behavior text,critical boolean,status text,evidence_ref text,last_tested_at timestamptz)
language plpgsql
security definer
set search_path=''
as $function$
begin
  perform authz.require_capability('analytics_read');
  return query select a.test_id,a.scenario,a.expected_behavior,a.critical,a.status,a.evidence_ref,a.last_tested_at
  from analytics.acceptance_catalog a order by a.test_id;
end
$function$;

revoke all on function api.analytics_foundation_status() from public,anon;
revoke all on function api.analytics_kpi_catalog() from public,anon;
revoke all on function api.analytics_kpi_result(text) from public,anon;
revoke all on function api.analytics_source_readiness() from public,anon;
revoke all on function api.analytics_acceptance_status() from public,anon;
grant execute on function api.analytics_foundation_status() to authenticated,service_role;
grant execute on function api.analytics_kpi_catalog() to authenticated,service_role;
grant execute on function api.analytics_kpi_result(text) to authenticated,service_role;
grant execute on function api.analytics_source_readiness() to authenticated,service_role;
grant execute on function api.analytics_acceptance_status() to authenticated,service_role;