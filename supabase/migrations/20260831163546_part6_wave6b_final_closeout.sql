create or replace view analytics.part6b_status_v as
select
  (select count(*) from analytics.acceptance_catalog) as acceptance_total,
  (select count(*) from analytics.acceptance_catalog where status='PASS') as acceptance_pass,
  (select count(*) from analytics.acceptance_catalog where status='NOT_RUN') as acceptance_not_run,
  (select count(*) from analytics.appointment_outcome_fact) as appointment_fact_rows,
  (select count(*) from analytics.partner_attribution_fact) as attribution_fact_rows,
  (select count(*) from analytics.stage_transition_fact) as stage_transition_rows,
  (select count(*) from analytics.placement_milestone_fact) as milestone_fact_rows,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as postgres_publish_enabled,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_materialization_enabled'),false) as materialization_enabled,
  'CLOSED'::text as foundation_status,
  'NOT_READY'::text as official_postgres_analytics_status,
  'AN-011'::text as remaining_acceptance_test;

revoke all on analytics.part6b_status_v from public,anon,authenticated;
grant select on analytics.part6b_status_v to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('part6b_foundation_closed','true'::jsonb,'Part 6B historical funnel/appointment/retention/attribution normalization foundation closed in TEST.','Part6B'),
('analytics_core_acceptance_ready','true'::jsonb,'Core analytics semantic acceptance AN-001..010 and AN-012 passed; AN-011 performance/materialization remains pending.','Part6B'),
('analytics_postgres_publish_enabled','false'::jsonb,'Official PostgreSQL KPI publishing remains disabled while PostgreSQL is TEST/shadow.','Part6B'),
('analytics_business_source_ready','false'::jsonb,'Operational Source of Truth remains Google Sheets/Drive.','Part6B'),
('analytics_materialization_enabled','false'::jsonb,'Materialization remains disabled until AN-011 measured-need test.','Part6B')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();