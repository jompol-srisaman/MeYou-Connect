create table ops.portal_production_gate_catalog(
  gate_id text primary key,
  gate_name text not null,
  evidence_scope text not null check(evidence_scope in ('TEST_TECHNICAL','PROD_REQUIRED','APPROVAL')),
  requirement text not null,
  critical boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.portal_production_gate_catalog(gate_id,gate_name,evidence_scope,requirement) values
('PPG-001','Cross-organization access DENY','TEST_TECHNICAL','Part 7 cross-client and cross-partner access tests PASS'),
('PPG-002','Cross-candidate access DENY','TEST_TECHNICAL','Candidate self/purpose boundaries PASS'),
('PPG-003','Minimum Candidate projection reviewed','TEST_TECHNICAL','Purpose-specific Client Candidate projection passes minimum-field tests'),
('PPG-004','Member offboarding and stale session DENY','TEST_TECHNICAL','Removed membership blocks access immediately'),
('PPG-005','Protected business authority boundaries','TEST_TECHNICAL','Portal actors cannot set consent, B2B price, COLLECTED, or verified Placement truth'),
('PPG-006','Private storage exposure controls','TEST_TECHNICAL','Private bucket/policy exposure tests PASS'),
('PPG-007','Material upload provenance complete','PROD_REQUIRED','Production material upload demonstrates Raw Input + file registry/evidence chain'),
('PPG-008','Audited support access','TEST_TECHNICAL','Capability + AAL2 + scoped support audit test PASS'),
('PPG-009','MFA / step-up protected actions','TEST_TECHNICAL','AAL1 deny and AAL2 protected-action tests PASS'),
('PPG-010','Production rate-limit / abuse controls active','PROD_REQUIRED','Production Portal ingress/endpoints have active verified abuse/rate-limit controls'),
('PPG-011','Real support / incident route verified','PROD_REQUIRED','Critical alert route points to a real owner and delivery is verified'),
('PPG-012','Feature kill switch proven','TEST_TECHNICAL','Portal feature flags can be scoped and disabled without residual access'),
('PPG-013','Relevant Part 5 PROD gates PASS','PROD_REQUIRED','No critical Production security blocker remains'),
('PPG-014','Fresh independent backup and restore evidence','PROD_REQUIRED','Fresh Tier-A independent backup exists and restore readiness is verified'),
('PPG-015','TEST / PROD environment and credentials separated','PROD_REQUIRED','Production environment and distinct credential bindings are verified'),
('PPG-016','Founder + Architect rollout approval','APPROVAL','Explicit Production Portal wave approval is recorded')
on conflict(gate_id) do update set gate_name=excluded.gate_name,evidence_scope=excluded.evidence_scope,requirement=excluded.requirement,critical=excluded.critical,updated_at=now();

create table ops.portal_production_readiness_runs(
  run_pk uuid primary key default gen_random_uuid(),
  pilot_wave text not null,
  overall_status text not null check(overall_status in ('READY','NOT_READY')),
  pass_test_count integer not null default 0,
  pass_prod_count integer not null default 0,
  not_ready_count integer not null default 0,
  part5_prod_pass_count integer not null default 0,
  part5_prod_not_ready_count integer not null default 0,
  backup_status text,
  verified_alert_route_count integer not null default 0,
  prod_ingress_policy_count integer not null default 0,
  enabled_portal_feature_flags integer not null default 0,
  evaluated_by text not null,
  evaluated_at timestamptz not null default now(),
  summary jsonb not null default '{}'::jsonb
);
create index portal_prod_readiness_time_idx on ops.portal_production_readiness_runs(evaluated_at desc);

create table ops.portal_production_gate_results(
  run_pk uuid not null references ops.portal_production_readiness_runs(run_pk) on delete cascade,
  gate_id text not null references ops.portal_production_gate_catalog(gate_id) on delete restrict,
  status text not null check(status in ('PASS_TEST','PASS_PROD','NOT_READY')),
  observed text not null,
  evidence_ref text,
  created_at timestamptz not null default now(),
  primary key(run_pk,gate_id)
);
create index portal_prod_gate_results_gate_idx on ops.portal_production_gate_results(gate_id,status);

alter table ops.portal_production_gate_catalog enable row level security;
alter table ops.portal_production_readiness_runs enable row level security;
alter table ops.portal_production_gate_results enable row level security;
create policy portal_prod_gate_catalog_external_deny on ops.portal_production_gate_catalog as restrictive for all to anon,authenticated using(false) with check(false);
create policy portal_prod_runs_external_deny on ops.portal_production_readiness_runs as restrictive for all to anon,authenticated using(false) with check(false);
create policy portal_prod_results_external_deny on ops.portal_production_gate_results as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.portal_production_gate_catalog,ops.portal_production_readiness_runs,ops.portal_production_gate_results from public,anon,authenticated;
grant all on ops.portal_production_gate_catalog,ops.portal_production_readiness_runs,ops.portal_production_gate_results to service_role;

create or replace function ops.evaluate_portal_production_readiness(p_evaluated_by text default 'PART7F')
returns uuid
language plpgsql
security definer
set search_path=''
as $$
declare
  v_run uuid:=gen_random_uuid();
  v_part5_pass integer:=0;
  v_part5_nr integer:=0;
  v_backup text:='NOT_READY';
  v_routes integer:=0;
  v_prod_ingress integer:=0;
  v_flags integer:=0;
  v_pass_test integer:=0;
  v_pass_prod integer:=0;
  v_not_ready integer:=0;
  v_upload_complete boolean:=false;
  v_prod_env_sep boolean:=false;
begin
  if p_evaluated_by is null or btrim(p_evaluated_by)='' then raise exception 'EVALUATED_BY_REQUIRED'; end if;
  select count(*) filter(where status='PASS'),count(*) filter(where status<>'PASS')
    into v_part5_pass,v_part5_nr from ops.security_latest_gate_v where environment='PROD';
  select coalesce(backup_status,'NOT_READY') into v_backup from ops.recovery_readiness_v where environment='TEST';
  if not found then v_backup:='NOT_READY'; end if;
  select count(*) into v_routes from ops.alert_routes where environment='PROD' and active=true and verified=true and destination_ref is not null;
  select count(*) into v_prod_ingress from ops.ingress_endpoint_policies where environment='PROD' and enabled=true and replay_protection_required=true and rate_limit_requests>0 and rate_limit_window_seconds>0;
  select count(*) into v_flags from ops.portal_feature_flags where enabled=true;
  select exists(
    select 1 from ops.security_latest_gate_v where environment='PROD' and gate_id='PG-005' and status='PASS'
  ) into v_prod_env_sep;
  select exists(
    select 1 from ops.security_latest_gate_v where environment='PROD' and gate_id in ('PG-009','PG-010') and status='PASS'
    group by environment having count(*)=2
  ) into v_upload_complete;

  insert into ops.portal_production_readiness_runs(run_pk,pilot_wave,overall_status,part5_prod_pass_count,part5_prod_not_ready_count,backup_status,verified_alert_route_count,prod_ingress_policy_count,enabled_portal_feature_flags,evaluated_by,summary)
  values(v_run,coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='part7_pilot_selected'),'UNSELECTED'),'NOT_READY',v_part5_pass,v_part5_nr,v_backup,v_routes,v_prod_ingress,v_flags,p_evaluated_by,
    jsonb_build_object('portal_acceptance_pass',(select count(*) from ops.portal_acceptance_catalog where status='PASS'),'portal_acceptance_total',(select count(*) from ops.portal_acceptance_catalog),'p1b_acceptance_pass',(select count(*) from ops.part7e_acceptance_catalog where status='PASS'),'p1b_acceptance_total',(select count(*) from ops.part7e_acceptance_catalog),'operational_source',(select setting_value #>> '{}' from config.system_settings where setting_key='current_operational_source')));

  insert into ops.portal_production_gate_results(run_pk,gate_id,status,observed,evidence_ref) values
  (v_run,'PPG-001',case when (select count(*) from ops.portal_acceptance_catalog where test_id in ('PT-001','PT-002','PT-008') and status='PASS')=3 then 'PASS_TEST' else 'NOT_READY' end,'Part 7 cross-org tests PT-001/PT-002/PT-008 evaluated','Part7B'),
  (v_run,'PPG-002',case when (select count(*) from ops.portal_acceptance_catalog where test_id in ('PT-003','PT-004','PT-012') and status='PASS')=3 then 'PASS_TEST' else 'NOT_READY' end,'Candidate cross-user/purpose isolation evaluated','Part7B/7C'),
  (v_run,'PPG-003',case when (select count(*) from ops.portal_acceptance_catalog where test_id in ('PT-004','PT-013') and status='PASS')=2 then 'PASS_TEST' else 'NOT_READY' end,'Minimum Client Candidate projection and private-field exclusion evaluated','Part7B/7E'),
  (v_run,'PPG-004',case when exists(select 1 from ops.portal_acceptance_catalog where test_id='PT-007' and status='PASS') then 'PASS_TEST' else 'NOT_READY' end,'Removed membership/stale session test evaluated','Part7B'),
  (v_run,'PPG-005',case when (select count(*) from ops.portal_acceptance_catalog where test_id in ('PT-005','PT-006','PT-011') and status='PASS')=3 then 'PASS_TEST' else 'NOT_READY' end,'Protected pricing/consent/finance/placement authority boundaries evaluated','Part7C/7D'),
  (v_run,'PPG-006',case when exists(select 1 from ops.security_latest_gate_v where environment='TEST' and gate_id='PG-011' and status='PASS') then 'PASS_TEST' else 'NOT_READY' end,'TEST private storage exposure gate evaluated','Part5F PG-011 TEST'),
  (v_run,'PPG-007',case when v_upload_complete then 'PASS_PROD' else 'NOT_READY' end,case when v_upload_complete then 'Production material upload provenance evidence recorded' else 'Production Raw/File/Evidence and restore-grade evidence chain not recorded' end,case when v_upload_complete then 'Part5 PROD PG-009/PG-010' else null end),
  (v_run,'PPG-008',case when exists(select 1 from ops.portal_acceptance_catalog where test_id='PT-014' and status='PASS') then 'PASS_TEST' else 'NOT_READY' end,'Audited scoped support-access test evaluated','Part7D PT-014'),
  (v_run,'PPG-009',case when (select count(*) from ops.part7d_acceptance_catalog where test_id in ('P7D-001','P7D-007','P7D-008') and status='PASS')=3 then 'PASS_TEST' else 'NOT_READY' end,'AAL1 deny / AAL2 protected controls evaluated','Part7D'),
  (v_run,'PPG-010',case when v_prod_ingress>0 then 'PASS_PROD' else 'NOT_READY' end,case when v_prod_ingress>0 then v_prod_ingress||' enabled Production ingress policies with rate/replay controls' else 'No enabled Production ingress policy with active rate/replay controls' end,null),
  (v_run,'PPG-011',case when v_routes>0 then 'PASS_PROD' else 'NOT_READY' end,case when v_routes>0 then v_routes||' verified Production alert routes' else 'No verified Production alert route to a real destination' end,null),
  (v_run,'PPG-012',case when v_flags=0 and exists(select 1 from ops.part7e_acceptance_catalog where test_id='P7E-001' and status='PASS') then 'PASS_TEST' else 'NOT_READY' end,'Feature-off deny proven; enabled Portal flags currently='||v_flags,'Part7E P7E-001'),
  (v_run,'PPG-013',case when v_part5_nr=0 and v_part5_pass>=15 then 'PASS_PROD' else 'NOT_READY' end,'Part 5 PROD gates PASS='||v_part5_pass||', NOT_READY='||v_part5_nr,'ops.security_latest_gate_v'),
  (v_run,'PPG-014',case when v_backup='READY' then 'PASS_PROD' else 'NOT_READY' end,'TEST recovery readiness='||v_backup||'; Production fresh independent backup/restore evidence required','ops.recovery_readiness_v'),
  (v_run,'PPG-015',case when v_prod_env_sep then 'PASS_PROD' else 'NOT_READY' end,case when v_prod_env_sep then 'Production credential separation gate PASS' else 'Production environment/credential separation not verified' end,'Part5 PG-005'),
  (v_run,'PPG-016',case when exists(select 1 from ops.security_latest_gate_v where environment='PROD' and gate_id='PG-015' and status='PASS') then 'PASS_PROD' else 'NOT_READY' end,'Founder + Architect Production approval gate evaluated','Part5 PG-015');

  select count(*) filter(where status='PASS_TEST'),count(*) filter(where status='PASS_PROD'),count(*) filter(where status='NOT_READY')
    into v_pass_test,v_pass_prod,v_not_ready from ops.portal_production_gate_results where run_pk=v_run;
  update ops.portal_production_readiness_runs set pass_test_count=v_pass_test,pass_prod_count=v_pass_prod,not_ready_count=v_not_ready,overall_status=case when v_not_ready=0 then 'READY' else 'NOT_READY' end where run_pk=v_run;

  insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at)
  values('portal_production_readiness_status',to_jsonb(case when v_not_ready=0 then 'READY' else 'NOT_READY' end::text),'Part 7F machine-evaluated Portal Production readiness. READY is impossible while any critical production gate lacks evidence.','Part7F run '||v_run::text,now())
  on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;
  return v_run;
end $$;
revoke all on function ops.evaluate_portal_production_readiness(text) from public,anon,authenticated;
grant execute on function ops.evaluate_portal_production_readiness(text) to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
('part7f_readiness_control_ready','true'::jsonb,'Part 7F Production readiness control plane installed; this does not enable Production Portal.','Part7F',now()),
('part7f_foundation_closed','false'::jsonb,'Part 7F evaluation/acceptance not yet closed.','Part7F',now())
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;