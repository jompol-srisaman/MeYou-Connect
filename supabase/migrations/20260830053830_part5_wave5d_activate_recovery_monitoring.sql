create or replace function ops.refresh_recovery_monitoring() returns jsonb language plpgsql security definer set search_path='' as $$
declare v_test uuid; v_prod uuid; v_prod_verified boolean;
begin
 v_test:=ops.capture_recovery_snapshot('TEST',now());
 v_prod_verified:=config.setting_is_true('security_prod_environment_verified');
 if v_prod_verified then v_prod:=ops.capture_recovery_snapshot('PROD',now()); end if;
 return jsonb_build_object('test_snapshot_pk',v_test,'prod_snapshot_pk',v_prod,'prod_verified',v_prod_verified,'external_alert_delivery_enabled',config.setting_is_true('security_external_alert_delivery_enabled'));
end $$;
revoke all on function ops.refresh_recovery_monitoring() from public,anon,authenticated;
grant execute on function ops.refresh_recovery_monitoring() to service_role;

select cron.unschedule(jobid) from cron.job where jobname='meyou-connect-recovery-readiness';
select cron.schedule('meyou-connect-recovery-readiness','*/15 * * * *',$$select ops.refresh_recovery_monitoring();$$);

update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key='security_recovery_monitoring_enabled';