do $$
declare v_repo uuid; v_drive uuid; v_prompt uuid;
begin
 v_repo:=ops.register_secret_scan_run('part5e-github-targeted-20260830','SHARED','GITHUB_REPOSITORY','jompol-srisaman/MeYou-Connect','CONNECTED_GITHUB_CODE_SEARCH','ChatGPT/Architect','Targeted token-pattern searches; not an exhaustive provider-native secret scan.');
 perform ops.finalize_secret_scan_run(v_repo,0,4,false,'github:connected-search-20260830','No hits for tested high-risk token markers; coverage remains partial.');

 v_drive:=ops.register_secret_scan_run('part5e-drive-targeted-20260830','SHARED','GOOGLE_DRIVE','MEYOU CONNECT accessible Drive','CONNECTED_DRIVE_SEARCH','ChatGPT/Architect','Targeted content/metadata searches; not an exhaustive Drive DLP scan.');
 perform ops.finalize_secret_scan_run(v_drive,0,4,false,'drive:connected-search-20260830','No hits for tested high-risk token markers; coverage remains partial.');

 v_prompt:=ops.register_secret_scan_run('part5e-prompt-known-exposure-20260830','SHARED','PROMPT_HISTORY','Current project conversation history','KNOWN_HISTORY_REVIEW','ChatGPT/Architect','No credential value is copied into the control plane.');
 perform ops.record_secret_scan_finding(v_prompt,'KNOWN_EXPOSURE','SEV1','CONVERSATION_HISTORY','CHAT_REDACTED','A sensitive credential was previously shared in chat; rotation/revocation evidence has not been verified.','ROTATION_REQUIRED','part5e:known-prompt-exposure','{}'::jsonb);
 perform ops.finalize_secret_scan_run(v_prompt,1,1,false,'part5e:known-prompt-exposure','Known exposure remains unresolved until rotation/revocation is verified.');
end $$;

insert into ops.security_evidence_records(evidence_key,environment,control_id,gate_id,evidence_type,status,source_type,source_ref,summary,details,observed_at,recorded_by)
values
 ('secret_scan_review','TEST','SEC-002','PG-004','CONNECTED_SCAN_REVIEW','NOT_READY','MULTI_SOURCE','part5e:connected-scans-20260830','Targeted GitHub/Drive searches found no tested marker hits, but full scan coverage is incomplete and prior prompt exposure still requires rotation verification.',jsonb_build_object('github','PARTIAL','drive','PARTIAL','prompt_history','ROTATION_REQUIRED'),now(),'ChatGPT/Architect'),
 ('credential_separation','TEST','SEC-002','PG-005','ENVIRONMENT_INVENTORY','NOT_READY','DATABASE_CONTROL_PLANE','part5e:environment-inventory','TEST exists; PROD environment and verified distinct production credential are not created/verified.',jsonb_build_object('test_environment','ACTIVE','prod_environment','NOT_CREATED'),now(),'ChatGPT/Architect'),
 ('secret_scan_review','PROD','SEC-002','PG-004','CONNECTED_SCAN_REVIEW','NOT_READY','MULTI_SOURCE','part5e:connected-scans-20260830','Production secret-scan gate cannot pass before full coverage and remediation evidence exist.','{}'::jsonb,now(),'ChatGPT/Architect'),
 ('credential_separation','PROD','SEC-002','PG-005','ENVIRONMENT_INVENTORY','NOT_READY','DATABASE_CONTROL_PLANE','part5e:environment-inventory','Production environment/credential has not been created and therefore separation is not yet provable.','{}'::jsonb,now(),'ChatGPT/Architect');

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
 ('security_secret_scan_review_complete','false'::jsonb,'Targeted connected scans exist but full coverage/remediation is incomplete.','Part5E evidence'),
 ('security_test_prod_credentials_separated','false'::jsonb,'PROD environment/credential not yet verified.','Part5E evidence')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();