select ops.record_security_evidence(
  'fresh_backup','TEST','BACKUP_READINESS','NOT_READY','SYSTEM','PART5_WAVE5D',
  'Part 5D found same-account Google rollback snapshots, but no verified independent PostgreSQL/Supabase backup artifact for the current TEST implementation.','PART5D',
  null,'PG-009',jsonb_build_object('google_latest_run','MYC-BK-000007','google_backup_class','SAME_ACCOUNT_ROLLBACK_ONLY','postgres_independent_backup_verified',false),now(),null
);
select ops.record_security_evidence(
  'restore_test','TEST','RESTORE_READINESS','NOT_READY','SYSTEM','PART5_WAVE5D',
  'Existing Google restore test MYC-RT-000001 passed Control Index + Data Hub structure, but full acceptance sample and PostgreSQL restore are not yet proven.','PART5D',
  null,'PG-010',jsonb_build_object('existing_restore_test','MYC-RT-000001','canonical_doc_sample',true,'data_hub_27_tabs',true,'candidate_sample',false,'placement_sample',false,'finance_evidence_sample',false,'postgres_restore_verified',false),now(),null
);
select ops.record_security_evidence(
  'part5d_backup_restore_engine','TEST','ACCEPTANCE_TEST','PASS','MIGRATION','part5_wave5d_backup_restore_smoke',
  'Synthetic independent-backup and full restore acceptance path passed transactionally and test records were removed.','PART5D',
  null,null,jsonb_build_object('synthetic_only',true,'used_for_production_gate',false),now(),null
);

select ops.capture_recovery_snapshot('TEST',now());
update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key in ('security_recovery_foundation_ready','part5d_foundation_closed');
update config.system_settings set setting_value='false'::jsonb,updated_at=now() where setting_key in ('security_backup_automation_enabled','security_restore_automation_enabled','production_cutover_approved');
select ops.evaluate_security_gates('TEST','PART5D_CLOSEOUT');
select ops.evaluate_security_gates('PROD','PART5D_CLOSEOUT');