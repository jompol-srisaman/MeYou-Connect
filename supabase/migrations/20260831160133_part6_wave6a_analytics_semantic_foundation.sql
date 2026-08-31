create schema if not exists analytics;

create table if not exists analytics.kpi_catalog (
  kpi_id text primary key,
  domain text not null,
  kpi_name text not null,
  kpi_class text not null,
  definition text not null,
  numerator text,
  denominator text,
  time_grain text not null,
  primary_source text not null,
  required_fields text,
  eligibility_filter text,
  result_type text not null,
  not_ready_rule text not null,
  owner_role text not null,
  dashboard text not null,
  priority text not null check (priority in ('P0','P1','P2','P3')),
  active boolean not null default true,
  source_ref text not null default 'MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists analytics.semantic_rules (
  rule_id text primary key,
  rule_name text not null,
  required_behavior text not null,
  example text,
  source_ref text not null default 'MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1',
  created_at timestamptz not null default now()
);

create table if not exists analytics.dq_gate_catalog (
  gate_id text primary key,
  kpi_domain text not null,
  check_description text not null,
  severity_if_fail text not null,
  behavior_if_fail text not null,
  owner_role text not null,
  architecture_status text not null,
  source_ref text not null default 'MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists analytics.acceptance_catalog (
  test_id text primary key,
  scenario text not null,
  expected_behavior text not null,
  critical boolean not null default true,
  status text not null default 'NOT_RUN' check (status in ('NOT_RUN','PASS','FAIL','BLOCKED')),
  evidence_ref text,
  last_tested_at timestamptz,
  source_ref text not null default 'MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists analytics.dim_date (
  calendar_date date primary key,
  year_no integer not null,
  quarter_no integer not null check (quarter_no between 1 and 4),
  month_no integer not null check (month_no between 1 and 12),
  month_start date not null,
  week_start date not null,
  iso_week integer not null,
  day_of_week integer not null check (day_of_week between 1 and 7),
  reporting_timezone text not null default 'Asia/Bangkok'
);

insert into analytics.dim_date(calendar_date,year_no,quarter_no,month_no,month_start,week_start,iso_week,day_of_week)
select d::date,
       extract(year from d)::int,
       extract(quarter from d)::int,
       extract(month from d)::int,
       date_trunc('month',d)::date,
       date_trunc('week',d)::date,
       extract(week from d)::int,
       extract(isodow from d)::int
from generate_series(date '2026-01-01',date '2030-12-31',interval '1 day') d
on conflict (calendar_date) do nothing;

create table if not exists analytics.stage_transition_fact (
  transition_pk uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id text not null,
  from_stage text,
  to_stage text not null,
  occurred_at timestamptz not null,
  source_event_pk uuid references ops.events(event_pk) on delete restrict,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  actor_service text not null,
  valid_transition boolean not null default true,
  source_kind text not null default 'EVENT' check (source_kind in ('EVENT','MIGRATION_VERIFIED','MANUAL_VERIFIED')),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint stage_transition_provenance_ck check (source_event_pk is not null or raw_input_id is not null or evidence_id is not null),
  constraint stage_transition_no_secret_keys_ck check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists stage_transition_entity_time_idx on analytics.stage_transition_fact(entity_type,entity_id,occurred_at);
create index if not exists stage_transition_to_stage_time_idx on analytics.stage_transition_fact(entity_type,to_stage,occurred_at);
create index if not exists stage_transition_event_idx on analytics.stage_transition_fact(source_event_pk);
create index if not exists stage_transition_raw_idx on analytics.stage_transition_fact(raw_input_id);
create index if not exists stage_transition_evidence_idx on analytics.stage_transition_fact(evidence_id);

create table if not exists analytics.placement_milestone_fact (
  milestone_fact_pk uuid primary key default gen_random_uuid(),
  placement_id text not null references core.placements(placement_id) on delete restrict,
  milestone text not null check (milestone in ('D7','D30','D90','D120')),
  outcome text not null check (outcome in ('ACTIVE','PASS','LEFT','DROPOUT','UNKNOWN','NOT_REACHED','CONTACT_FAILED','NEEDS_REVIEW')),
  observed_at timestamptz not null,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  source_followup_id text references core.followups(followup_id) on delete restrict,
  actor_service text not null,
  created_at timestamptz not null default now(),
  unique (placement_id,milestone,observed_at),
  constraint placement_milestone_provenance_ck check (evidence_id is not null or raw_input_id is not null or source_followup_id is not null)
);
create index if not exists placement_milestone_placement_idx on analytics.placement_milestone_fact(placement_id,milestone,observed_at desc);
create index if not exists placement_milestone_evidence_idx on analytics.placement_milestone_fact(evidence_id);
create index if not exists placement_milestone_raw_idx on analytics.placement_milestone_fact(raw_input_id);
create index if not exists placement_milestone_followup_idx on analytics.placement_milestone_fact(source_followup_id);

create table if not exists analytics.source_freshness (
  source_key text primary key,
  source_type text not null,
  last_source_at timestamptz,
  last_refresh_at timestamptz,
  freshness_window_minutes integer check (freshness_window_minutes is null or freshness_window_minutes > 0),
  readiness_status text not null default 'NOT_READY' check (readiness_status in ('READY','PARTIAL','NOT_READY','STALE','BLOCKED')),
  blocked_reason text,
  source_ref text,
  updated_at timestamptz not null default now()
);

insert into analytics.source_freshness(source_key,source_type,readiness_status,blocked_reason,source_ref)
values
('POSTGRES_OPERATIONAL_MASTER','POSTGRES','NOT_READY','PostgreSQL is TEST/shadow and is not the operational Source of Truth.','Part4/Part5 safety boundary'),
('GOOGLE_OPERATIONAL_MASTER','GOOGLE_SHEETS_DRIVE','PARTIAL','Current operational Source of Truth is outside PostgreSQL analytics runtime.','MEYOU_CONNECT_MVP_DATA_HUB_V1')
on conflict (source_key) do update set source_type=excluded.source_type,readiness_status=excluded.readiness_status,blocked_reason=excluded.blocked_reason,source_ref=excluded.source_ref,updated_at=now();

insert into authz.role_capabilities(role_key,capability_key)
values ('founder','analytics_read'),('secretary','analytics_read'),('data_audit','analytics_read')
on conflict do nothing;

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('analytics_business_source_ready','false'::jsonb,'PostgreSQL analytics business metrics must remain NOT_READY until operational-source cutover is approved.','Part6A'),
('analytics_postgres_publish_enabled','false'::jsonb,'Do not publish PostgreSQL business KPI as official while it is TEST/shadow.','Part6A'),
('analytics_materialization_enabled','false'::jsonb,'Use normal views first; materialization only after measured need.','Part6A'),
('analytics_foundation_ready','false'::jsonb,'Part 6A semantic foundation readiness flag.','Part6A'),
('part6a_foundation_closed','false'::jsonb,'Part 6A closeout flag.','Part6A')
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

alter table analytics.kpi_catalog enable row level security;
alter table analytics.semantic_rules enable row level security;
alter table analytics.dq_gate_catalog enable row level security;
alter table analytics.acceptance_catalog enable row level security;
alter table analytics.dim_date enable row level security;
alter table analytics.stage_transition_fact enable row level security;
alter table analytics.placement_milestone_fact enable row level security;
alter table analytics.source_freshness enable row level security;

revoke all on schema analytics from public,anon,authenticated;
revoke all on analytics.kpi_catalog,analytics.semantic_rules,analytics.dq_gate_catalog,analytics.acceptance_catalog,analytics.dim_date,analytics.stage_transition_fact,analytics.placement_milestone_fact,analytics.source_freshness from public,anon,authenticated;
grant usage on schema analytics to service_role;
grant select,insert,update,delete on analytics.kpi_catalog,analytics.semantic_rules,analytics.dq_gate_catalog,analytics.acceptance_catalog,analytics.dim_date,analytics.stage_transition_fact,analytics.placement_milestone_fact,analytics.source_freshness to service_role;