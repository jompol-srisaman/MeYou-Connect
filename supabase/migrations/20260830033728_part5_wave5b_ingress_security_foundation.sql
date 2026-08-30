insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
 ('security_test_ingress_enabled','false'::jsonb,'TEST-only secured ingress execution gate. Must remain false outside controlled tests.','PART5_WAVE5B'),
 ('security_webhook_test_acceptance_passed','false'::jsonb,'Machine-readable TEST acceptance for webhook/API protection.','PART5_WAVE5B')
on conflict (setting_key) do update
set description=excluded.description, source_ref=excluded.source_ref, updated_at=now();

create table ops.ingress_endpoint_policies (
  endpoint_key text primary key,
  environment text not null check (environment in ('TEST','PROD')),
  source_system text not null,
  channel text not null,
  endpoint_class text not null check (endpoint_class in ('SIGNED_WEBHOOK','PUBLIC_FORM','INTERNAL_SERVICE')),
  auth_mode text not null check (auth_mode in ('PROVIDER_SIGNATURE','PUBLIC_ABUSE_GUARD','SERVICE_AUTH')),
  enabled boolean not null default false,
  signature_required boolean not null default false,
  timestamp_required boolean not null default true,
  replay_protection_required boolean not null default true,
  replay_window_seconds integer not null check (replay_window_seconds between 30 and 86400),
  max_future_skew_seconds integer not null default 60 check (max_future_skew_seconds between 0 and 3600),
  max_payload_bytes integer not null check (max_payload_bytes between 1024 and 10485760),
  allowed_content_types text[] not null,
  rate_limit_requests integer not null check (rate_limit_requests between 1 and 100000),
  rate_limit_window_seconds integer not null check (rate_limit_window_seconds between 1 and 3600),
  material_event boolean not null default true,
  raw_input_required boolean not null default true,
  sensitive_allowed boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (cardinality(allowed_content_types) > 0)
);

create table ops.ingress_request_log (
  ingress_request_pk uuid primary key default gen_random_uuid(),
  endpoint_key text not null references ops.ingress_endpoint_policies(endpoint_key),
  environment text not null check (environment in ('TEST','PROD')),
  request_id text not null,
  source_system text not null,
  provider_event_id text,
  idempotency_key text,
  request_timestamp timestamptz,
  received_at timestamptz not null,
  payload_bytes integer not null check (payload_bytes >= 0),
  content_type text,
  signature_present boolean not null default false,
  signature_verified boolean not null default false,
  replay_key_hash text,
  client_key_hash text,
  decision text not null check (decision in ('ALLOW','DENY','QUARANTINE')),
  reason_code text not null,
  raw_input_id text,
  event_pk uuid references ops.events(event_pk),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique(endpoint_key,request_id),
  check (jsonb_typeof(metadata)='object'),
  check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','authorization','signature']))
);

create table ops.ingress_replay_keys (
  endpoint_key text not null references ops.ingress_endpoint_policies(endpoint_key),
  replay_key_hash text not null,
  request_id text not null,
  first_seen_at timestamptz not null,
  expires_at timestamptz not null,
  primary key(endpoint_key,replay_key_hash),
  check (expires_at > first_seen_at)
);

create table ops.ingress_rate_windows (
  endpoint_key text not null references ops.ingress_endpoint_policies(endpoint_key),
  client_key_hash text not null,
  window_started_at timestamptz not null,
  window_seconds integer not null,
  request_count integer not null default 0 check (request_count >= 0),
  expires_at timestamptz not null,
  primary key(endpoint_key,client_key_hash,window_started_at),
  check (window_seconds between 1 and 3600),
  check (expires_at > window_started_at)
);

create index ingress_request_log_endpoint_time_idx on ops.ingress_request_log(endpoint_key,received_at desc);
create index ingress_request_log_decision_time_idx on ops.ingress_request_log(decision,received_at desc);
create index ingress_request_log_reason_time_idx on ops.ingress_request_log(reason_code,received_at desc);
create index ingress_request_log_event_idx on ops.ingress_request_log(event_pk) where event_pk is not null;
create index ingress_replay_keys_expiry_idx on ops.ingress_replay_keys(expires_at);
create index ingress_rate_windows_expiry_idx on ops.ingress_rate_windows(expires_at);

insert into ops.ingress_endpoint_policies(
 endpoint_key,environment,source_system,channel,endpoint_class,auth_mode,enabled,
 signature_required,timestamp_required,replay_protection_required,replay_window_seconds,max_future_skew_seconds,
 max_payload_bytes,allowed_content_types,rate_limit_requests,rate_limit_window_seconds,material_event,raw_input_required,sensitive_allowed,notes)
values
 ('facebook_webhook_test','TEST','FACEBOOK','FACEBOOK','SIGNED_WEBHOOK','PROVIDER_SIGNATURE',false,true,true,true,300,60,1048576,array['application/json'],120,60,true,true,false,'TEST policy only; external channel remains disabled.'),
 ('line_webhook_test','TEST','LINE','LINE','SIGNED_WEBHOOK','PROVIDER_SIGNATURE',false,true,true,true,300,60,1048576,array['application/json'],120,60,true,true,false,'TEST policy only; external channel remains disabled.'),
 ('public_candidate_form_test','TEST','WEB_FORM','WEB','PUBLIC_FORM','PUBLIC_ABUSE_GUARD',false,false,true,true,600,120,262144,array['application/json','application/x-www-form-urlencoded'],30,60,true,true,true,'TEST public form policy; requires replay and abuse controls.'),
 ('founder_internal_test','TEST','CHATGPT','CHATGPT','INTERNAL_SERVICE','SERVICE_AUTH',false,false,true,true,600,120,1048576,array['application/json'],120,60,true,true,true,'TEST internal service policy.')
on conflict (endpoint_key) do nothing;

alter table ops.ingress_endpoint_policies enable row level security;
alter table ops.ingress_request_log enable row level security;
alter table ops.ingress_replay_keys enable row level security;
alter table ops.ingress_rate_windows enable row level security;

create policy ingress_endpoint_policies_client_deny on ops.ingress_endpoint_policies for all to anon,authenticated using(false) with check(false);
create policy ingress_request_log_client_deny on ops.ingress_request_log for all to anon,authenticated using(false) with check(false);
create policy ingress_replay_keys_client_deny on ops.ingress_replay_keys for all to anon,authenticated using(false) with check(false);
create policy ingress_rate_windows_client_deny on ops.ingress_rate_windows for all to anon,authenticated using(false) with check(false);

revoke all on ops.ingress_endpoint_policies,ops.ingress_request_log,ops.ingress_replay_keys,ops.ingress_rate_windows from public,anon,authenticated;
grant select,insert,update,delete on ops.ingress_endpoint_policies,ops.ingress_request_log,ops.ingress_replay_keys,ops.ingress_rate_windows to service_role;