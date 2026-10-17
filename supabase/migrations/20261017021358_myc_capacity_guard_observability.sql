-- Founder-authorized additive capacity metrics and alerts, PR29.
-- Actual isolated PostgreSQL17.6 ACL/capability/UNKNOWN/throttle/history tests PASS.
-- REVIEW DRAFT ONLY. Do not apply from this file.
-- Additive health and alert monitoring for existing Part 5C observability.
-- No data deletion, importer/guard replacement, Cron #11 activation, route
-- creation, external delivery, or setting change is performed here.
-- Exercise inside a disposable, network-isolated clone transaction first.

-- Pure byte classifier: boundaries are inclusive. Synthetic boundary tests do
-- not establish physical guard behavior.
create or replace function ops.capacity_classify(p_database_bytes bigint,p_shadow_bytes bigint)
returns jsonb language sql immutable security definer set search_path=''
as $$
  select jsonb_build_object(
    'database_state',case when p_database_bytes is null then 'UNKNOWN'
                          when p_database_bytes >= 419430400 then 'STOP'
                          when p_database_bytes >= 262144000 then 'WARN' else 'OK' end,
    'shadow_state',case when p_shadow_bytes is null then 'UNKNOWN'
                        when p_shadow_bytes >= 78643200 then 'STOP' else 'OK' end,
    'database_warning_bytes',262144000,
    'database_stop_bytes',419430400,
    'shadow_stop_bytes',78643200
  );
$$;
alter function ops.capacity_classify(bigint,bigint) owner to postgres;
revoke all on function ops.capacity_classify(bigint,bigint) from public,anon,authenticated;
grant execute on function ops.capacity_classify(bigint,bigint) to service_role;

-- Aggregate-only runtime snapshot. The service-only helper is exposed to the
-- frontend through the capability-checked API below.
create or replace function ops.capacity_guard_metrics()
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_db_bytes bigint;
  v_shadow_bytes bigint;
  v_classification jsonb;
begin
  v_db_bytes := pg_catalog.pg_database_size(pg_catalog.current_database());
  if pg_catalog.to_regclass('ops.shadow_import_rows') is not null then
    v_shadow_bytes := pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass);
  end if;
  v_classification := ops.capacity_classify(v_db_bytes,v_shadow_bytes);
  return v_classification || jsonb_build_object(
    'sampled_at',pg_catalog.clock_timestamp(),
    'database_bytes',v_db_bytes,
    'database_mib',pg_catalog.round(v_db_bytes::numeric / 1048576,2),
    'shadow_relation_bytes',v_shadow_bytes,
    'shadow_relation_mib',case when v_shadow_bytes is null then null else pg_catalog.round(v_shadow_bytes::numeric / 1048576,2) end,
    'open_shadow_sessions',(select count(*) from ops.shadow_import_sessions where status='OPEN'),
    'staged_shadow_sessions',(select count(*) from ops.shadow_import_sessions where status='STAGED'),
    'open_alerts',(select count(*) from ops.alert_instances where status in ('OPEN','ACKNOWLEDGED')),
    'active_capacity_alerts',(select count(*) from ops.alert_instances where status in ('OPEN','ACKNOWLEDGED') and signal_key in ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_DATABASE_CAPACITY_STOP_400MIB','MYC_SHADOW_CAPACITY_STOP_75MIB')),
    'held_deliveries',(select count(*) from ops.alert_delivery_queue where delivery_status='HELD'),
    'ready_deliveries',(select count(*) from ops.alert_delivery_queue where delivery_status='READY'),
    'verified_active_external_routes',(select count(*) from ops.alert_routes where active and verified and channel_type<>'DB_ONLY'),
    'external_delivery_enabled',config.setting_is_true('security_external_alert_delivery_enabled'),
    'migration_shadow_write_enabled',config.setting_is_true('migration_shadow_write_enabled'),
    'business_master_apply_enabled',config.setting_is_true('business_master_apply_enabled'),
    'migration_target_apply_enabled',config.setting_is_true('migration_target_apply_enabled'),
    'production_cutover_approved',config.setting_is_true('production_cutover_approved'),
    'cron11_active',coalesce((select j.active from cron.job j where j.jobid=11 and j.jobname='myc_datahub_shadow_import_5min'),false),
    'observability_refresh_active',coalesce((select j.active from cron.job j where j.jobname='meyou-connect-observability-refresh'),false),
    'capacity_samples_retained',(select count(*) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD'),
    'capacity_sample_limit',2016,
    'capacity_samples_24h',(select count(*) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD' and s.captured_at>=now()-interval '24 hours'),
    'capacity_oldest_sample_at',(select min(s.captured_at) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD'),
    'capacity_latest_sample_at',(select max(s.captured_at) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD'),
    'capacity_database_min_bytes_24h',(select min((s.details#>>'{metrics,database_bytes}')::bigint) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD' and s.captured_at>=now()-interval '24 hours'),
    'capacity_database_max_bytes_24h',(select max((s.details#>>'{metrics,database_bytes}')::bigint) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD' and s.captured_at>=now()-interval '24 hours'),
    'capacity_shadow_min_bytes_24h',(select min((s.details#>>'{metrics,shadow_relation_bytes}')::bigint) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD' and s.captured_at>=now()-interval '24 hours'),
    'capacity_shadow_max_bytes_24h',(select max((s.details#>>'{metrics,shadow_relation_bytes}')::bigint) from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD' and s.captured_at>=now()-interval '24 hours'),
    'capacity_history_full',(select count(*)>=2016 from ops.recovery_monitor_snapshots s where s.environment='TEST' and s.details->>'capture_source'='MYC_CAPACITY_GUARD')
  );
end;
$$;
alter function ops.capacity_guard_metrics() owner to postgres;
revoke all on function ops.capacity_guard_metrics() from public,anon,authenticated;
grant execute on function ops.capacity_guard_metrics() to service_role;

-- Existing capability, no direct ops table access and no destination/person or
-- source-row identifiers in the response.
create or replace function api.capacity_guard_health()
returns jsonb language plpgsql security definer set search_path=''
as $$
begin
  perform authz.require_capability('security_read');
  return ops.capacity_guard_metrics();
end;
$$;
alter function api.capacity_guard_health() owner to postgres;
revoke all on function api.capacity_guard_health() from public,anon;
grant execute on function api.capacity_guard_health() to authenticated,service_role;

-- Internal service-only signal emitter. Stable fingerprints aggregate repeats.
-- Existing active alerts are re-emitted only when new or after six hours.
create or replace function ops.emit_capacity_alert_if_due(
  p_environment text,p_signal_key text,p_severity text,p_summary text,p_metadata jsonb
) returns boolean
language plpgsql security definer set search_path=''
as $$
declare v_alert ops.alert_instances%rowtype;
begin
  if p_environment is null or p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
  if p_severity is null or p_summary is null or btrim(p_summary)='' then raise exception 'INVALID_CAPACITY_SIGNAL'; end if;
  if p_signal_key is null or p_signal_key not in ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_DATABASE_CAPACITY_STOP_400MIB','MYC_SHADOW_CAPACITY_STOP_75MIB','MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED') then
    raise exception 'INVALID_CAPACITY_SIGNAL';
  end if;
  if (p_signal_key='MYC_DATABASE_CAPACITY_WARNING_250MIB' and p_severity<>'SEV2')
     or (p_signal_key in ('MYC_DATABASE_CAPACITY_STOP_400MIB','MYC_SHADOW_CAPACITY_STOP_75MIB') and p_severity<>'SEV1')
     or (p_signal_key='MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED' and p_severity<>'SEV2') then
    raise exception 'INVALID_CAPACITY_SEVERITY';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('MYC_CAPACITY_ALERT|'||p_environment||'|'||p_signal_key,0));
  select * into v_alert from ops.alert_instances a
  where a.environment=p_environment and a.signal_key=p_signal_key
    and a.fingerprint=p_signal_key and a.status in ('OPEN','ACKNOWLEDGED')
  for update;
  if found and v_alert.last_seen_at > now()-interval '6 hours'
     and v_alert.metadata->>'capacity_recovered_at' is null then return false; end if;
  perform ops.ingest_alert_signal(
    p_environment,p_signal_key,p_signal_key,p_severity,p_summary,1,'MYC_CAPACITY_GUARD',
    coalesce(p_metadata,'{}'::jsonb)||jsonb_build_object(
      'source','ops.refresh_capacity_guard_alerts','capacity_recovered_at',null),now());
  return true;
end;
$$;
alter function ops.emit_capacity_alert_if_due(text,text,text,text,jsonb) owner to postgres;
revoke all on function ops.emit_capacity_alert_if_due(text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function ops.emit_capacity_alert_if_due(text,text,text,text,jsonb) to service_role;

-- Resolve only transient SEV2 warning alerts via existing alert status fields;
-- record the recovery as an occurrence and cancel only unsent deliveries.
-- SEV1 stop alerts remain open; do not auto-close their incidents.
create or replace function ops.record_capacity_recovery(
  p_environment text,p_signal_key text,p_recovery_reason text,p_resolve_warning boolean default false
) returns integer
language plpgsql security definer set search_path=''
as $$
declare v_alert ops.alert_instances%rowtype; v_count integer:=0;
begin
  if p_environment is null or p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
  if p_signal_key is null or p_signal_key not in ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_DATABASE_CAPACITY_STOP_400MIB','MYC_SHADOW_CAPACITY_STOP_75MIB') then
    raise exception 'INVALID_CAPACITY_SIGNAL';
  end if;
  if p_recovery_reason is null or (p_resolve_warning and p_signal_key<>'MYC_DATABASE_CAPACITY_WARNING_250MIB') then
    raise exception 'INVALID_CAPACITY_RECOVERY';
  end if;
  for v_alert in
    select * from ops.alert_instances a
    where a.environment=p_environment and a.signal_key=p_signal_key
      and a.fingerprint=p_signal_key and a.status in ('OPEN','ACKNOWLEDGED')
    for update
  loop
    if p_resolve_warning and v_alert.severity='SEV2' then
      update ops.alert_instances set status='RESOLVED',resolved_at=now(),
        resolved_by='SYSTEM_CAPACITY_GUARD',updated_at=now(),
        metadata=metadata||jsonb_build_object('capacity_state','RECOVERED','capacity_recovery_reason',p_recovery_reason)
      where alert_pk=v_alert.alert_pk;
    elsif v_alert.metadata->>'capacity_recovered_at' is null then
      update ops.alert_instances set updated_at=now(),
        metadata=metadata||jsonb_build_object('capacity_state','RECOVERED_REQUIRES_INCIDENT_REVIEW',
          'capacity_recovery_reason',p_recovery_reason,'capacity_recovered_at',now())
      where alert_pk=v_alert.alert_pk;
    else
      continue;
    end if;
    insert into ops.alert_occurrences(alert_pk,observed_at,severity,affected_count,source_ref,summary,metadata)
    values(v_alert.alert_pk,now(),v_alert.severity,0,'MYC_CAPACITY_GUARD',
      'Capacity condition returned below its threshold',
      jsonb_build_object('transition','CAPACITY_RECOVERED','reason',p_recovery_reason));
    update ops.alert_delivery_queue set delivery_status='CANCELLED',
      hold_reason='CAPACITY_RECOVERED',updated_at=now()
    where alert_pk=v_alert.alert_pk and delivery_status in ('HELD','READY','FAILED');
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;
alter function ops.record_capacity_recovery(text,text,text,boolean) owner to postgres;
revoke all on function ops.record_capacity_recovery(text,text,text,boolean) from public,anon,authenticated;
grant execute on function ops.record_capacity_recovery(text,text,text,boolean) to service_role;

create or replace function ops.refresh_capacity_guard_alerts(p_environment text default 'TEST')
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_metrics jsonb;
  v_db_bytes bigint;
  v_shadow_bytes bigint;
  v_db_state text;
  v_shadow_state text;
  v_emitted integer:=0;
  v_recovered integer:=0;
begin
  if p_environment is null or p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
  v_metrics:=ops.capacity_guard_metrics();
  v_db_bytes:=(v_metrics->>'database_bytes')::bigint;
  v_shadow_bytes:=(v_metrics->>'shadow_relation_bytes')::bigint;
  v_db_state:=v_metrics->>'database_state';
  v_shadow_state:=v_metrics->>'shadow_state';

  if v_db_state='STOP' then
    if ops.emit_capacity_alert_if_due(p_environment,'MYC_DATABASE_CAPACITY_STOP_400MIB','SEV1',
      'Database capacity reached the 400 MiB hard stop',
      jsonb_build_object('database_bytes',v_db_bytes,'threshold_bytes',419430400)) then v_emitted:=v_emitted+1; end if;
  elsif v_db_state='WARN' then
    if ops.emit_capacity_alert_if_due(p_environment,'MYC_DATABASE_CAPACITY_WARNING_250MIB','SEV2',
      'Database capacity reached the 250 MiB warning threshold',
      jsonb_build_object('database_bytes',v_db_bytes,'threshold_bytes',262144000)) then v_emitted:=v_emitted+1; end if;
  end if;

  if v_shadow_state='STOP' then
    if ops.emit_capacity_alert_if_due(p_environment,'MYC_SHADOW_CAPACITY_STOP_75MIB','SEV1',
      'Shadow relation reached the 75 MiB hard stop',
      jsonb_build_object('shadow_relation_bytes',v_shadow_bytes,'threshold_bytes',78643200)) then v_emitted:=v_emitted+1; end if;
  end if;

  if v_db_state='OK' then
    v_recovered:=v_recovered+ops.record_capacity_recovery(p_environment,'MYC_DATABASE_CAPACITY_WARNING_250MIB','BELOW_250MIB',true);
  elsif v_db_state='STOP' then
    v_recovered:=v_recovered+ops.record_capacity_recovery(p_environment,'MYC_DATABASE_CAPACITY_WARNING_250MIB','ESCALATED_TO_400MIB',true);
  end if;
  if v_db_state in ('OK','WARN') then
    v_recovered:=v_recovered+ops.record_capacity_recovery(p_environment,'MYC_DATABASE_CAPACITY_STOP_400MIB','BELOW_400MIB',false);
  end if;
  if v_shadow_state='OK' then
    v_recovered:=v_recovered+ops.record_capacity_recovery(p_environment,'MYC_SHADOW_CAPACITY_STOP_75MIB','BELOW_75MIB',false);
  end if;
  return v_metrics||jsonb_build_object('capacity_alerts_emitted',v_emitted,
    'capacity_recoveries_recorded',v_recovered);
end;
$$;
alter function ops.refresh_capacity_guard_alerts(text) owner to postgres;
revoke all on function ops.refresh_capacity_guard_alerts(text) from public,anon,authenticated;
grant execute on function ops.refresh_capacity_guard_alerts(text) to service_role;

-- Reuse the existing recovery monitor history table without changing its DR
-- meaning. Keep at most 2,016 TEST snapshots (15-minute cadence for 21 days).
-- Never update/delete historical rows; once full, stop optional sampling and
-- raise a stable archive-required alert for an operator-controlled archive.
create or replace function ops.capture_capacity_guard_snapshot(p_environment text default 'TEST')
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_metrics jsonb;
  v_count integer;
  v_last timestamptz;
  v_sample_id uuid;
  v_archived_alert boolean:=false;
begin
  if p_environment is null or p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtext('MYC_CAPACITY_HISTORY'),pg_catalog.hashtext(p_environment));
  select count(*),max(captured_at) into v_count,v_last from ops.recovery_monitor_snapshots
  where environment=p_environment and details->>'capture_source'='MYC_CAPACITY_GUARD';
  if v_count>=2016 then
    v_archived_alert:=ops.emit_capacity_alert_if_due(p_environment,'MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED','SEV2',
      'Capacity history reached its 21-day sample limit; archive is required before sampling can resume',
      jsonb_build_object('retained_samples',v_count,'sample_limit',2016));
    return jsonb_build_object('captured',false,'history_full',true,'retained_samples',v_count,'sample_limit',2016,'archive_alert_emitted',v_archived_alert);
  end if;
  if v_last is not null and v_last>now()-interval '15 minutes' then
    return jsonb_build_object('captured',false,'history_full',false,'retained_samples',v_count,'sample_limit',2016);
  end if;
  v_metrics:=ops.capacity_guard_metrics();
  insert into ops.recovery_monitor_snapshots(
    environment,captured_at,active_tier_a_policies,fresh_backup_policies,fresh_independent_policies,
    restore_verified_policies,stale_or_missing_policies,oldest_required_backup_age_minutes,
    latest_restore_age_days,overall_status,details
  )
  select p_environment,now(),s.active_tier_a_policies,s.fresh_backup_policies,s.fresh_independent_policies,
    s.restore_verified_policies,s.stale_or_missing_policies,s.oldest_required_backup_age_minutes,
    s.latest_restore_age_days,s.overall_status,
    jsonb_build_object('monitor_only',true,'capture_source','MYC_CAPACITY_GUARD',
      'does_not_evaluate_recovery',true,'metrics',v_metrics)
  from (select * from ops.recovery_monitor_snapshots where environment=p_environment
        and details->>'capture_source' is distinct from 'MYC_CAPACITY_GUARD'
        order by captured_at desc limit 1) s;
  if not found then
    insert into ops.recovery_monitor_snapshots(environment,captured_at,overall_status,details)
    values(p_environment,now(),'NOT_READY',jsonb_build_object('monitor_only',true,
      'capture_source','MYC_CAPACITY_GUARD','does_not_evaluate_recovery',true,'metrics',v_metrics));
  end if;
  select recovery_snapshot_pk into v_sample_id from ops.recovery_monitor_snapshots
  where environment=p_environment and details->>'capture_source'='MYC_CAPACITY_GUARD'
  order by captured_at desc limit 1;
  return jsonb_build_object('captured',true,'history_full',false,'retained_samples',v_count+1,
    'sample_limit',2016,'snapshot_ref',v_sample_id);
end;
$$;
alter function ops.capture_capacity_guard_snapshot(text) owner to postgres;
revoke all on function ops.capture_capacity_guard_snapshot(text) from public,anon,authenticated;
grant execute on function ops.capture_capacity_guard_snapshot(text) to service_role;

-- Preserve existing refresh signature, owner, ACL and Cron #3. Existing loops
-- and response keys stay intact; capacity monitoring is appended in-place.
create or replace function ops.refresh_observability_signals(p_environment text default 'TEST')
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; v_alerts int:=0; v_security int:=0; v_result jsonb; v_capacity jsonb; v_history jsonb;
begin
 if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
 for r in select * from ops.alert_candidates_v loop
   v_result:=ops.ingest_alert_signal(p_environment,r.alert_key,r.alert_key,coalesce(r.severity,'SEV2'),r.reason,r.affected_count,r.alert_key,jsonb_build_object('source','ops.alert_candidates_v','first_seen_at',r.first_seen_at),now());
   v_alerts:=v_alerts+1;
 end loop;
 for r in select security_event_pk,event_type,severity,summary,evidence_ref,entity_type,entity_id,occurred_at from ops.security_events where environment=p_environment and status='OPEN' and severity in ('SEV0','SEV1') loop
   v_result:=ops.ingest_alert_signal(p_environment,r.event_type,'SECURITY_EVENT|'||r.event_type||'|'||coalesce(r.entity_type,'')||'|'||coalesce(r.entity_id,''),r.severity,r.summary,1,coalesce(r.evidence_ref,r.security_event_pk::text),jsonb_build_object('source','ops.security_events'),r.occurred_at);
   v_security:=v_security+1;
 end loop;
 v_capacity:=ops.refresh_capacity_guard_alerts(p_environment);
 v_history:=ops.capture_capacity_guard_snapshot(p_environment);
 return jsonb_build_object('alert_candidates_scanned',v_alerts,'security_events_scanned',v_security,'capacity_guard',v_capacity,'capacity_history',v_history);
end $$;

-- CREATE OR REPLACE preserves refresh function identity and grants. Verify on
-- clone. Do not change Cron #3 command/schedule or activate Cron #11.
-- Keep security_external_alert_delivery_enabled false until route + TEST
-- receipt evidence exists and delivery is explicitly authorized.
