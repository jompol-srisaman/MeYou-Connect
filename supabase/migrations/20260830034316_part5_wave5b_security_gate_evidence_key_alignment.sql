select ops.record_security_evidence(
 'webhook_signature_replay','TEST','ACCEPTANCE_TEST','PASS','SUPABASE_MIGRATION','part5_wave5b_endpoint_security_smoke',
 'Canonical PG-006 evidence: TEST webhook/API signature-enforcement contract, timestamp replay window, idempotent retry and replay rejection passed. Provider cryptographic verification remains in the trusted adapter using secret-store credentials.',
 'CHATGPT_ARCHITECT','SEC-007','PG-006',
 jsonb_build_object('supporting_evidence_key','PART5B_TEST_WEBHOOK_REPLAY_ACCEPTANCE_V1','external_live_ingress_enabled',false,'provider_secret_persisted_in_database',false),
 now(),null
);
select ops.evaluate_security_gates('TEST','part5b-closeout-aligned');
select ops.evaluate_security_gates('PROD','part5b-closeout-aligned');