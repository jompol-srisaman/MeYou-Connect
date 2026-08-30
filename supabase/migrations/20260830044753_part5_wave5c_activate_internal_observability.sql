do $$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='meyou-connect-observability-refresh' limit 1;
  if v_job is not null then perform cron.unschedule(v_job); end if;
  perform cron.schedule('meyou-connect-observability-refresh','*/5 * * * *',$cron$select ops.refresh_observability_signals('TEST');$cron$);
end $$;

insert into config.system_settings(setting_key,setting_value,description,source_ref) values
 ('security_observability_foundation_ready','true'::jsonb,'Part 5C observability/incident foundation acceptance passed in TEST','PART5C'),
 ('part5c_foundation_closed','true'::jsonb,'Part 5C TEST foundation closed','PART5C')
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

select ops.record_security_evidence(
 'part5c_observability_incident_acceptance_v1','TEST','ACCEPTANCE_TEST','PASS','SUPABASE_MIGRATION','part5_wave5c_observability_incident_smoke',
 'TEST alert aggregation, severity escalation, SEV0/SEV1 incident creation, acknowledgement deadlines, closure-evidence enforcement, held delivery and role-scoped read API passed.',
 'part5c',null,null,'{"external_delivery_enabled":false,"real_owner_route_verified":false}'::jsonb,now(),null
);

select ops.evaluate_security_gates('TEST','part5c-closeout');
select ops.evaluate_security_gates('PROD','part5c-closeout');