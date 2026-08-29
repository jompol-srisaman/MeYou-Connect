do $$
declare
  v_ingest1 jsonb;
  v_ingest2 jsonb;
  v_file1 jsonb;
  v_file2 jsonb;
  v_replay1 jsonb;
  v_replay2 jsonb;
  v_event_pk uuid;
  v_raw_count integer;
  v_event_count integer;
  v_file_count integer;
  v_replay_count integer;
  v_route_count integer;
  v_expected_error boolean := false;
begin
  v_ingest1 := ops.ingest_material_event(
    'WC-RAW-SMOKE3B001','2.1','chatgpt','founder_chat','wave3b-event-001',
    'chatgpt|wave3b-event-001','trace-wave3b-001','candidate.lead.received',now(),
    'founder','text','chatgpt:wave3b:message:001',null,'founder-account',
    'thread-wave3b-001','message-wave3b-001','synthetic founder candidate lead',
    'Candidate',null,true,99,false,null,'{"test":true}'::jsonb,null,null
  );

  v_ingest2 := ops.ingest_material_event(
    'WC-RAW-SMOKE3B001','2.1','chatgpt','founder_chat','wave3b-event-001',
    'chatgpt|wave3b-event-001','trace-wave3b-001','candidate.lead.received',now(),
    'founder','text','chatgpt:wave3b:message:001',null,'founder-account',
    'thread-wave3b-001','message-wave3b-001','synthetic founder candidate lead',
    'Candidate',null,true,99,false,null,'{"test":true}'::jsonb,null,null
  );

  if coalesce((v_ingest1->>'duplicate_event')::boolean, false) then
    raise exception 'WAVE3B FAIL: first ingest unexpectedly duplicate';
  end if;
  if not coalesce((v_ingest2->>'duplicate_event')::boolean, false) then
    raise exception 'WAVE3B FAIL: replay ingest not marked duplicate';
  end if;
  if v_ingest1->>'route_key' <> 'candidate_intake' then
    raise exception 'WAVE3B FAIL: wrong route %', v_ingest1->>'route_key';
  end if;

  select count(*) into v_raw_count from ops.raw_inputs where raw_input_id='WC-RAW-SMOKE3B001';
  select count(*) into v_event_count from ops.events where source_system='chatgpt' and event_id='wave3b-event-001';
  select event_pk into v_event_pk from ops.events where source_system='chatgpt' and event_id='wave3b-event-001' limit 1;

  if v_raw_count <> 1 or v_event_count <> 1 or v_event_pk is null then
    raise exception 'WAVE3B FAIL: raw/event counts raw=% event=%', v_raw_count, v_event_count;
  end if;

  v_file1 := ops.register_file_intake(
    'WC-RAW-SMOKE3B001','chatgpt','file-wave3b-001','founder-account',
    'candidate_photo.jpg','image/jpeg',12345,null,'SOURCE_NOT_MIRRORED',false,'{"test":true}'::jsonb
  );
  v_file2 := ops.register_file_intake(
    'WC-RAW-SMOKE3B001','chatgpt','file-wave3b-001','founder-account',
    'candidate_photo.jpg','image/jpeg',12345,null,'SOURCE_NOT_MIRRORED',false,'{"test":true}'::jsonb
  );

  if coalesce((v_file1->>'duplicate_file')::boolean, false) then
    raise exception 'WAVE3B FAIL: first file unexpectedly duplicate';
  end if;
  if not coalesce((v_file2->>'duplicate_file')::boolean, false) then
    raise exception 'WAVE3B FAIL: replay file not marked duplicate';
  end if;

  select count(*) into v_file_count from ops.file_intake
  where source_system='chatgpt' and provider_file_ref='file-wave3b-001';
  if v_file_count <> 1 then
    raise exception 'WAVE3B FAIL: expected one file intake, got %', v_file_count;
  end if;

  update ops.events set processing_state='DEAD_LETTER' where event_pk=v_event_pk;

  v_replay1 := ops.request_manual_replay(v_event_pk,'smoke-test','verify replay request idempotency');
  v_replay2 := ops.request_manual_replay(v_event_pk,'smoke-test','verify replay request idempotency');

  if coalesce((v_replay1->>'duplicate_request')::boolean, false) then
    raise exception 'WAVE3B FAIL: first replay request unexpectedly duplicate';
  end if;
  if not coalesce((v_replay2->>'duplicate_request')::boolean, false) then
    raise exception 'WAVE3B FAIL: duplicate replay request not detected';
  end if;

  select count(*) into v_replay_count from ops.replay_requests where event_pk=v_event_pk and status='PENDING';
  if v_replay_count <> 1 then
    raise exception 'WAVE3B FAIL: expected one pending replay request, got %', v_replay_count;
  end if;

  select count(*) into v_route_count from ops.routing_rules where active=true;
  if v_route_count < 20 then
    raise exception 'WAVE3B FAIL: routing catalog incomplete: %', v_route_count;
  end if;

  begin
    perform ops.ingest_material_event(
      'WC-RAW-SMOKE3B999','2.1','chatgpt','founder_chat','wave3b-event-999',
      'chatgpt|wave3b-event-999','trace-wave3b-999','unknown.event',now(),
      'founder','text','chatgpt:wave3b:message:999'
    );
  exception when others then
    v_expected_error := true;
  end;

  if not v_expected_error then
    raise exception 'WAVE3B FAIL: unsupported event_type was accepted';
  end if;

  delete from ops.replay_requests where event_pk=v_event_pk;
  delete from ops.file_intake where raw_input_id='WC-RAW-SMOKE3B001';
  delete from ops.events where event_pk=v_event_pk;
  delete from ops.raw_inputs where raw_input_id='WC-RAW-SMOKE3B001';
end $$;
