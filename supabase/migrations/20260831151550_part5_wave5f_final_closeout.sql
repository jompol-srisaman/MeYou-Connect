insert into ops.security_evidence_records(evidence_key,environment,control_id,gate_id,evidence_type,status,source_type,source_ref,summary,details,recorded_by)
values('part5f_change_reliability_acceptance','TEST','SEC-012',null,'ACCEPTANCE_TEST','PASS','SUPABASE_MIGRATION','part5_wave5f_change_reliability_smoke','Change reliability acceptance passed: standard and high-risk TEST changes require complete evidence; PROD critical change remains blocked by global Production readiness.','{}'::jsonb,'PART5F_CLOSEOUT');

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('part5f_foundation_closed','true'::jsonb,'Part 5F change reliability and closeout foundation closed in TEST.','Part5F'),
('part5_test_foundation_status','"CLOSED"'::jsonb,'Part 5 implementation foundation is closed in TEST.','Part5F'),
('part5_production_readiness_status','"NOT_READY"'::jsonb,'Production remains blocked until all Production security gates pass and explicit approval exists.','Part5F')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

select ops.evaluate_security_gates('TEST','PART5F_CLOSEOUT');
select ops.evaluate_security_gates('PROD','PART5F_CLOSEOUT');
select ops.evaluate_part5_closeout('PART5F_CLOSEOUT');