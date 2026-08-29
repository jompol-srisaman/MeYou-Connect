do $$
declare
  v_event ops.events;
  v_event2 ops.events;
  v_effect ops.event_effects;
  v_effect2 ops.event_effects;
  v_event_count integer;
  v_effect_count integer;
begin
  insert into ops.raw_inputs (
    raw_input_id, channel, sender_type, content_type, original_ref, raw_summary
  ) values (
    'WC-RAW-SMOKE001', 'TEST', 'automation', 'system', 'smoke:event:001', 'Part 3 Wave 3A synthetic smoke test'
  );

  select * into v_event from ops.register_event(
    '2.1','smoke','event-001','smoke|event-001','trace-smoke-001',
    'candidate.lead.received',now(),'WC-RAW-SMOKE001'
  );

  select * into v_event2 from ops.register_event(
    '2.1','smoke','event-001','smoke|event-001','trace-smoke-001',
    'candidate.lead.received',now(),'WC-RAW-SMOKE001'
  );

  if v_event.event_pk <> v_event2.event_pk then
    raise exception 'SMOKE FAIL: event replay returned different event_pk';
  end if;

  select count(*) into v_event_count
  from ops.events
  where source_system='smoke' and event_id='event-001';

  if v_event_count <> 1 then
    raise exception 'SMOKE FAIL: expected one event, got %', v_event_count;
  end if;

  select * into v_effect from ops.register_effect(
    v_event.event_pk,'candidate.upsert','smoke:candidate:event-001','Candidate','WC-C-SMOKE001','synthetic'
  );

  select * into v_effect2 from ops.register_effect(
    v_event.event_pk,'candidate.upsert','smoke:candidate:event-001','Candidate','WC-C-SMOKE001','synthetic'
  );

  if v_effect.effect_id <> v_effect2.effect_id then
    raise exception 'SMOKE FAIL: effect replay returned different effect_id';
  end if;

  select count(*) into v_effect_count
  from ops.event_effects
  where effect_key='smoke:candidate:event-001';

  if v_effect_count <> 1 then
    raise exception 'SMOKE FAIL: expected one effect, got %', v_effect_count;
  end if;

  delete from ops.event_effects where effect_key='smoke:candidate:event-001';
  delete from ops.events where source_system='smoke' and event_id='event-001';
  delete from ops.raw_inputs where raw_input_id='WC-RAW-SMOKE001';
end $$;
