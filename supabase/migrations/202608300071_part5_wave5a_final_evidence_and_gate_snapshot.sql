select ops.record_security_evidence(
  'rls_allow_tests','TEST','AUTOMATED_TEST','PASS','MIGRATION','part5_wave5a_security_control_plane_smoke',
  'Part 5A role-scoped ALLOW paths passed with synthetic authenticated identities and rolled back cleanly.',
  'part5a-closeout',null,'PG-001',jsonb_build_object('scope','TEST','synthetic_users_cleaned',true),now(),null
);

select ops.record_security_evidence(
  'rls_deny_tests','TEST','AUTOMATED_TEST','PASS','MIGRATION','part5_wave5a_security_control_plane_smoke',
  'Part 5A DENY paths passed for direct security tables, unrelated role, and anonymous caller.',
  'part5a-closeout','SEC-005','PG-002',jsonb_build_object('scope','TEST','direct_table_access','DENIED'),now(),null
);

select ops.record_security_evidence(
  'api_inventory_review','TEST','DB_INTROSPECTION','PASS','MIGRATION','part5_wave5a_security_definer_grant_hardening',
  'Exposed API and SECURITY DEFINER inventory reviewed after hardening; no unexpected anonymous privileged execution remains.',
  'part5a-closeout','SEC-006','PG-003',jsonb_build_object('unexpected_anon_privileged_execute',0),now(),null
);

select ops.record_security_evidence(
  'incident_runbook','SHARED','RUNBOOK','PASS','GOOGLE_DRIVE','1TNbLVwNTp4pamDS0mrApUC3fGK_Z5I5j',
  'Canonical MeYou Connect Incident Response Runbook is present in Google Drive.',
  'part5a-closeout',null,'PG-012',jsonb_build_object('document','MEYOU_CONNECT_INCIDENT_RESPONSE_RUNBOOK_V1.md'),now(),null
);

select ops.record_security_evidence(
  'supabase_security_advisor','TEST','SECURITY_ADVISOR','PASS','SUPABASE_ADVISOR','pgjmxdeafzogzsyawejs',
  'Supabase Security Advisor returned zero lints after Part 5A hardening.',
  'part5a-closeout','SEC-004',null,jsonb_build_object('lint_count',0),now(),null
);

select ops.evaluate_security_gates('TEST','part5a-closeout');
select ops.evaluate_security_gates('PROD','part5a-closeout');

update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key='part5a_foundation_closed';
update config.system_settings set setting_value='"NOT_READY"'::jsonb,updated_at=now() where setting_key='part5_production_readiness_status';
update config.system_settings set setting_value='false'::jsonb,updated_at=now() where setting_key in ('security_production_gate_enabled','security_external_alert_delivery_enabled','security_webhook_enforcement_ready','security_prod_environment_verified');