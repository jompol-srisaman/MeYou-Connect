-- Founder-authorized capacity delivery via existing local Codex/Gmail tools.
-- Clone-tested bounded leases, real concurrent claims and receipt acknowledgements.
-- REVIEW DRAFT ONLY. Do not apply to the live project or send email from SQL.
-- Gmail/native heartbeat integration is external to this database contract.
-- Install after MYC_CAPACITY_OBSERVABILITY_REVIEW.sql.

create or replace function ops.claim_myc_capacity_emails(p_limit integer default 5)
returns table(
  delivery_pk uuid,
  claimed_at timestamptz,
  email_subject_tag text,
  signal_key text,
  severity text,
  summary text,
  capacity_metrics jsonb
)
language plpgsql security definer set search_path=''
as $$
begin
  if p_limit is null or p_limit<1 or p_limit>5 then raise exception 'INVALID_CLAIM_LIMIT'; end if;
  if not config.setting_is_true('security_external_alert_delivery_enabled') then return; end if;

  return query
  with eligible as materialized (
    select q.delivery_pk,a.alert_pk,a.signal_key,a.severity
    from ops.alert_delivery_queue q
    join ops.alert_instances a on a.alert_pk=q.alert_pk
    join ops.alert_routes r on r.route_pk=q.route_pk
    where a.environment='TEST' and a.owner_role='founder'
      and a.status in ('OPEN','ACKNOWLEDGED')
      and a.signal_key in (
        'MYC_DATABASE_CAPACITY_WARNING_250MIB',
        'MYC_DATABASE_CAPACITY_STOP_400MIB',
        'MYC_SHADOW_CAPACITY_STOP_75MIB',
        'MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED',
        'MYC_CAPACITY_DELIVERY_TEST'
      )
      and q.delivery_status in ('READY','FAILED')
      and q.attempt_count<3
      and (q.last_attempt_at is null or q.last_attempt_at<=pg_catalog.clock_timestamp()-interval '15 minutes')
      and r.environment='TEST' and r.owner_role='founder' and r.channel_type='EMAIL'
      and r.destination_ref='MYC_FOUNDER_CONNECTED_GMAIL_SELF'
      and r.active and r.verified and r.verified_at is not null
    order by q.created_at,q.delivery_pk
    limit p_limit
    for update of q skip locked
  ), claimed as (
    update ops.alert_delivery_queue q
    set attempt_count=q.attempt_count+1,last_attempt_at=pg_catalog.clock_timestamp(),updated_at=pg_catalog.clock_timestamp()
    from eligible e
    where q.delivery_pk=e.delivery_pk
    returning q.delivery_pk,q.alert_pk,q.route_pk,q.last_attempt_at
  )
  select c.delivery_pk,c.last_attempt_at,
    'MYC-CAPACITY-'||c.delivery_pk::text,
    a.signal_key,a.severity,
    case a.signal_key
      when 'MYC_DATABASE_CAPACITY_WARNING_250MIB' then 'MeYou Connect database is at or above its 250 MiB warning threshold.'
      when 'MYC_DATABASE_CAPACITY_STOP_400MIB' then 'MeYou Connect database has reached its 400 MiB hard stop.'
      when 'MYC_SHADOW_CAPACITY_STOP_75MIB' then 'MeYou Connect shadow storage has reached its 75 MiB hard stop.'
      when 'MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED' then 'MeYou Connect capacity history is full and requires archive review.'
      else 'MeYou Connect capacity email transport test.'
    end,
    case when a.signal_key='MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED' then
      pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'database_bytes',current_metrics.m->'database_bytes','database_mib',current_metrics.m->'database_mib',
        'shadow_relation_bytes',current_metrics.m->'shadow_relation_bytes','shadow_relation_mib',current_metrics.m->'shadow_relation_mib',
        'database_warning_bytes',current_metrics.m->'database_warning_bytes','database_stop_bytes',current_metrics.m->'database_stop_bytes',
        'shadow_stop_bytes',current_metrics.m->'shadow_stop_bytes',
        'retained_samples',case when pg_catalog.jsonb_typeof(a.metadata->'retained_samples')='number' then a.metadata->'retained_samples' end,
        'sample_limit',case when pg_catalog.jsonb_typeof(a.metadata->'sample_limit')='number' then a.metadata->'sample_limit' end))
    else pg_catalog.jsonb_strip_nulls(pg_catalog.jsonb_build_object(
        'database_bytes',current_metrics.m->'database_bytes','database_mib',current_metrics.m->'database_mib',
        'shadow_relation_bytes',current_metrics.m->'shadow_relation_bytes','shadow_relation_mib',current_metrics.m->'shadow_relation_mib',
        'database_warning_bytes',current_metrics.m->'database_warning_bytes','database_stop_bytes',current_metrics.m->'database_stop_bytes',
        'shadow_stop_bytes',current_metrics.m->'shadow_stop_bytes'))
    end
  from claimed c
  join ops.alert_instances a on a.alert_pk=c.alert_pk
  cross join lateral (select pg_catalog.jsonb_build_object(
    'database_bytes',pg_catalog.pg_database_size(pg_catalog.current_database()),
    'database_mib',pg_catalog.round(pg_catalog.pg_database_size(pg_catalog.current_database())::numeric/1048576,2),
    'shadow_relation_bytes',pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass),
    'shadow_relation_mib',pg_catalog.round(pg_catalog.pg_total_relation_size('ops.shadow_import_rows'::regclass)::numeric/1048576,2),
    'database_warning_bytes',262144000,'database_stop_bytes',419430400,'shadow_stop_bytes',78643200
  ) as m) current_metrics;
end;
$$;
alter function ops.claim_myc_capacity_emails(integer) owner to postgres;
revoke all on function ops.claim_myc_capacity_emails(integer) from public,anon,authenticated;
grant execute on function ops.claim_myc_capacity_emails(integer) to service_role;

-- A claim token is the queue's last_attempt_at. Complete locks the alert row
-- before the queue row, matching the producer's alert-then-queue lock order.
-- SENT requires a real Gmail receipt identifier; failures store only an enum.
create or replace function ops.complete_myc_capacity_email(
  p_delivery_pk uuid,p_claimed_at timestamptz,p_receipt_id text,
  p_received boolean,p_error_class text default null
) returns jsonb
language plpgsql security definer set search_path=''
as $$
declare
  v_alert_pk uuid;
  v_alert ops.alert_instances%rowtype;
  v_delivery ops.alert_delivery_queue%rowtype;
  v_existing_receipt text;
  v_receipt jsonb;
begin
  if p_delivery_pk is null or p_claimed_at is null or p_received is null then raise exception 'INVALID_COMPLETION'; end if;
  if p_received then
    if p_receipt_id is null or pg_catalog.length(p_receipt_id)>300 or p_receipt_id !~ '^[A-Za-z0-9._:-]+$' or p_error_class is not null then
      raise exception 'RECEIPT_REQUIRED_OR_INVALID';
    end if;
  elsif p_receipt_id is not null or p_error_class is null or p_error_class not in (
    'NO_RECEIPT','SEND_REJECTED','RATE_LIMITED','AUTH_UNAVAILABLE','NETWORK_TIMEOUT','WORKER_ERROR'
  ) then raise exception 'INVALID_FAILURE_CLASS';
  end if;

  select q.alert_pk into v_alert_pk from ops.alert_delivery_queue q where q.delivery_pk=p_delivery_pk;
  if not found then raise exception 'DELIVERY_NOT_FOUND'; end if;
  select * into v_alert from ops.alert_instances a where a.alert_pk=v_alert_pk for update;
  if not found then raise exception 'ALERT_NOT_FOUND'; end if;
  select * into v_delivery from ops.alert_delivery_queue q where q.delivery_pk=p_delivery_pk for update;
  if not found then raise exception 'DELIVERY_NOT_FOUND'; end if;

  if v_delivery.delivery_status='SENT' and p_received then
    v_existing_receipt:=v_alert.metadata#>>'{capacity_email_receipt,receipt_id}';
    if v_alert.metadata#>>'{capacity_email_receipt,delivery_pk}'=p_delivery_pk::text
       and v_existing_receipt=p_receipt_id then
      return pg_catalog.jsonb_build_object('delivery_status','SENT','idempotent',true,'receipt_id',p_receipt_id);
    end if;
    raise exception 'RECEIPT_CONFLICT';
  end if;

  if v_delivery.delivery_status not in ('READY','FAILED') or v_delivery.last_attempt_at is distinct from p_claimed_at
     or v_delivery.attempt_count<1 or v_delivery.attempt_count>3 then
    raise exception 'STALE_OR_UNCLAIMED_DELIVERY';
  end if;
  if v_alert.status not in ('OPEN','ACKNOWLEDGED') then raise exception 'INACTIVE_ALERT'; end if;
  if v_alert.environment<>'TEST' or v_alert.owner_role<>'founder' or v_alert.signal_key not in (
    'MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_DATABASE_CAPACITY_STOP_400MIB',
    'MYC_SHADOW_CAPACITY_STOP_75MIB','MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED','MYC_CAPACITY_DELIVERY_TEST'
  ) then raise exception 'SIGNAL_NOT_EMAIL_ELIGIBLE'; end if;

  if p_received then
    v_receipt:=pg_catalog.jsonb_build_object('delivery_pk',p_delivery_pk,'receipt_id',p_receipt_id,'received_at',pg_catalog.clock_timestamp());
    update ops.alert_delivery_queue set delivery_status='SENT',hold_reason=null,last_error=null,updated_at=pg_catalog.clock_timestamp()
    where delivery_pk=p_delivery_pk;
    update ops.alert_instances set metadata=metadata||pg_catalog.jsonb_build_object('capacity_email_receipt',v_receipt),updated_at=pg_catalog.clock_timestamp()
    where alert_pk=v_alert_pk;
    return pg_catalog.jsonb_build_object('delivery_status','SENT','idempotent',false,'receipt_id',p_receipt_id);
  end if;

  update ops.alert_delivery_queue set delivery_status='FAILED',last_error=p_error_class,updated_at=pg_catalog.clock_timestamp()
  where delivery_pk=p_delivery_pk;
  return pg_catalog.jsonb_build_object('delivery_status','FAILED','attempt_count',v_delivery.attempt_count,
    'retryable',v_delivery.attempt_count<3,'error_class',p_error_class);
end;
$$;
alter function ops.complete_myc_capacity_email(uuid,timestamptz,text,boolean,text) owner to postgres;
revoke all on function ops.complete_myc_capacity_email(uuid,timestamptz,text,boolean,text) from public,anon,authenticated;
grant execute on function ops.complete_myc_capacity_email(uuid,timestamptz,text,boolean,text) to service_role;

-- No route/rule/gate/test alert is inserted or enabled by this draft. The
-- native heartbeat/Gmail bridge must retain the Gmail message ID as receipt,
-- call the completion RPC only after readback, and inspect bounded failure
-- backlog. A 15-minute lease is at-least-once; it cannot guarantee exactly
-- once email delivery if a send succeeds but receipt acknowledgement is lost.
-- A Codex heartbeat bridge is not a continuously available worker: it can
-- run only while the local app/session and its authorized Gmail connection are
-- available, so offline periods delay claims and delivery beyond 15 minutes.
