create table ops.part7f_acceptance_catalog(
  test_id text primary key,
  scenario text not null,
  expected_behavior text not null,
  status text not null default 'NOT_RUN' check(status in ('NOT_RUN','PASS','FAIL')),
  evidence_ref text,
  last_tested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into ops.part7f_acceptance_catalog(test_id,scenario,expected_behavior) values
('P7F-001','Evaluator records all canonical Production Portal gates','16 RESULTS'),
('P7F-002','TEST portal acceptance is preserved as technical evidence only','PASS_TEST'),
('P7F-003','Missing Part 5 PROD evidence keeps Production NOT_READY','NOT_READY'),
('P7F-004','Missing fresh independent backup/restore keeps Production NOT_READY','NOT_READY'),
('P7F-005','Missing verified Production support/rate-limit routes keeps Production NOT_READY','NOT_READY'),
('P7F-006','Evaluation does not enable Portal or feature flags','OFF')
on conflict(test_id) do nothing;
alter table ops.part7f_acceptance_catalog enable row level security;
create policy part7f_acceptance_external_deny on ops.part7f_acceptance_catalog as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.part7f_acceptance_catalog from public,anon,authenticated;
grant all on ops.part7f_acceptance_catalog to service_role;

do $smoke$
declare
  v_run uuid;
  v_status text;
  v_not_ready integer;
  v_results integer;
  v_flags integer;
  v_external boolean;
begin
  v_run:=ops.evaluate_portal_production_readiness('PART7F_SMOKE');
  select overall_status,not_ready_count into v_status,v_not_ready from ops.portal_production_readiness_runs where run_pk=v_run;
  if v_status<>'NOT_READY' then raise exception 'P7F_PRODUCTION_MUST_BE_NOT_READY:%',v_status; end if;
  select count(*) into v_results from ops.portal_production_gate_results where run_pk=v_run;
  if v_results<>16 then raise exception 'P7F_GATE_RESULT_COUNT_NOT_16:%',v_results; end if;
  if not exists(select 1 from ops.portal_production_gate_results where run_pk=v_run and gate_id='PPG-001' and status='PASS_TEST') then raise exception 'P7F_TEST_CROSS_ORG_EVIDENCE_NOT_PRESERVED'; end if;
  if not exists(select 1 from ops.portal_production_gate_results where run_pk=v_run and gate_id='PPG-013' and status='NOT_READY') then raise exception 'P7F_PART5_PROD_BLOCKER_NOT_ENFORCED'; end if;
  if not exists(select 1 from ops.portal_production_gate_results where run_pk=v_run and gate_id='PPG-014' and status='NOT_READY') then raise exception 'P7F_BACKUP_BLOCKER_NOT_ENFORCED'; end if;
  if not exists(select 1 from ops.portal_production_gate_results where run_pk=v_run and gate_id='PPG-010' and status='NOT_READY') then raise exception 'P7F_RATE_LIMIT_PROD_BLOCKER_NOT_ENFORCED'; end if;
  if not exists(select 1 from ops.portal_production_gate_results where run_pk=v_run and gate_id='PPG-011' and status='NOT_READY') then raise exception 'P7F_SUPPORT_ROUTE_BLOCKER_NOT_ENFORCED'; end if;
  if not exists(select 1 from ops.portal_production_gate_results where run_pk=v_run and gate_id='PPG-016' and status='NOT_READY') then raise exception 'P7F_APPROVAL_BLOCKER_NOT_ENFORCED'; end if;
  if v_not_ready<=0 then raise exception 'P7F_EXPECTED_NONZERO_BLOCKERS'; end if;
  select count(*) into v_flags from ops.portal_feature_flags where enabled;
  if v_flags<>0 then raise exception 'P7F_FEATURE_FLAGS_MUST_REMAIN_OFF'; end if;
  select coalesce((setting_value #>> '{}')::boolean,false) into v_external from config.system_settings where setting_key='portal_external_access_enabled';
  if v_external then raise exception 'P7F_EXTERNAL_PORTAL_MUST_REMAIN_OFF'; end if;
  if coalesce((select setting_value #>> '{}' from config.system_settings where setting_key='portal_production_readiness_status'),'')<>'NOT_READY' then raise exception 'P7F_PROD_STATUS_SETTING_MUST_BE_NOT_READY'; end if;
  update ops.part7f_acceptance_catalog set status='PASS',evidence_ref='part7_wave7f_portal_production_readiness_evaluation_smoke:'||v_run::text,last_tested_at=now(),updated_at=now();
end
$smoke$;