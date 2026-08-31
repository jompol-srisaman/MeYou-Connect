create or replace view analytics.part6a_status_v as
select
  (select count(*) from analytics.kpi_catalog where active) as kpi_catalog_count,
  (select count(*) from analytics.semantic_rules) as semantic_rule_count,
  (select count(*) from analytics.dq_gate_catalog) as dq_gate_count,
  (select count(*) from analytics.acceptance_catalog) as acceptance_total,
  (select count(*) from analytics.acceptance_catalog where status='PASS') as acceptance_pass,
  (select count(*) from analytics.acceptance_catalog where status='NOT_RUN') as acceptance_not_run,
  (select count(*) from analytics.stage_transition_fact) as stage_transition_rows,
  (select count(*) from analytics.placement_milestone_fact) as placement_milestone_rows,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as postgres_publish_enabled,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_materialization_enabled'),false) as materialization_enabled,
  (select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source') as operational_source,
  'Asia/Bangkok'::text as reporting_timezone,
  'CLOSED'::text as foundation_status,
  'NOT_READY'::text as official_postgres_analytics_status;

revoke all on analytics.part6a_status_v from public,anon,authenticated;
grant select on analytics.part6a_status_v to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('analytics_foundation_ready','true'::jsonb,'Part 6A KPI semantic/readiness foundation is implemented in TEST.','Part6A'),
('part6a_foundation_closed','true'::jsonb,'Part 6A implementation foundation closed in TEST.','Part6A'),
('analytics_business_source_ready','false'::jsonb,'Official business analytics remains blocked until PostgreSQL becomes approved operational source.','Part6A'),
('analytics_postgres_publish_enabled','false'::jsonb,'Official PostgreSQL KPI publishing remains disabled.','Part6A'),
('analytics_materialization_enabled','false'::jsonb,'No materialized views before measured performance need.','Part6A')
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

update analytics.source_freshness
set readiness_status='NOT_READY',blocked_reason='PostgreSQL remains TEST/shadow and is not approved as operational Source of Truth.',updated_at=now()
where source_key='POSTGRES_OPERATIONAL_MASTER';