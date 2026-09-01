create or replace function api.analytics_kpi_result(p_kpi_id text)
returns table(
  kpi_id text,status text,as_of timestamptz,numerator numeric,denominator numeric,metric_value numeric,
  result_type text,blocked_reason text,source_object text
)
language plpgsql
security definer
set search_path=''
as $fn$
begin
  perform authz.require_capability('analytics_read');
  return query select * from analytics.evaluate_kpi_v3(p_kpi_id,now(),false);
end
$fn$;
revoke all on function api.analytics_kpi_result(text) from public,anon;
grant execute on function api.analytics_kpi_result(text) to authenticated,service_role;

create or replace function api.analytics_dashboard_contract(p_page_key text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_page analytics.dashboard_pages%rowtype;
  v_kpis jsonb;
begin
  select * into v_page from analytics.dashboard_pages where page_key=upper(trim(p_page_key)) and active;
  if not found then raise exception 'UNKNOWN_DASHBOARD_PAGE'; end if;
  perform authz.require_capability(v_page.required_capability);
  select coalesce(jsonb_agg(jsonb_build_object(
    'kpi_id',m.kpi_id,'kpi_name',k.kpi_name,'display_order',m.display_order,'section',m.section_name,
    'primary_metric',m.primary_metric,'kpi_class',k.kpi_class,'result_type',k.result_type,'not_ready_rule',k.not_ready_rule
  ) order by m.display_order),'[]'::jsonb)
  into v_kpis
  from analytics.dashboard_kpi_map m join analytics.kpi_catalog k on k.kpi_id=m.kpi_id
  where m.page_key=v_page.page_key;
  return jsonb_build_object(
    'page_key',v_page.page_key,'page_name',v_page.page_name,'audience',v_page.audience,
    'top_row',v_page.top_row,'sections',v_page.sections,'default_filters',v_page.default_filters,
    'drillthrough',v_page.drillthrough_contract,'freshness',v_page.freshness_contract,'rule',v_page.page_rule,
    'performance_target_ms',v_page.performance_target_ms,'kpis',v_kpis
  );
end
$fn$;

create or replace function api.analytics_dashboard(p_page_key text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_page analytics.dashboard_pages%rowtype;
  v_publish boolean;
  v_payload jsonb;
  v_readiness jsonb;
begin
  select * into v_page from analytics.dashboard_pages where page_key=upper(trim(p_page_key)) and active;
  if not found then raise exception 'UNKNOWN_DASHBOARD_PAGE'; end if;
  perform authz.require_capability(v_page.required_capability);
  select coalesce((setting_value #>> '{}')::boolean,false) into v_publish from config.system_settings where setting_key='analytics_postgres_publish_enabled';
  select coalesce(jsonb_agg(jsonb_build_object('source_key',source_key,'status',readiness_status,'blocked_reason',blocked_reason,'last_refresh_at',last_refresh_at)),'[]'::jsonb)
  into v_readiness from analytics.source_readiness_v;

  if not coalesce(v_publish,false) then
    return jsonb_build_object(
      'page_key',v_page.page_key,'page_name',v_page.page_name,'status','NOT_READY','as_of',now(),
      'blocked_reason','POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE',
      'freshness',v_readiness,'data',null
    );
  end if;

  case v_page.page_key
    when 'FOUNDER_DAILY' then select to_jsonb(v) into v_payload from analytics.founder_daily_v v;
    when 'FOUNDER_WEEKLY' then select to_jsonb(v) into v_payload from analytics.founder_weekly_v v;
    when 'FOUNDER_MONTHLY' then select to_jsonb(v) into v_payload from analytics.founder_monthly_v v;
    when 'CANDIDATE_OPS' then select to_jsonb(v) into v_payload from analytics.candidate_ops_dashboard_v v;
    when 'CLIENT_SALES' then select to_jsonb(v) into v_payload from analytics.client_sales_dashboard_v v;
    when 'FINANCE' then select to_jsonb(v) into v_payload from analytics.finance_dashboard_v v;
    when 'PARTNER_REVIEW' then select coalesce(jsonb_agg(to_jsonb(v) order by v.partner_id),'[]'::jsonb) into v_payload from analytics.partner_performance_v v;
    when 'DATA_QUALITY' then select to_jsonb(v) into v_payload from analytics.data_quality_dashboard_v v;
    else raise exception 'DASHBOARD_SURFACE_NOT_IMPLEMENTED';
  end case;

  return jsonb_build_object(
    'page_key',v_page.page_key,'page_name',v_page.page_name,'status','READY','as_of',now(),
    'blocked_reason',null,'freshness',v_readiness,'data',v_payload
  );
end
$fn$;

revoke all on function api.analytics_dashboard_contract(text) from public,anon;
revoke all on function api.analytics_dashboard(text) from public,anon;
grant execute on function api.analytics_dashboard_contract(text),api.analytics_dashboard(text) to authenticated,service_role;