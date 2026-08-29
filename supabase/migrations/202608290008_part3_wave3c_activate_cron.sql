begin;

create extension if not exists pg_cron;

do $$
declare
  v_jobid bigint;
begin
  for v_jobid in
    select jobid from cron.job where jobname = 'work-connect-scheduler-tick'
  loop
    perform cron.unschedule(v_jobid);
  end loop;

  perform cron.schedule(
    'work-connect-scheduler-tick',
    '*/5 * * * *',
    $cmd$select ops.scheduler_tick(now(), 100, 'CRON');$cmd$
  );
end $$;

commit;