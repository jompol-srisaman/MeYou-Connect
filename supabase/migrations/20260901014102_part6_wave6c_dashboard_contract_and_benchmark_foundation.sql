create table if not exists analytics.dashboard_pages (
  page_key text primary key,
  page_name text not null unique,
  audience text not null,
  top_row text not null,
  sections text not null,
  default_filters text not null,
  drillthrough_contract text not null,
  freshness_contract text not null,
  page_rule text not null,
  required_capability text not null,
  performance_target_ms integer check (performance_target_ms is null or performance_target_ms > 0),
  active boolean not null default true,
  source_ref text not null default 'MEYOU_CONNECT_ANALYTICS_KPI_CATALOG_V1/04_Dashboard_Pages',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists analytics.dashboard_kpi_map (
  page_key text not null references analytics.dashboard_pages(page_key) on delete restrict,
  kpi_id text not null references analytics.kpi_catalog(kpi_id) on delete restrict,
  display_order integer not null check (display_order > 0),
  section_name text not null,
  primary_metric boolean not null default false,
  created_at timestamptz not null default now(),
  primary key(page_key,kpi_id)
);
create index if not exists dashboard_kpi_map_kpi_idx on analytics.dashboard_kpi_map(kpi_id,page_key);

create table if not exists analytics.query_benchmark_samples (
  benchmark_pk uuid primary key default gen_random_uuid(),
  surface_key text not null,
  query_key text not null,
  measured_at timestamptz not null default clock_timestamp(),
  duration_ms numeric(14,4) not null check (duration_ms >= 0),
  row_count bigint,
  test_mode boolean not null default true,
  source_state text not null,
  measured_by text not null,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists query_benchmark_surface_time_idx on analytics.query_benchmark_samples(surface_key,measured_at desc);

create table if not exists analytics.materialization_decisions (
  surface_key text primary key,
  decision text not null check (decision in ('KEEP_NORMAL_VIEW','RECOMMEND_MATERIALIZATION','MATERIALIZED','NOT_ENOUGH_DATA')),
  p95_ms numeric(14,4),
  threshold_ms integer,
  sample_count integer not null default 0 check (sample_count >= 0),
  rationale text not null,
  semantic_hash_before text,
  semantic_hash_after text,
  materialized_object text,
  evaluated_at timestamptz not null default now(),
  evaluated_by text not null,
  source_ref text not null default 'Part6C'
);

insert into analytics.dashboard_pages(page_key,page_name,audience,top_row,sections,default_filters,drillthrough_contract,freshness_contract,page_rule,required_capability,performance_target_ms)
values
('FOUNDER_DAILY','Founder Daily','Founder','Cash Balance / Collected / AR / Commission Payable / Critical Alerts','Client Demand; Placement Starts; Candidate Actions; DQ/Automation; Next Actions','Today + as-of','Entity/Evidence/Task','Live/as-of visible','Cash/Client/Placement before vanity metrics','founder_dashboard_read',5000),
('FOUNDER_WEEKLY','Founder Weekly','Founder','Qualified / Appointments / Starts / D7 / Collected','Candidate Funnel; Client Pipeline; Partner; Retention; Collection; Risks; Priorities','Last 7d + cohort','Candidate/Job/Placement/Client/Partner','Daily/live','Do not show rate without ready denominator','founder_dashboard_read',5000),
('FOUNDER_MONTHLY','Founder Monthly','Founder','Collected / Contribution / Cash / AR','P&L; Funnel; Retention; Repeat Client; Source/Partner; Bottlenecks; Automation','Month','Finance/entity drill','Month closed/provisional badge','Accounting reports from journal','founder_dashboard_read',5000),
('CANDIDATE_OPS','Candidate Ops','Candidate Ops','Due Followups / Appointments / Starts / No-show','Candidate queue; readiness; placements; retention exceptions','Today/7d','Candidate/Placement/Evidence','Near-live','PII only as required','candidate_ops_dashboard_read',null),
('CLIENT_SALES','Client & Sales','Client Sales','Active Demand / Headcount / Starts / AR risk','CRM; Job Demand; Fill; Client conversion; repeat','Active clients/jobs','Client/Job/Placement','Near-live','No candidate sensitive fields by default','client_sales_dashboard_read',null),
('FINANCE','Finance','Finance','Collected / AR / AP / Payable / Cash','Revenue lifecycle; invoices; collections; commission; journal health','Current month/as-of','Revenue/AR/AP/Evidence/Journal','Near-live + close state','COLLECTED only evidence-backed','finance_dashboard_read',null),
('PARTNER_REVIEW','Partner Review','Founder/Sales','Leads / Starts / D7 / Collected','Attribution; funnel; data completeness; no-show','Partner + period','Partner→Candidate/Placement','Daily','Attribution conflict excluded/flagged','partner_dashboard_read',null),
('DATA_QUALITY','Data Quality','Data Audit','Critical DQ / Raw Backlog / Missing Files / DLQ','Completeness; conflicts; stale data; orphan links; automation errors','Severity/status','DQ→Raw/Evidence/Entity/Event','Near-live','Quality blocks downstream KPI when material','dq_dashboard_read',null)
on conflict (page_key) do update set
 page_name=excluded.page_name,audience=excluded.audience,top_row=excluded.top_row,sections=excluded.sections,
 default_filters=excluded.default_filters,drillthrough_contract=excluded.drillthrough_contract,freshness_contract=excluded.freshness_contract,
 page_rule=excluded.page_rule,required_capability=excluded.required_capability,performance_target_ms=excluded.performance_target_ms,updated_at=now();

insert into analytics.dashboard_kpi_map(page_key,kpi_id,display_order,section_name,primary_metric)
values
('FOUNDER_DAILY','KPI-FIN-008',1,'TOP',true),('FOUNDER_DAILY','KPI-FIN-004',2,'TOP',true),('FOUNDER_DAILY','KPI-FIN-005',3,'TOP',true),('FOUNDER_DAILY','KPI-FIN-006',4,'TOP',true),('FOUNDER_DAILY','KPI-CLI-002',5,'CLIENT_DEMAND',false),('FOUNDER_DAILY','KPI-CLI-003',6,'CLIENT_DEMAND',false),('FOUNDER_DAILY','KPI-CAN-007',7,'PLACEMENT_STARTS',false),('FOUNDER_DAILY','KPI-OPS-001',8,'CANDIDATE_ACTIONS',false),('FOUNDER_DAILY','KPI-DQ-001',9,'DQ_AUTOMATION',false),('FOUNDER_DAILY','KPI-DQ-002',10,'DQ_AUTOMATION',false),('FOUNDER_DAILY','KPI-OPS-002',11,'DQ_AUTOMATION',false),
('FOUNDER_WEEKLY','KPI-CAN-002',1,'TOP',true),('FOUNDER_WEEKLY','KPI-CAN-004',2,'TOP',true),('FOUNDER_WEEKLY','KPI-CAN-007',3,'TOP',true),('FOUNDER_WEEKLY','KPI-RET-001',4,'TOP',true),('FOUNDER_WEEKLY','KPI-FIN-004',5,'TOP',true),('FOUNDER_WEEKLY','KPI-CAN-003',6,'FUNNEL',false),('FOUNDER_WEEKLY','KPI-CAN-005',7,'FUNNEL',false),('FOUNDER_WEEKLY','KPI-CAN-006',8,'FUNNEL',false),('FOUNDER_WEEKLY','KPI-CLI-004',9,'CLIENT',false),('FOUNDER_WEEKLY','KPI-PAR-003',10,'PARTNER',false),
('FOUNDER_MONTHLY','KPI-FIN-004',1,'TOP',true),('FOUNDER_MONTHLY','KPI-FIN-007',2,'TOP',true),('FOUNDER_MONTHLY','KPI-FIN-008',3,'TOP',true),('FOUNDER_MONTHLY','KPI-FIN-005',4,'TOP',true),('FOUNDER_MONTHLY','KPI-CAN-003',5,'FUNNEL',false),('FOUNDER_MONTHLY','KPI-RET-002',6,'RETENTION',false),('FOUNDER_MONTHLY','KPI-CLI-004',7,'CLIENT',false),('FOUNDER_MONTHLY','KPI-PAR-003',8,'PARTNER',false),
('CANDIDATE_OPS','KPI-OPS-001',1,'TOP',true),('CANDIDATE_OPS','KPI-CAN-004',2,'TOP',true),('CANDIDATE_OPS','KPI-CAN-007',3,'TOP',true),('CANDIDATE_OPS','KPI-CAN-006',4,'TOP',true),('CANDIDATE_OPS','KPI-RET-001',5,'RETENTION',false),('CANDIDATE_OPS','KPI-RET-002',6,'RETENTION',false),
('CLIENT_SALES','KPI-CLI-001',1,'TOP',true),('CLIENT_SALES','KPI-CLI-002',2,'TOP',true),('CLIENT_SALES','KPI-CLI-003',3,'TOP',true),('CLIENT_SALES','KPI-CAN-007',4,'TOP',true),('CLIENT_SALES','KPI-FIN-005',5,'AR_RISK',false),('CLIENT_SALES','KPI-CLI-004',6,'FILL',false),('CLIENT_SALES','KPI-CLI-005',7,'FILL',false),
('FINANCE','KPI-FIN-004',1,'TOP',true),('FINANCE','KPI-FIN-005',2,'TOP',true),('FINANCE','KPI-FIN-006',3,'TOP',true),('FINANCE','KPI-FIN-008',4,'TOP',true),('FINANCE','KPI-FIN-001',5,'REVENUE_LIFECYCLE',false),('FINANCE','KPI-FIN-002',6,'REVENUE_LIFECYCLE',false),('FINANCE','KPI-FIN-003',7,'REVENUE_LIFECYCLE',false),('FINANCE','KPI-FIN-007',8,'ACCOUNTING',false),
('PARTNER_REVIEW','KPI-PAR-001',1,'TOP',true),('PARTNER_REVIEW','KPI-PAR-002',2,'TOP',true),('PARTNER_REVIEW','KPI-PAR-003',3,'TOP',true),('PARTNER_REVIEW','KPI-PAR-004',4,'DATA_QUALITY',false),('PARTNER_REVIEW','KPI-RET-001',5,'RETENTION',false),
('DATA_QUALITY','KPI-DQ-001',1,'TOP',true),('DATA_QUALITY','KPI-DQ-002',2,'TOP',true),('DATA_QUALITY','KPI-OPS-002',3,'TOP',true)
on conflict (page_key,kpi_id) do update set display_order=excluded.display_order,section_name=excluded.section_name,primary_metric=excluded.primary_metric;

insert into authz.role_capabilities(role_key,capability_key) values
('founder','founder_dashboard_read'),('founder','candidate_ops_dashboard_read'),('founder','client_sales_dashboard_read'),('founder','finance_dashboard_read'),('founder','partner_dashboard_read'),('founder','dq_dashboard_read'),
('secretary','founder_dashboard_read'),('secretary','candidate_ops_dashboard_read'),('secretary','client_sales_dashboard_read'),('secretary','finance_dashboard_read'),('secretary','dq_dashboard_read'),
('candidate_ops','candidate_ops_dashboard_read'),
('client_sales','client_sales_dashboard_read'),('client_sales','partner_dashboard_read'),
('finance_control','finance_dashboard_read'),
('data_audit','founder_dashboard_read'),('data_audit','candidate_ops_dashboard_read'),('data_audit','client_sales_dashboard_read'),('data_audit','finance_dashboard_read'),('data_audit','partner_dashboard_read'),('data_audit','dq_dashboard_read')
on conflict do nothing;

insert into config.system_settings(setting_key,setting_value,description,source_ref) values
('analytics_dashboard_surfaces_ready','false'::jsonb,'Part 6C role dashboard semantic surfaces readiness.','Part6C'),
('analytics_query_benchmark_ready','false'::jsonb,'Part 6C query benchmark completion flag.','Part6C'),
('analytics_materialization_recommended','false'::jsonb,'Measured materialization recommendation; does not enable materialization.','Part6C'),
('part6c_foundation_closed','false'::jsonb,'Part 6C closeout flag.','Part6C')
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

alter table analytics.dashboard_pages enable row level security;
alter table analytics.dashboard_kpi_map enable row level security;
alter table analytics.query_benchmark_samples enable row level security;
alter table analytics.materialization_decisions enable row level security;

do $p$
declare t text;
begin
 foreach t in array array['dashboard_pages','dashboard_kpi_map','query_benchmark_samples','materialization_decisions'] loop
   execute format('drop policy if exists %I on analytics.%I','deny_client_'||t,t);
   execute format('create policy %I on analytics.%I as restrictive for all to anon,authenticated using (false) with check (false)','deny_client_'||t,t);
 end loop;
end $p$;

revoke all on analytics.dashboard_pages,analytics.dashboard_kpi_map,analytics.query_benchmark_samples,analytics.materialization_decisions from public,anon,authenticated;
grant select,insert,update,delete on analytics.dashboard_pages,analytics.dashboard_kpi_map,analytics.query_benchmark_samples,analytics.materialization_decisions to service_role;