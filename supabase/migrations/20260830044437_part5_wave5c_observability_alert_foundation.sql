create table if not exists ops.alert_rule_catalog (
  alert_rule_key text primary key,
  source_signal_key text unique,
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  owner_role text not null,
  auto_incident boolean not null default false,
  active boolean not null default true,
  description text not null,
  source_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.alert_rule_catalog(alert_rule_key,source_signal_key,severity,owner_role,auto_incident,description,source_ref) values
 ('ALT-001','PRIVATE_EVIDENCE_PUBLIC','SEV0','founder',true,'Private evidence becomes public','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-002','ACTIVE_SECRET_LEAK','SEV0','founder',true,'Active credential leak','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-003','RLS_CRITICAL_TEST_FAILURE','SEV1','data_audit',true,'Critical RLS allow/deny regression','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-004','CORE_API_5XX','SEV1','data_audit',true,'Core API 5xx above threshold','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-005','CORE_HEALTH_FAILURE','SEV1','data_audit',true,'Core health check repeated failure','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-006','FINANCE_DEAD_LETTER','SEV1','finance_control',true,'Finance event in dead letter','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-007','CRITICAL_EVENT_STALE','SEV1','automation_worker',true,'Critical event oldest age above threshold','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-008','BACKUP_STALE','SEV1','data_audit',true,'Production database backup stale','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-009','RESTORE_TEST_OVERDUE','SEV2','data_audit',false,'Restore test overdue','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-010','CHECKSUM_MISMATCH','SEV1','data_audit',true,'File checksum mismatch','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-011','JOURNAL_IMBALANCE','SEV0','finance_control',true,'Posted journal imbalance','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1'),
 ('ALT-012','WEBHOOK_SIGNATURE_FAILURE_SPIKE','SEV1','automation_worker',true,'Repeated webhook signature failures','MEYOU_CONNECT_SECURITY_CONTROL_MATRIX_V1')
on conflict (alert_rule_key) do update set
 source_signal_key=excluded.source_signal_key,severity=excluded.severity,owner_role=excluded.owner_role,
 auto_incident=excluded.auto_incident,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

create table if not exists ops.alert_routes (
  route_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('TEST','PROD')),
  owner_role text not null,
  channel_type text not null check (channel_type in ('DB_ONLY','EMAIL','SLACK','LINE','SMS','WEBHOOK')),
  destination_ref text,
  verified boolean not null default false,
  verified_at timestamptz,
  verified_by text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(environment,owner_role,channel_type)
);

create table if not exists ops.alert_instances (
  alert_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('TEST','PROD')),
  alert_rule_key text references ops.alert_rule_catalog(alert_rule_key),
  signal_key text not null,
  fingerprint text not null,
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  owner_role text not null,
  status text not null default 'OPEN' check (status in ('OPEN','ACKNOWLEDGED','RESOLVED','SUPPRESSED')),
  summary text not null,
  affected_count bigint not null default 1 check (affected_count >= 0),
  occurrence_count bigint not null default 1 check (occurrence_count >= 1),
  first_seen_at timestamptz not null,
  last_seen_at timestamptz not null,
  acknowledged_at timestamptz,
  acknowledged_by text,
  resolved_at timestamptz,
  resolved_by text,
  source_ref text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists alert_instances_active_fingerprint_uq on ops.alert_instances(environment,fingerprint) where status in ('OPEN','ACKNOWLEDGED');
create index if not exists alert_instances_status_severity_idx on ops.alert_instances(environment,status,severity,last_seen_at desc);

create table if not exists ops.alert_occurrences (
  occurrence_pk uuid primary key default gen_random_uuid(),
  alert_pk uuid not null references ops.alert_instances(alert_pk) on delete cascade,
  observed_at timestamptz not null default now(),
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  affected_count bigint not null default 1,
  source_ref text,
  summary text not null,
  metadata jsonb not null default '{}'::jsonb
);
create index if not exists alert_occurrences_alert_time_idx on ops.alert_occurrences(alert_pk,observed_at desc);

create table if not exists ops.incidents (
  incident_pk uuid primary key default gen_random_uuid(),
  environment text not null check (environment in ('TEST','PROD')),
  alert_pk uuid not null references ops.alert_instances(alert_pk),
  severity text not null check (severity in ('SEV0','SEV1','SEV2','SEV3')),
  status text not null default 'OPEN' check (status in ('OPEN','ACKNOWLEDGED','CONTAINED','RECOVERING','RESOLVED','CLOSED')),
  owner_role text not null,
  owner_identity_ref text,
  title text not null,
  declared_at timestamptz not null default now(),
  ack_due_at timestamptz,
  acknowledged_at timestamptz,
  contained_at timestamptz,
  resolved_at timestamptz,
  closed_at timestamptz,
  evidence_ref text,
  root_cause text,
  corrective_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists incidents_active_alert_uq on ops.incidents(alert_pk) where status <> 'CLOSED';
create index if not exists incidents_status_severity_idx on ops.incidents(environment,status,severity,declared_at desc);

create table if not exists ops.incident_timeline (
  timeline_pk uuid primary key default gen_random_uuid(),
  incident_pk uuid not null references ops.incidents(incident_pk) on delete cascade,
  occurred_at timestamptz not null default now(),
  action_type text not null,
  actor_ref text not null,
  summary text not null,
  evidence_ref text,
  metadata jsonb not null default '{}'::jsonb
);
create index if not exists incident_timeline_incident_time_idx on ops.incident_timeline(incident_pk,occurred_at);

create table if not exists ops.alert_delivery_queue (
  delivery_pk uuid primary key default gen_random_uuid(),
  alert_pk uuid not null references ops.alert_instances(alert_pk) on delete cascade,
  route_pk uuid references ops.alert_routes(route_pk),
  delivery_status text not null default 'HELD' check (delivery_status in ('HELD','READY','SENT','FAILED','CANCELLED')),
  hold_reason text,
  attempt_count integer not null default 0,
  last_attempt_at timestamptz,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists alert_delivery_queue_alert_route_uq on ops.alert_delivery_queue(alert_pk,route_pk) where route_pk is not null;

insert into config.system_settings(setting_key,setting_value,description,source_ref) values
 ('security_observability_foundation_ready','false'::jsonb,'Part 5C observability/incident foundation acceptance state','PART5C'),
 ('security_external_alert_delivery_enabled','false'::jsonb,'External alert delivery remains disabled until real owner/channel verification','PART5C')
on conflict (setting_key) do update set description=excluded.description,source_ref=excluded.source_ref,updated_at=now();