create or replace function ops.evaluate_province_scale_preflight()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_target text;
  v_target_exists boolean:=false;
  v_activation boolean:=false;
  v_readiness jsonb;
  v_signal jsonb;
begin
  select nullif(setting_value #>> '{}','') into v_target from config.system_settings where setting_key='province_scale_target_province_code';
  select coalesce((setting_value #>> '{}')::boolean,false) into v_activation from config.system_settings where setting_key='province_scale_activation_enabled';
  select setting_value into v_signal from config.system_settings where setting_key='province_scale_observed_demand_signal';

  if v_target is null then
    return jsonb_build_object(
      'status','TARGET_NOT_SELECTED',
      'target_province_code',null,
      'target_selected',false,
      'activation_master_enabled',coalesce(v_activation,false),
      'observed_demand_signal',coalesce(v_signal,'{}'::jsonb),
      'active_transition_ready',false,
      'reason','A demand signal is not an authorization to select or activate a province.'
    );
  end if;

  select exists(select 1 from geo.provinces where province_code=v_target and active=true) into v_target_exists;
  if not v_target_exists then
    return jsonb_build_object(
      'status','TARGET_MASTER_NOT_SEEDED',
      'target_province_code',v_target,
      'target_selected',true,
      'province_master_exists',false,
      'activation_master_enabled',coalesce(v_activation,false),
      'active_transition_ready',false
    );
  end if;

  v_readiness:=ops.province_scale_readiness(v_target);
  return jsonb_build_object(
    'status',case when coalesce((v_readiness->>'active_transition_ready')::boolean,false) then 'READY_FOR_ACTIVE_TRANSITION' else 'NOT_READY' end,
    'target_province_code',v_target,
    'target_selected',true,
    'province_master_exists',true,
    'activation_master_enabled',coalesce(v_activation,false),
    'scale_readiness',v_readiness,
    'active_transition_ready',coalesce((v_readiness->>'active_transition_ready')::boolean,false)
  );
end $$;
revoke all on function ops.evaluate_province_scale_preflight() from public,anon,authenticated;
grant execute on function ops.evaluate_province_scale_preflight() to service_role;

create table ops.part7g_acceptance_catalog(
  test_id text primary key,
  scenario text not null,
  expected_behavior text not null,
  status text not null default 'NOT_RUN' check(status in ('NOT_RUN','PASS','FAIL')),
  evidence_ref text,
  last_tested_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
insert into ops.part7g_acceptance_catalog(test_id,scenario,expected_behavior) values
('P7G-001','Observed demand signal does not automatically select a province','TARGET_NOT_SELECTED'),
('P7G-002','No Province/Service Area/Region Assignment is created without explicit target authorization','ZERO AUTO-CREATE'),
('P7G-003','No SG gate is marked READY without target-specific evidence','ZERO READY'),
('P7G-004','Province ACTIVE master switch remains disabled','OFF'),
('P7G-005','Missing province target cannot be advanced through lifecycle','DENY'),
('P7G-006','Operational Source remains Google Sheets/Drive','UNCHANGED')
on conflict(test_id) do nothing;
alter table ops.part7g_acceptance_catalog enable row level security;
create policy part7g_acceptance_external_deny on ops.part7g_acceptance_catalog as restrictive for all to anon,authenticated using(false) with check(false);
revoke all on ops.part7g_acceptance_catalog from public,anon,authenticated;
grant all on ops.part7g_acceptance_catalog to service_role;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
('province_scale_observed_demand_signal',jsonb_build_object('province_name_th','พระนครศรีอยุธยา','area','บางปะอิน','job_id','MYC-J-000015','classification','DEMAND_SIGNAL_ONLY','authorizes_target',false),'Observed operational demand signal from Google Data Hub. This is not Founder target-province authorization and must not create geography/lifecycle rows.','Google Data Hub 1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc / 02_งาน_Job',now()),
('province_scale_target_status','"TARGET_NOT_SELECTED"'::jsonb,'No target province has been explicitly selected for S10. Demand signal alone is insufficient.','Part7G',now()),
('province_scale_readiness_status','"NOT_READY"'::jsonb,'Province scale remains NOT_READY until a target is explicitly selected and SG-01..SG-09 receive target-specific evidence.','Part7G',now()),
('part7g_foundation_closed','false'::jsonb,'Part 7G S10 preflight acceptance not yet closed.','Part7G',now())
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;