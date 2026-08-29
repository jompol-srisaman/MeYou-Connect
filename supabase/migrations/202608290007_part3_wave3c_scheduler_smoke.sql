do $$
declare
  v_followup_1 jsonb;
  v_followup_2 jsonb;
  v_invoice jsonb;
  v_notification jsonb;
  v_source_event ops.events;
  v_tick1 jsonb;
  v_tick2 jsonb;
  v_tick3 jsonb;
  v_event_count integer;
  v_schedule_count integer;
  v_notification_count integer;
  v_invoice_event_pk uuid;
  v_context jsonb;
begin
  insert into ops.raw_inputs(
    raw_input_id, channel, sender_type, content_type, original_ref, raw_summary,
    source_system, processing_status
  ) values (
    'WC-RAW-3C-SMOKE001','TEST','automation','system','smoke:3c:retry-source',
    'Part 3C retry source','smoke3c','RAW_STORED'
  );

  select * into v_source_event from ops.register_event(
    '2.1','smoke3c','retry-source-001','smoke3c|retry-source-001','trace-smoke3c-source',
    'candidate.lead.received',now(),'WC-RAW-3C-SMOKE001'
  );

  update ops.events
  set processing_state = 'RETRY_WAIT',
      processing_attempt = 2,
      next_retry_at = now() - interval '1 minute',
      entity_type = 'Candidate',
      entity_id = 'WC-C-SMOKE3C'
  where event_pk = v_source_event.event_pk;

  v_followup_1 := ops.schedule_followup_due(
    'SMOKE-FU-001', now() - interval '2 minutes', 'Placement', 'WC-PL-SMOKE3C',
    jsonb_build_object('milestone','D7'), 'smoke3c'
  );
  v_followup_2 := ops.schedule_followup_due(
    'SMOKE-FU-001', now() - interval '2 minutes', 'Placement', 'WC-PL-SMOKE3C',
    jsonb_build_object('milestone','D7'), 'smoke3c'
  );

  if v_followup_1->>'schedule_pk' <> v_followup_2->>'schedule_pk' then
    raise exception '3C SMOKE FAIL: duplicate followup schedule changed schedule_pk';
  end if;
  if (v_followup_2->>'duplicate_schedule')::boolean is not true then
    raise exception '3C SMOKE FAIL: duplicate followup not detected';
  end if;

  v_invoice := ops.schedule_invoice_due(
    'SMOKE-INV-001', now() - interval '1 minute', 'WC-B2B-SMOKE',
    jsonb_build_object('amount',800), 'smoke3c'
  );

  v_notification := ops.schedule_notification(
    'SMOKE-NOTIFY-001', now() + interval '1 hour', 'Candidate', 'WC-C-SMOKE3C',
    jsonb_build_object('channel','TEST','template','followup_reminder'), 'smoke3c'
  );

  v_tick1 := ops.scheduler_tick(now(), 100, 'SMOKE_3C');

  if (v_tick1->>'retry_schedules_created')::integer <> 1 then
    raise exception '3C SMOKE FAIL: expected 1 retry schedule, got %', v_tick1->>'retry_schedules_created';
  end if;
  if (v_tick1->>'emitted_count')::integer <> 3 then
    raise exception '3C SMOKE FAIL: expected 3 emitted events, got %', v_tick1->>'emitted_count';
  end if;
  if (v_tick1->>'failed_count')::integer <> 0 then
    raise exception '3C SMOKE FAIL: scheduler reported failures';
  end if;

  select count(*) into v_notification_count
  from ops.events
  where source_system = 'scheduler'
    and event_id = 'schedule:notification:SMOKE-NOTIFY-001';

  if v_notification_count <> 0 then
    raise exception '3C SMOKE FAIL: future notification emitted too early';
  end if;

  v_tick2 := ops.scheduler_tick(now(), 100, 'SMOKE_3C_REPEAT');
  if (v_tick2->>'emitted_count')::integer <> 0 then
    raise exception '3C SMOKE FAIL: repeat tick emitted duplicate events';
  end if;
  if (v_tick2->>'retry_schedules_created')::integer <> 0 then
    raise exception '3C SMOKE FAIL: repeat tick created duplicate retry schedule';
  end if;

  v_tick3 := ops.scheduler_tick(now() + interval '2 hours', 100, 'SMOKE_3C_FUTURE');
  if (v_tick3->>'emitted_count')::integer <> 1 then
    raise exception '3C SMOKE FAIL: future tick expected 1 notification, got %', v_tick3->>'emitted_count';
  end if;

  select count(*) into v_event_count
  from ops.events
  where source_system = 'scheduler'
    and event_id in (
      'schedule:followup:SMOKE-FU-001',
      'schedule:invoice_due:SMOKE-INV-001',
      'schedule:notification:SMOKE-NOTIFY-001'
    );

  if v_event_count <> 3 then
    raise exception '3C SMOKE FAIL: expected exactly 3 named scheduled events, got %', v_event_count;
  end if;

  select emitted_event_pk into v_invoice_event_pk
  from ops.scheduled_signals
  where schedule_key = 'invoice_due:SMOKE-INV-001';

  v_context := ops.get_scheduled_event_context(v_invoice_event_pk);
  if v_context->'payload'->>'invoice_ref' <> 'SMOKE-INV-001' then
    raise exception '3C SMOKE FAIL: scheduled event context lost invoice payload';
  end if;

  select count(*) into v_schedule_count
  from ops.scheduled_signals
  where schedule_key like '%SMOKE%'
     or schedule_key like 'retry:' || v_source_event.event_pk::text || ':%';

  if v_schedule_count <> 4 then
    raise exception '3C SMOKE FAIL: expected 4 schedules, got %', v_schedule_count;
  end if;

  delete from ops.scheduled_signals
  where schedule_key like '%SMOKE%'
     or schedule_key like 'retry:' || v_source_event.event_pk::text || ':%';

  delete from ops.events
  where source_system = 'scheduler'
    and (
      event_id like 'schedule:%SMOKE%'
      or causation_event_id = 'retry-source-001'
    );

  delete from ops.events where event_pk = v_source_event.event_pk;
  delete from ops.raw_inputs where raw_input_id = 'WC-RAW-3C-SMOKE001';
  delete from ops.scheduler_runs where trigger_source like 'SMOKE_3C%';
end $$;