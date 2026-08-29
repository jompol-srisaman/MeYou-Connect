begin;

do $$
declare
  v_job record;
begin
  for v_job in select jobid from cron.job where jobname='work-connect-ops-snapshot'
  loop
    perform cron.unschedule(v_job.jobid);
  end loop;
end $$;

select cron.schedule(
  'work-connect-ops-snapshot',
  '*/15 * * * *',
  $cmd$select ops.capture_operations_snapshot('test', now());$cmd$
);

commit;
