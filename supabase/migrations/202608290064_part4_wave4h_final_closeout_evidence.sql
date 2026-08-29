do $$
declare
  v_test jsonb;
  v_prod jsonb;
  v_gate boolean;
  v_source text;
begin
  perform ops.record_part4_evidence(
    'PART4_REPOSITORY_OUTPUTS',
    'PASS',
    'GitHub:jompol-srisaman/MeYou-Connect@main',
    jsonb_build_object(
      'schema_overview','docs/PART4_SCHEMA_OVERVIEW.md',
      'rollback_runbook','docs/PART4_ROLLBACK_RUNBOOK.md',
      'environment_security_notes','docs/PART4_ENVIRONMENT_SECURITY_NOTES.md',
      'open_issues','docs/PART4_OPEN_ISSUES.md',
      'production_readiness_evidence','docs/PART4_PRODUCTION_READINESS_EVIDENCE.md',
      'file_migration_verifier','scripts/part4_file_migration_verify.py'
    ),
    'Part4H Closeout'
  );

  perform ops.record_part4_evidence(
    'PART4_SECURITY_ADVISOR',
    'PASS',
    'Supabase Security Advisor / Part4H',
    jsonb_build_object(
      'security_lints',0,
      'performance_blockers',0,
      'remaining_performance_notice','unused_index INFO in TEST/no-traffic environment',
      'checked_after_hardening',true
    ),
    'Part4H Closeout'
  );

  v_test:=ops.evaluate_part4_closeout('TEST_IMPLEMENTATION','Part4H Final Closeout');
  if v_test->>'status' <> 'PASS' then
    raise exception 'Part 4 TEST implementation closeout must PASS, got %',v_test;
  end if;

  v_prod:=ops.evaluate_part4_closeout('PRODUCTION_READINESS','Part4H Final Closeout');
  if v_prod->>'status' <> 'NOT_READY' then
    raise exception 'Production readiness must remain NOT_READY, got %',v_prod;
  end if;

  select config.setting_is_true('part4_test_implementation_closed') into v_gate;
  if not v_gate then raise exception 'Part 4 TEST closeout flag was not set'; end if;

  select config.setting_is_true('production_cutover_approved') into v_gate;
  if v_gate then raise exception 'Production cutover approval was unexpectedly enabled'; end if;
  select config.setting_is_true('migration_cutover_enabled') into v_gate;
  if v_gate then raise exception 'Migration cutover was unexpectedly enabled'; end if;
  select config.setting_is_true('migration_target_apply_enabled') into v_gate;
  if v_gate then raise exception 'Migration target apply was unexpectedly enabled'; end if;

  select setting_value #>> '{}' into v_source from config.system_settings where setting_key='current_operational_source';
  if v_source <> 'GOOGLE_SHEETS_DRIVE' then raise exception 'Operational Source of Truth changed unexpectedly: %',v_source; end if;
end;
$$;
