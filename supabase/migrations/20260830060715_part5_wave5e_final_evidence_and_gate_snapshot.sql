insert into ops.security_evidence_records(evidence_key,environment,control_id,gate_id,evidence_type,status,source_type,source_ref,summary,details,observed_at,recorded_by)
values
 ('secret_scan_review','TEST','SEC-003','PG-004','CONNECTED_SCAN_REVIEW','NOT_READY','MULTI_SOURCE','part5e:final-scan-review-20260830','Targeted GitHub and Drive searches found no tested high-risk token markers, but full scan coverage is incomplete and a known prior prompt exposure still requires verified rotation/revocation.',jsonb_build_object('github_scan','PARTIAL','drive_scan','PARTIAL','prompt_history','ROTATION_REQUIRED','secret_values_stored',false),clock_timestamp(),'ChatGPT/Architect'),
 ('credential_separation','TEST',null,'PG-005','ENVIRONMENT_INVENTORY','NOT_READY','DATABASE_CONTROL_PLANE','part5e:final-environment-review-20260830','TEST environment exists, but no verified PROD environment and distinct PROD credential binding exist yet.',jsonb_build_object('test_environment','ACTIVE','prod_environment','NOT_CREATED'),clock_timestamp(),'ChatGPT/Architect'),
 ('secret_scan_review','PROD','SEC-003','PG-004','CONNECTED_SCAN_REVIEW','NOT_READY','MULTI_SOURCE','part5e:final-scan-review-20260830','Production secret-scan gate remains blocked until full coverage and known exposure remediation are verified.',jsonb_build_object('full_scan_complete',false,'known_exposure_remediated',false),clock_timestamp(),'ChatGPT/Architect'),
 ('credential_separation','PROD',null,'PG-005','ENVIRONMENT_INVENTORY','NOT_READY','DATABASE_CONTROL_PLANE','part5e:final-environment-review-20260830','Production environment and production credential are not created/verified, so TEST/PROD separation is not yet provable.','{}'::jsonb,clock_timestamp(),'ChatGPT/Architect');

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
 ('part5e_foundation_closed','true'::jsonb,'Part 5E TEST foundation implemented and smoke-tested. Production secret and environment gates remain evidence-driven.','Part5E closeout'),
 ('security_secret_environment_foundation_ready','true'::jsonb,'Metadata-only credential/scan/isolation control plane is ready in TEST.','Part5E closeout'),
 ('security_secret_scan_review_complete','false'::jsonb,'Targeted scans are partial and known prior prompt exposure still requires remediation evidence.','Part5E closeout'),
 ('security_test_prod_credentials_separated','false'::jsonb,'PROD environment/credential not created or verified.','Part5E closeout')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=clock_timestamp();

select ops.evaluate_security_gates('TEST','Part5E Closeout');
select ops.evaluate_security_gates('PROD','Part5E Closeout');