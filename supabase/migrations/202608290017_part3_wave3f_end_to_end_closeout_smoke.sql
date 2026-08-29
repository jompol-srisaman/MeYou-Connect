begin;

do $$
declare
  v_event_pk uuid;
  v_claim record;
  v_prepare jsonb;
  v_command_pk uuid;
  v_status jsonb;
  v_snapshot ops.operations_snapshots;
  v_count integer;
  v_hb jsonb;
begin
  perform ops.ingest_material_event(
    p_raw_input_id=>'WC-RAW-990091',
    p_schema_version=>'2.1',
    p_source_system=>'wave3f_smoke',
    p_channel=>'chatgpt',
    p_event_id=>'wave3f-e2e-001',
    p_idempotency_key=>'wave3f|e2e|001',
    p_trace_id=>'wave3f-trace-001',
    p_event_type=>'candidate.lead.received',
    p_occurred_at=>now(),
    p_sender_type=>'founder',
    p_content_type=>'text',
    p_original_ref=>'wave3f:original:001',
    p_raw_summary=>'Synthetic Part 3F candidate intake closeout test',
    p_entity_type_hint=>'Candidate',
    p_ai_parsed=>true,
    p_ai_confidence=>99,
    p_sensitive=>false,
    p_metadata=>jsonb_build_object('test','part3f_closeout')
  );

  select event_pk into v_event_pk
  from ops.events
  where source_system='wave3f_smoke' and event_id='wave3f-e2e-001';

  if v_event_pk is null then raise exception '3F E2E FAIL: event not created'; end if;

  select * into v_claim
  from ops.claim_events('candidate_intake','wave3f-worker-1',1,120,now())
  where event_pk=v_event_pk
  limit 1;

  if v_claim.worker_run_pk is null then raise exception '3F E2E FAIL: candidate event not claimed'; end if;

  v_prepare := ops.prepare_domain_command(
    v_event_pk,
    'candidate_intake',
    v_claim.lease_token,
    jsonb_build_object(
      'candidate',jsonb_build_object(
        'full_name','Part 3F Synthetic Candidate',
        'phone','0800000091',
        'origin_province','Saraburi',
        'relocation_ready',true
      ),
      'source','wave3f_smoke'
    ),
    'Candidate',
    null
  );

  if coalesce(v_prepare->>'validation_status','')<>'VALID'
     or coalesce(v_prepare->>'apply_status','')<>'READY' then
    raise exception '3F E2E FAIL: command not VALID/READY: %',v_prepare;
  end if;

  v_command_pk := (v_prepare->>'command_pk')::uuid;
  if v_command_pk is null then raise exception '3F E2E FAIL: command_pk missing'; end if;

  perform ops.finish_event_success(
    v_claim.worker_run_pk,
    v_claim.lease_token,
    'domain.command.prepared',
    'wave3f|effect|candidate|001',
    'Candidate',
    null,
    v_command_pk::text,
    jsonb_build_object('wave','3F','result','proposal_ready'),
    now()
  );

  if not exists(select 1 from ops.events where event_pk=v_event_pk and processing_state='COMPLETED') then
    raise exception '3F E2E FAIL: event not completed';
  end if;

  if (select count(*) from ops.event_effects where effect_key='wave3f|effect|candidate|001')<>1 then
    raise exception '3F E2E FAIL: effect not exactly once';
  end if;

  v_hb := ops.record_worker_heartbeat('candidate_intake','wave3f-worker-1','wave3f_smoke','HEALTHY','3f-test-1',jsonb_build_object('phase','first'),now());
  v_hb := ops.record_worker_heartbeat('candidate_intake','wave3f-worker-1','wave3f_smoke','HEALTHY','3f-test-2',jsonb_build_object('phase','second'),now());

  select count(*) into v_count
  from ops.worker_heartbeats
  where worker_key='candidate_intake' and worker_instance='wave3f-worker-1' and environment='wave3f_smoke';
  if v_count<>1 then raise exception '3F HEARTBEAT FAIL: expected one upserted heartbeat, got %',v_count; end if;

  if not exists(
    select 1 from ops.worker_heartbeats
    where worker_key='candidate_intake'
      and worker_instance='wave3f-worker-1'
      and environment='wave3f_smoke'
      and version='3f-test-2'
  ) then
    raise exception '3F HEARTBEAT FAIL: latest version not stored';
  end if;

  v_snapshot := ops.capture_operations_snapshot('wave3f_smoke',now());
  if v_snapshot.snapshot_pk is null or v_snapshot.total_events<1 or v_snapshot.completed_events<1 then
    raise exception '3F SNAPSHOT FAIL';
  end if;

  v_status := ops.part3_closeout_status();
  if coalesce((v_status->>'part3_foundation_ready_for_part4')::boolean,false) is not true then
    raise exception '3F CLOSEOUT FAIL: foundation not ready: %',v_status;
  end if;

  delete from ops.operations_snapshots where environment='wave3f_smoke';
  delete from ops.worker_heartbeats where environment='wave3f_smoke';
  delete from ops.domain_commands where event_pk=v_event_pk;
  delete from ops.event_effects where event_pk=v_event_pk;
  delete from ops.worker_runs where event_pk=v_event_pk;
  delete from ops.approvals where event_pk=v_event_pk;
  delete from ops.dead_letters where event_pk=v_event_pk;
  delete from ops.scheduled_signals where emitted_event_pk=v_event_pk;
  delete from ops.events where event_pk=v_event_pk;
  delete from ops.raw_inputs where raw_input_id='WC-RAW-990091';

  if exists(select 1 from ops.events where source_system='wave3f_smoke')
     or exists(select 1 from ops.raw_inputs where raw_input_id='WC-RAW-990091')
     or exists(select 1 from ops.worker_heartbeats where environment='wave3f_smoke')
     or exists(select 1 from ops.operations_snapshots where environment='wave3f_smoke') then
    raise exception '3F CLEANUP FAIL: synthetic records remain';
  end if;

  raise notice 'PASS: Part 3F end-to-end closeout / heartbeat / snapshot / readiness';
end $$;

commit;
