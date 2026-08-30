insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
 ('part5b_foundation_closed','true'::jsonb,'Part 5B TEST webhook/API protection foundation closed after acceptance.','PART5_WAVE5B'),
 ('security_webhook_test_acceptance_passed','true'::jsonb,'TEST endpoint security acceptance passed.','PART5_WAVE5B')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

update config.system_settings
set setting_value='true'::jsonb,
    description='Webhook signature/replay enforcement contract is implemented and accepted in TEST; external live ingress remains separately disabled.',
    source_ref='PART5_WAVE5B',
    updated_at=now()
where setting_key='security_webhook_enforcement_ready';

update config.system_settings set setting_value='false'::jsonb,updated_at=now() where setting_key in ('security_test_ingress_enabled','external_channel_webhooks_enabled');
update ops.ingress_endpoint_policies set enabled=false,updated_at=now();

select ops.record_security_evidence(
 'PART5B_TEST_WEBHOOK_REPLAY_ACCEPTANCE_V1','TEST','ACCEPTANCE_TEST','PASS','SUPABASE_MIGRATION','part5_wave5b_endpoint_security_smoke',
 'TEST webhook/API guard passed signature-required, replay-window, idempotent retry, replay rejection, timestamp, payload, content-type, sensitive quarantine and source-policy tests.',
 'CHATGPT_ARCHITECT','SEC-007','PG-006',
 jsonb_build_object('crypto_boundary','provider adapter verifies signature using secret store; database receives only verification result','external_live_ingress_enabled',false,'raw_test_residue',0),
 now(),null
);

select ops.record_security_evidence(
 'PART5B_TEST_ABUSE_RATE_ACCEPTANCE_V1','TEST','ACCEPTANCE_TEST','PASS','SUPABASE_MIGRATION','part5_wave5b_endpoint_security_smoke',
 'TEST fixed-window endpoint rate control rejected requests above the configured endpoint limit and recorded the rejection reason without raw client identifiers.',
 'CHATGPT_ARCHITECT','SEC-008',null,
 jsonb_build_object('client_identity_storage','hashed key only','rate_policy','per endpoint fixed window','external_live_ingress_enabled',false),
 now(),null
);

select ops.evaluate_security_gates('TEST','part5b-closeout');
select ops.evaluate_security_gates('PROD','part5b-closeout');