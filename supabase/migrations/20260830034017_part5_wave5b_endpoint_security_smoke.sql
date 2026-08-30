begin;

update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key='security_test_ingress_enabled';

do $$
declare v jsonb; begin
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-disabled','evt-disabled','idem-disabled',now(),100,'application/json',true,true,'rh-disabled','ch-disabled',false,'{}'::jsonb,now());
  if v->>'reason_code' <> 'ENDPOINT_DISABLED' then raise exception 'disabled endpoint did not fail closed: %',v; end if;
end $$;

update ops.ingress_endpoint_policies set enabled=true,updated_at=now() where endpoint_key in ('facebook_webhook_test','public_candidate_form_test');
update ops.ingress_endpoint_policies set rate_limit_requests=2,rate_limit_window_seconds=60,updated_at=now() where endpoint_key='public_candidate_form_test';

do $$
declare v jsonb; v2 jsonb; v_count int; v_env jsonb; begin
  v_env:=jsonb_build_object(
    'raw_input_id','MYC-RAW-990501','schema_version','1.0','source_system','FACEBOOK','channel','FACEBOOK',
    'event_id','tst5b-event-001','idempotency_key','tst5b|event|001','trace_id','tst5b-trace-001',
    'event_type','candidate.lead.received','occurred_at',now(),'sender_type','CANDIDATE','content_type','application/json',
    'original_ref','facebook:test:message:001','raw_summary','Synthetic Part 5B candidate lead','entity_type_hint','Candidate',
    'ai_parsed',false,'sensitive',false,'metadata',jsonb_build_object('test_scope','PART5B'));
  v:=ops.secure_ingest_material_event('facebook_webhook_test','tst5b-req-valid-001',now(),512,'application/json',true,true,'tst5b-replay-001','tst5b-client-a',v_env,'{}'::jsonb,now());
  if v->>'decision'<>'ALLOW' or coalesce((v->>'ingested')::boolean,false) is not true then raise exception 'valid signed ingress failed: %',v; end if;
  select count(*) into v_count from ops.events where event_id='tst5b-event-001';
  if v_count<>1 then raise exception 'valid ingress event count expected 1 got %',v_count; end if;
  select count(*) into v_count from ops.raw_inputs where raw_input_id='MYC-RAW-990501';
  if v_count<>1 then raise exception 'valid ingress raw input count expected 1 got %',v_count; end if;

  v2:=ops.secure_ingest_material_event('facebook_webhook_test','tst5b-req-valid-001',now(),512,'application/json',true,true,'tst5b-replay-001','tst5b-client-a',v_env,'{}'::jsonb,now());
  if v2->>'decision'<>'ALLOW' or coalesce((v2->>'duplicate_event')::boolean,false) is not true then raise exception 'idempotent retry failed: %',v2; end if;
  select count(*) into v_count from ops.events where event_id='tst5b-event-001';
  if v_count<>1 then raise exception 'idempotent retry duplicated event'; end if;
end $$;

do $$
declare v jsonb; v_env jsonb; v_count int; begin
  v_env:=jsonb_build_object('raw_input_id','MYC-RAW-990502','source_system','FACEBOOK','channel','FACEBOOK','event_id','tst5b-event-002','idempotency_key','tst5b|event|002','trace_id','tst5b-trace-002','event_type','candidate.lead.received','occurred_at',now(),'sender_type','CANDIDATE','content_type','application/json','original_ref','facebook:test:message:002','raw_summary','Replay should not ingest','sensitive',false,'metadata','{}'::jsonb);
  v:=ops.secure_ingest_material_event('facebook_webhook_test','tst5b-req-replay-002',now(),512,'application/json',true,true,'tst5b-replay-001','tst5b-client-a',v_env,'{}'::jsonb,now());
  if v->>'reason_code'<>'REPLAY_DETECTED' then raise exception 'replay was not rejected: %',v; end if;
  select count(*) into v_count from ops.events where event_id='tst5b-event-002'; if v_count<>0 then raise exception 'replay created event'; end if;
  select count(*) into v_count from ops.raw_inputs where raw_input_id='MYC-RAW-990502'; if v_count<>0 then raise exception 'replay created raw input'; end if;
end $$;

do $$
declare v jsonb; begin
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-badsig','e','i',now(),100,'application/json',true,false,'rh-badsig','client-b',false,'{}',now());
  if v->>'reason_code'<>'SIGNATURE_INVALID' then raise exception 'signature guard failed: %',v; end if;
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-stale','e','i',now()-interval '10 minutes',100,'application/json',true,true,'rh-stale','client-c',false,'{}',now());
  if v->>'reason_code'<>'REQUEST_STALE' then raise exception 'stale guard failed: %',v; end if;
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-future','e','i',now()+interval '5 minutes',100,'application/json',true,true,'rh-future','client-d',false,'{}',now());
  if v->>'reason_code'<>'REQUEST_FROM_FUTURE' then raise exception 'future guard failed: %',v; end if;
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-large','e','i',now(),2000000,'application/json',true,true,'rh-large','client-e',false,'{}',now());
  if v->>'reason_code'<>'PAYLOAD_TOO_LARGE' then raise exception 'payload guard failed: %',v; end if;
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-content','e','i',now(),100,'text/plain',true,true,'rh-content','client-f',false,'{}',now());
  if v->>'reason_code'<>'CONTENT_TYPE_NOT_ALLOWED' then raise exception 'content type guard failed: %',v; end if;
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-sensitive','e','i',now(),100,'application/json',true,true,'rh-sensitive','client-g',true,'{}',now());
  if v->>'decision'<>'QUARANTINE' or v->>'reason_code'<>'SENSITIVE_NOT_ALLOWED' then raise exception 'sensitive quarantine failed: %',v; end if;
  v:=ops.evaluate_ingress_request('facebook_webhook_test','tst5b-secretmeta','e','i',now(),100,'application/json',true,true,'rh-secret','client-h',false,jsonb_build_object('api_key','do-not-store'),now());
  if v->>'reason_code'<>'SECRET_MATERIAL_NOT_ALLOWED' then raise exception 'secret metadata guard failed: %',v; end if;
end $$;

do $$
declare v jsonb; v_env jsonb; v_count int; begin
  v_env:=jsonb_build_object('raw_input_id','MYC-RAW-990503','source_system','LINE','channel','LINE','event_id','tst5b-event-003','idempotency_key','tst5b|event|003','trace_id','tst5b-trace-003','event_type','candidate.lead.received','occurred_at',now(),'sender_type','CANDIDATE','content_type','application/json','original_ref','line:spoof:003','raw_summary','spoof test','sensitive',false,'metadata','{}'::jsonb);
  v:=ops.secure_ingest_material_event('facebook_webhook_test','tst5b-spoof',now(),100,'application/json',true,true,'rh-spoof','client-i',v_env,'{}',now());
  if v->>'reason_code'<>'SOURCE_POLICY_MISMATCH' then raise exception 'source spoof guard failed: %',v; end if;
  select count(*) into v_count from ops.raw_inputs where raw_input_id='MYC-RAW-990503'; if v_count<>0 then raise exception 'source spoof created raw input'; end if;
end $$;

do $$
declare v1 jsonb; v2 jsonb; v3 jsonb; begin
  v1:=ops.evaluate_ingress_request('public_candidate_form_test','tst5b-rate-1','r1','ri1',now(),100,'application/json',false,false,'rh-rate-1','rate-client',false,'{}',now());
  v2:=ops.evaluate_ingress_request('public_candidate_form_test','tst5b-rate-2','r2','ri2',now(),100,'application/json',false,false,'rh-rate-2','rate-client',false,'{}',now());
  v3:=ops.evaluate_ingress_request('public_candidate_form_test','tst5b-rate-3','r3','ri3',now(),100,'application/json',false,false,'rh-rate-3','rate-client',false,'{}',now());
  if v1->>'decision'<>'ALLOW' or v2->>'decision'<>'ALLOW' or v3->>'reason_code'<>'RATE_LIMITED' then raise exception 'rate limit acceptance failed: %, %, %',v1,v2,v3; end if;
end $$;

insert into auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous) values
 ('50000000-0000-0000-0000-000000000001','authenticated','authenticated','tst5b-founder@example.invalid',now(),now(),false,false),
 ('50000000-0000-0000-0000-000000000002','authenticated','authenticated','tst5b-audit@example.invalid',now(),now(),false,false),
 ('50000000-0000-0000-0000-000000000003','authenticated','authenticated','tst5b-content@example.invalid',now(),now(),false,false);
select authz.assign_role('50000000-0000-0000-0000-000000000001','founder','part5b-smoke','synthetic founder',null);
select authz.assign_role('50000000-0000-0000-0000-000000000002','data_audit','part5b-smoke','synthetic audit',null);
select authz.assign_role('50000000-0000-0000-0000-000000000003','content_studio','part5b-smoke','synthetic content',null);

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$ declare v_count int; begin
  select count(*) into v_count from api.security_ingress_policies(); if v_count<4 then raise exception 'founder ingress policy API missing rows'; end if;
  select count(*) into v_count from api.security_ingress_summary(); if v_count<4 then raise exception 'founder ingress summary API missing rows'; end if;
  begin perform 1 from ops.ingress_request_log limit 1; raise exception 'direct ingress log unexpectedly allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000002',true);
do $$ declare v_count int; begin
  select count(*) into v_count from api.security_ingress_rejections(100); if v_count<1 then raise exception 'data audit rejection API missing test rows'; end if;
end $$;

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000003',true);
do $$ begin
  begin perform * from api.security_ingress_policies(); raise exception 'content role unexpectedly accessed security ingress API'; exception when others then if position('ACCESS_DENIED' in sqlerrm)=0 then raise; end if; end;
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform * from api.security_ingress_policies(); raise exception 'anon unexpectedly executed ingress security API'; exception when insufficient_privilege then null; end;
end $$;

reset role;
rollback;