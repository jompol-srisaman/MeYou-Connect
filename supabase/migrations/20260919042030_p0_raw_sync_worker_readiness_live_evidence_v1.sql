-- Readiness projection: Edge-based raw_sync uses heartbeat + sync ledger evidence instead of worker_runs.
create or replace view ops.unified_worker_readiness_v
with (security_invoker=true)
as
with latest_hb as (
  select distinct on (worker_key) worker_key,worker_instance,environment,status heartbeat_status,version,last_seen_at
  from ops.worker_heartbeats order by worker_key,last_seen_at desc
), runs as (
  select worker_key,count(*) filter(where status='SUCCEEDED') successful_runs,
         count(*) filter(where status in ('FAILED','DEAD_LETTER')) failed_runs,
         max(coalesce(finished_at,started_at)) last_run_at
  from ops.worker_runs group by worker_key
), candidate_gap as (
  select count(*) filter(where readiness='NOT_READY') gap_count from ops.candidate_promotion_gap_v
), raw_sync_evidence as (
  select count(*) filter(where sync_status='SYNCED') synced_count,
         count(*) filter(where sync_status in ('PENDING','RETRY','IN_FLIGHT','DQ')) open_count,
         max(readback_verified_at) latest_readback
  from ops.raw_datahub_sync_ledger
)
select wr.worker_key,wr.domain,wr.enabled,hb.worker_instance,hb.environment,hb.version,hb.heartbeat_status,hb.last_seen_at,
 case when hb.last_seen_at is null then null else extract(epoch from(now()-hb.last_seen_at))::bigint end heartbeat_age_seconds,
 coalesce(r.successful_runs,0)::bigint successful_runs,coalesce(r.failed_runs,0)::bigint failed_runs,r.last_run_at,
 coalesce(wb.ready_count,0) ready_count,coalesce(wb.retry_wait_count,0) retry_wait_count,
 coalesce(wb.approval_wait_count,0) approval_wait_count,coalesce(wb.dead_letter_count,0) dead_letter_count,
 case
  when wr.enabled=false then 'BLOCKED'
  when hb.last_seen_at is not null and (hb.heartbeat_status in ('FAILED','UNHEALTHY','ERROR') or now()-hb.last_seen_at>interval '15 minutes') then 'BLOCKED'
  when wr.worker_key='raw_sync' and hb.last_seen_at is not null and now()-hb.last_seen_at<=interval '15 minutes' and hb.heartbeat_status='HEALTHY'
       and raw_sync_evidence.synced_count>0 and raw_sync_evidence.open_count=0
       and raw_sync_evidence.latest_readback is not null and now()-raw_sync_evidence.latest_readback<=interval '15 minutes' then 'READY'
  when hb.last_seen_at is null and coalesce(r.successful_runs,0)=0 then 'NOT_STARTED'
  when wr.worker_key='candidate_intake' and hb.last_seen_at is not null and now()-hb.last_seen_at<=interval '15 minutes' and candidate_gap.gap_count>0 then 'PARTIAL'
  when hb.last_seen_at is not null and now()-hb.last_seen_at<=interval '15 minutes' and coalesce(r.successful_runs,0)>0 and coalesce(wb.dead_letter_count,0)=0 then 'READY'
  when hb.last_seen_at is not null and now()-hb.last_seen_at<=interval '15 minutes' then 'PARTIAL'
  else 'PARTIAL' end readiness,
 case
  when wr.enabled=false then 'WORKER_DISABLED'
  when hb.last_seen_at is not null and now()-hb.last_seen_at>interval '15 minutes' then 'STALE_HEARTBEAT'
  when wr.worker_key='raw_sync' and hb.last_seen_at is not null and hb.heartbeat_status='HEALTHY'
       and raw_sync_evidence.synced_count>0 and raw_sync_evidence.open_count=0
       and raw_sync_evidence.latest_readback is not null and now()-raw_sync_evidence.latest_readback<=interval '15 minutes'
       then 'EDGE_HEARTBEAT_AND_SYNC_READBACK_VERIFIED'
  when wr.worker_key='candidate_intake' and candidate_gap.gap_count>0 then 'HEARTBEAT_HEALTHY_BUT_CANDIDATE_COMPLETENESS_GAP'
  when hb.last_seen_at is null and coalesce(r.successful_runs,0)=0 then 'REGISTRY_ONLY_NO_HEARTBEAT_OR_RUN_EVIDENCE'
  when coalesce(wb.dead_letter_count,0)>0 then 'DEAD_LETTER_PRESENT'
  else 'RUNTIME_EVIDENCE_EVALUATED' end reason_code
from ops.worker_registry wr
left join latest_hb hb using(worker_key)
left join runs r using(worker_key)
left join ops.worker_backlog_v wb using(worker_key)
cross join candidate_gap cross join raw_sync_evidence;

revoke all on ops.unified_worker_readiness_v from public,anon,authenticated;
grant select on ops.unified_worker_readiness_v to service_role;
