-- Enable accepted TEST Raw->Data Hub runtime and invoke it every 5 minutes through the existing pg_cron lane.
-- Supabase publishable key is client-safe; Google/service credentials remain only in Edge Function secrets.
update ops.worker_registry
set enabled=true,
    description='Canonical Supabase Raw -> Google Data Hub sync lane. TEST runtime accepted live on 2026-09-19 with Google auth/read-back/idempotency; scheduled every 5 minutes.',
    updated_at=now()
where worker_key='raw_sync';

do $$
declare v_jobid bigint;
begin
 select jobid into v_jobid from cron.job where jobname='meyou-connect-raw-datahub-sync';
 if v_jobid is not null then perform cron.unschedule(v_jobid); end if;
end $$;

select cron.schedule(
 'meyou-connect-raw-datahub-sync','*/5 * * * *',
 $cron$
 select (extensions.http((
   'POST',
   'https://pgjmxdeafzogzsyawejs.supabase.co/functions/v1/raw-datahub-sync',
   array[
     extensions.http_header('Authorization','Bearer sb_publishable_10U1B29lgIYs85IuMQ1IOQ_CpfQc-BI'),
     extensions.http_header('apikey','sb_publishable_10U1B29lgIYs85IuMQ1IOQ_CpfQc-BI')
   ],
   'application/json',
   '{"batchSize":500}'
 )::extensions.http_request)).status;
 $cron$
);
