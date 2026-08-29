begin;

insert into ops.routing_rules(event_type, domain, route_key, material, evidence_expected, approval_policy)
values
  ('test.worker.dispatch','Test','test_worker_3d',false,false,'NONE'),
  ('test.approval.dispatch','Test','test_approval_worker_3d',false,false,'FOUNDER_APPROVAL')
on conflict (event_type) do update set active = true, updated_at = now();

insert into ops.worker_registry(worker_key, domain, enabled, default_lease_seconds, default_batch_size, max_retries, description)
values
  ('test_worker_3d','Test',true,60,10,3,'Wave 3D smoke only'),
  ('test_approval_worker_3d','Test',true,60,10,3,'Wave 3D smoke only')
on conflict (worker_key) do update set enabled=true, updated_at=now();

do $$
declare
  v_event ops.events;
  v_claim record;
  v_claim_count integer;
  v_result jsonb;
  v_effect_count integer;
  v_retry_event ops.events;
  v_retry_run ops.worker_runs;
  v_approval_id uuid;
  v_state ops.event_processing_state;
  v_attempt integer;
  v_dead integer;
  v_abandoned integer;
begin
  v_event := ops.register_event('2.1','wave3d_smoke','success-001','wave3d|success-001','wave3d-trace-success','test.worker.dispatch',now(),null,null,null);
  select * into v_claim from ops.claim_events('test_worker_3d','wave3d-smoke-success',1,60,now());
  if v_claim.event_pk is distinct from v_event.event_pk then raise exception '3D-A FAIL: wrong event claimed'; end if;
  select count(*) into v_claim_count from ops.claim_events('test_worker_3d','wave3d-smoke-double-claim',1,60,now());
  if v_claim_count <> 0 then raise exception '3D-A FAIL: double claim allowed'; end if;
  perform ops.finish_event_success(v_claim.worker_run_pk,v_claim.lease_token,'test.effect','wave3d:effect:success-001','Test','TEST-001','smoke','{}'::jsonb,now());
  select processing_state into v_state from ops.events where event_pk=v_event.event_pk;
  if v_state <> 'COMPLETED' then raise exception '3D-A FAIL: success state %',v_state; end if;
  select count(*) into v_effect_count from ops.event_effects where effect_key='wave3d:effect:success-001';
  if v_effect_count <> 1 then raise exception '3D-A FAIL: effect count %',v_effect_count; end if;

  v_event := ops.register_event('2.1','wave3d_smoke','retry-001','wave3d|retry-001','wave3d-trace-retry','test.worker.dispatch',now(),null,null,null);
  select * into v_claim from ops.claim_events('test_worker_3d','wave3d-smoke-retry',1,60,now());
  perform ops.finish_event_failure(v_claim.worker_run_pk,v_claim.lease_token,'TRANSIENT','synthetic timeout','{}'::jsonb,now());
  select processing_state,processing_attempt into v_state,v_attempt from ops.events where event_pk=v_event.event_pk;
  if v_state <> 'RETRY_WAIT' or v_attempt <> 1 then raise exception '3D-B FAIL: state %, attempt %',v_state,v_attempt; end if;
  update ops.events set next_retry_at=now()-interval '1 second' where event_pk=v_event.event_pk;
  v_retry_event := ops.register_event('2.1','wave3d_smoke','retry-signal-001','wave3d|retry-signal-001','wave3d-trace-retry-signal','automation.retry_due',now(),null,null,v_event.event_id);
  insert into ops.scheduled_signals(schedule_key,event_type,due_at,next_attempt_at,source_timezone,source_system,entity_type,entity_id,causation_event_id,payload,status,attempt_count,max_attempts,emitted_event_pk,emitted_at,created_by)
  values ('wave3d-smoke:retry:001','automation.retry_due',now(),now(),'Asia/Bangkok','wave3d_smoke','Test','TEST-RETRY',v_event.event_id,jsonb_build_object('source_event_pk',v_event.event_pk,'source_event_id',v_event.event_id,'processing_attempt',1),'EMITTED',1,5,v_retry_event.event_pk,now(),'wave3d-smoke');
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values (v_retry_event.event_pk,'retry_router','wave3d-smoke-retry-router',now()+interval '1 minute','CLAIMED',1)
  returning * into v_retry_run;
  perform ops.process_retry_due(v_retry_run.worker_run_pk,v_retry_run.lease_token,now());
  select processing_state into v_state from ops.events where event_pk=v_event.event_pk;
  if v_state <> 'ROUTED' then raise exception '3D-B FAIL: retry source not released'; end if;
  select * into v_claim from ops.claim_events('test_worker_3d','wave3d-smoke-retry-success',1,60,now());
  if v_claim.event_pk is distinct from v_event.event_pk then raise exception '3D-B FAIL: released event not reclaimable'; end if;
  perform ops.finish_event_success(v_claim.worker_run_pk,v_claim.lease_token,null,null,null,null,null,'{}'::jsonb,now());

  v_event := ops.register_event('2.1','wave3d_smoke','dlq-001','wave3d|dlq-001','wave3d-trace-dlq','test.worker.dispatch',now(),null,null,null);
  update ops.events set processing_attempt=3 where event_pk=v_event.event_pk;
  select * into v_claim from ops.claim_events('test_worker_3d','wave3d-smoke-dlq',1,60,now());
  perform ops.finish_event_failure(v_claim.worker_run_pk,v_claim.lease_token,'TRANSIENT','fourth failure','{}'::jsonb,now());
  select processing_state,processing_attempt into v_state,v_attempt from ops.events where event_pk=v_event.event_pk;
  select count(*) into v_dead from ops.dead_letters where event_pk=v_event.event_pk;
  if v_state <> 'DEAD_LETTER' or v_attempt <> 4 or v_dead <> 1 then raise exception '3D-C FAIL'; end if;

  v_event := ops.register_event('2.1','wave3d_smoke','approval-001','wave3d|approval-001','wave3d-trace-approval','test.approval.dispatch',now(),null,null,null);
  select * into v_claim from ops.claim_events('test_approval_worker_3d','wave3d-smoke-approval',1,60,now());
  v_result := ops.request_event_approval(v_claim.worker_run_pk,v_claim.lease_token,'TEST_PROTECTED_ACTION','wave3d-smoke','{"amount":100}'::jsonb,now());
  v_approval_id := (v_result->>'approval_id')::uuid;
  select processing_state into v_state from ops.events where event_pk=v_event.event_pk;
  if v_state <> 'APPROVAL_REQUIRED' then raise exception '3D-D FAIL: approval state %',v_state; end if;
  perform ops.decide_approval(v_approval_id,'APPROVED','wave3d-smoke-approver','approved synthetic test',now());
  select processing_state into v_state from ops.events where event_pk=v_event.event_pk;
  if v_state <> 'ROUTED' then raise exception '3D-D FAIL: approved event not routed'; end if;
  select * into v_claim from ops.claim_events('test_approval_worker_3d','wave3d-smoke-after-approval',1,60,now());
  if v_claim.latest_approval_status <> 'APPROVED' or v_claim.latest_approval_action <> 'TEST_PROTECTED_ACTION' then raise exception '3D-D FAIL: approval context missing'; end if;
  perform ops.finish_event_success(v_claim.worker_run_pk,v_claim.lease_token,'test.approved','wave3d:effect:approval-001','Test','TEST-APPROVAL','approved-only','{}'::jsonb,now());

  v_event := ops.register_event('2.1','wave3d_smoke','lease-001','wave3d|lease-001','wave3d-trace-lease','test.worker.dispatch',now(),null,null,null);
  select * into v_claim from ops.claim_events('test_worker_3d','wave3d-smoke-expired',1,15,now()-interval '30 seconds');
  if v_claim.event_pk is distinct from v_event.event_pk then raise exception '3D-E FAIL: wrong event claimed'; end if;
  v_abandoned := ops.reap_expired_worker_runs(now(),100);
  if v_abandoned < 1 then raise exception '3D-E FAIL: expired lease not reaped'; end if;
  select processing_state,processing_attempt into v_state,v_attempt from ops.events where event_pk=v_event.event_pk;
  if v_state <> 'RETRY_WAIT' or v_attempt <> 1 then raise exception '3D-E FAIL: state %, attempt %',v_state,v_attempt; end if;
end $$;

delete from ops.event_effects where effect_key like 'wave3d:effect:%';
delete from ops.dead_letters where event_pk in (select event_pk from ops.events where source_system='wave3d_smoke');
delete from ops.approvals where event_pk in (select event_pk from ops.events where source_system='wave3d_smoke');
delete from ops.worker_runs where worker_instance like 'wave3d-smoke%';
delete from ops.scheduled_signals where schedule_key like 'wave3d-smoke:%';
delete from ops.events where source_system='wave3d_smoke';
delete from ops.worker_registry where worker_key in ('test_worker_3d','test_approval_worker_3d');
delete from ops.routing_rules where event_type in ('test.worker.dispatch','test.approval.dispatch');

commit;
