do $close$
declare
  v_total integer;
  v_pass integer;
  v_recommend boolean;
begin
  select count(*),count(*) filter(where status='PASS') into v_total,v_pass from analytics.acceptance_catalog;
  if v_total<>12 or v_pass<>12 then raise exception 'PART6_ACCEPTANCE_NOT_COMPLETE:%/%',v_pass,v_total; end if;
  if exists(select 1 from analytics.materialization_decisions where surface_key in ('FOUNDER_DAILY','FOUNDER_WEEKLY','FOUNDER_MONTHLY') and decision<>'KEEP_NORMAL_VIEW') then
    v_recommend:=true;
  else
    v_recommend:=false;
  end if;
  if to_regclass('analytics.founder_weekly_mv') is not null or to_regclass('analytics.monthly_review_mv') is not null then
    raise exception 'UNAPPROVED_MATERIALIZED_VIEW_PRESENT';
  end if;

  insert into config.system_settings(setting_key,setting_value,description,source_ref) values
  ('analytics_dashboard_surfaces_ready','true'::jsonb,'Part 6C Founder/role dashboard semantic surfaces implemented and role-gated in TEST.','Part6C'),
  ('analytics_query_benchmark_ready','true'::jsonb,'Part 6C measured dashboard query benchmark completed in TEST.','Part6C'),
  ('analytics_materialization_recommended',to_jsonb(v_recommend),'Measured materialization recommendation only; does not enable materialization.','Part6C'),
  ('part6c_foundation_closed','true'::jsonb,'Part 6C implementation foundation closed in TEST.','Part6C'),
  ('part6_foundation_closed','true'::jsonb,'Part 6 semantic/dashboard implementation foundation closed in TEST with 12/12 canonical acceptance PASS.','Part6C')
  on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();
end
$close$;

create or replace view analytics.part6c_status_v as
select
  (select count(*) from analytics.dashboard_pages where active) as dashboard_page_count,
  (select count(*) from analytics.dashboard_kpi_map) as dashboard_kpi_mapping_count,
  (select count(*) from analytics.acceptance_catalog) as acceptance_total,
  (select count(*) from analytics.acceptance_catalog where status='PASS') as acceptance_pass,
  (select count(*) from analytics.query_benchmark_samples where source_state='ACTUAL_TEST_BENCHMARK' and measured_by='PART6C_ACTUAL') as actual_benchmark_samples,
  (select max(p95_ms) from analytics.materialization_decisions where surface_key in ('FOUNDER_DAILY','FOUNDER_WEEKLY','FOUNDER_MONTHLY')) as founder_max_p95_ms,
  (select bool_and(decision='KEEP_NORMAL_VIEW') from analytics.materialization_decisions where surface_key in ('FOUNDER_DAILY','FOUNDER_WEEKLY','FOUNDER_MONTHLY')) as founder_keep_normal_views,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as postgres_publish_enabled,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_materialization_enabled'),false) as materialization_enabled,
  (select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source') as operational_source,
  'CLOSED'::text as part6_foundation_status,
  'NOT_READY'::text as official_postgres_analytics_status;
revoke all on analytics.part6c_status_v from public,anon,authenticated;
grant select on analytics.part6c_status_v to service_role;

create or replace function api.analytics_part6_status()
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare v jsonb;
begin
  perform authz.require_capability('analytics_read');
  select to_jsonb(s) into v from analytics.part6c_status_v s;
  return v;
end
$fn$;
revoke all on function api.analytics_part6_status() from public,anon;
grant execute on function api.analytics_part6_status() to authenticated,service_role;