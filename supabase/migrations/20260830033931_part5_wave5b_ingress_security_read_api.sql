create or replace view ops.ingress_security_summary_v
with (security_invoker=true)
as
select
  p.endpoint_key,
  p.environment,
  p.source_system,
  p.channel,
  p.endpoint_class,
  p.enabled,
  p.signature_required,
  p.timestamp_required,
  p.replay_protection_required,
  p.replay_window_seconds,
  p.max_payload_bytes,
  p.rate_limit_requests,
  p.rate_limit_window_seconds,
  count(l.ingress_request_pk) as total_requests,
  count(*) filter (where l.decision='ALLOW') as allowed_requests,
  count(*) filter (where l.decision='DENY') as denied_requests,
  count(*) filter (where l.decision='QUARANTINE') as quarantined_requests,
  count(*) filter (where l.reason_code='REPLAY_DETECTED') as replay_rejections,
  count(*) filter (where l.reason_code='RATE_LIMITED') as rate_limit_rejections,
  count(*) filter (where l.reason_code in ('SIGNATURE_REQUIRED','SIGNATURE_INVALID')) as signature_rejections,
  max(l.received_at) as last_request_at
from ops.ingress_endpoint_policies p
left join ops.ingress_request_log l on l.endpoint_key=p.endpoint_key
group by p.endpoint_key,p.environment,p.source_system,p.channel,p.endpoint_class,p.enabled,p.signature_required,p.timestamp_required,p.replay_protection_required,p.replay_window_seconds,p.max_payload_bytes,p.rate_limit_requests,p.rate_limit_window_seconds;

revoke all on ops.ingress_security_summary_v from public,anon,authenticated;
grant select on ops.ingress_security_summary_v to service_role;

create or replace function api.security_ingress_policies()
returns table(
  endpoint_key text,
  environment text,
  source_system text,
  channel text,
  endpoint_class text,
  enabled boolean,
  signature_required boolean,
  timestamp_required boolean,
  replay_protection_required boolean,
  replay_window_seconds integer,
  max_payload_bytes integer,
  rate_limit_requests integer,
  rate_limit_window_seconds integer,
  sensitive_allowed boolean
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_read');
  return query
  select p.endpoint_key,p.environment,p.source_system,p.channel,p.endpoint_class,p.enabled,
         p.signature_required,p.timestamp_required,p.replay_protection_required,p.replay_window_seconds,
         p.max_payload_bytes,p.rate_limit_requests,p.rate_limit_window_seconds,p.sensitive_allowed
  from ops.ingress_endpoint_policies p
  order by p.environment,p.endpoint_key;
end; $$;

create or replace function api.security_ingress_summary()
returns table(
  endpoint_key text,
  environment text,
  source_system text,
  channel text,
  endpoint_class text,
  enabled boolean,
  total_requests bigint,
  allowed_requests bigint,
  denied_requests bigint,
  quarantined_requests bigint,
  replay_rejections bigint,
  rate_limit_rejections bigint,
  signature_rejections bigint,
  last_request_at timestamptz
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_audit_read');
  return query
  select s.endpoint_key,s.environment,s.source_system,s.channel,s.endpoint_class,s.enabled,
         s.total_requests,s.allowed_requests,s.denied_requests,s.quarantined_requests,
         s.replay_rejections,s.rate_limit_rejections,s.signature_rejections,s.last_request_at
  from ops.ingress_security_summary_v s
  order by s.environment,s.endpoint_key;
end; $$;

create or replace function api.security_ingress_rejections(p_limit integer default 100)
returns table(
  endpoint_key text,
  environment text,
  received_at timestamptz,
  decision text,
  reason_code text,
  provider_event_id text,
  request_id text
)
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  perform authz.require_capability('security_audit_read');
  return query
  select l.endpoint_key,l.environment,l.received_at,l.decision,l.reason_code,l.provider_event_id,l.request_id
  from ops.ingress_request_log l
  where l.decision <> 'ALLOW'
  order by l.received_at desc
  limit greatest(1,least(coalesce(p_limit,100),500));
end; $$;

revoke all on function api.security_ingress_policies() from public,anon;
revoke all on function api.security_ingress_summary() from public,anon;
revoke all on function api.security_ingress_rejections(integer) from public,anon;
grant execute on function api.security_ingress_policies() to authenticated,service_role;
grant execute on function api.security_ingress_summary() to authenticated,service_role;
grant execute on function api.security_ingress_rejections(integer) to authenticated,service_role;