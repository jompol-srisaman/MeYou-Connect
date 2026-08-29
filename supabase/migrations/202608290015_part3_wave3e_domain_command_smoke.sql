begin;

do $$
declare
  v_event ops.events;
  v_run ops.worker_runs;
  v_result jsonb;
  v_count integer;
  v_cmd_pk uuid;
  v_raw text;
begin
  v_raw := 'WC-RAW-TEST3E-C1';
  insert into ops.raw_inputs(raw_input_id,source_system,channel,sender_type,content_type,original_ref,raw_summary,processing_status)
  values(v_raw,'test3e','TEST','system','text','test3e:candidate:valid','candidate valid','RAW_STORED');
  v_event := ops.register_event('2.1','test3e','event-candidate-valid','test3e|candidate-valid','trace-3e-c1','candidate.lead.received',now(),v_raw,null,null);
  update ops.events set processing_state='ROUTED' where event_pk=v_event.event_pk;
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'candidate_intake','wave3e-smoke',now()+interval '5 minutes','CLAIMED',1) returning * into v_run;
  v_result := ops.prepare_domain_command(v_event.event_pk,'candidate_intake',v_run.lease_token,'{"candidate":{"full_name":"Test Candidate","phone":"0800000000"}}'::jsonb,'Candidate',null);
  if v_result->>'validation_status' <> 'VALID' or v_result->>'apply_status' <> 'READY' then raise exception '3E candidate valid FAIL: %', v_result; end if;
  v_result := ops.prepare_domain_command(v_event.event_pk,'candidate_intake',v_run.lease_token,'{"candidate":{"full_name":"Test Candidate","phone":"0800000000"}}'::jsonb,'Candidate',null);
  if coalesce((v_result->>'duplicate_command')::boolean,false) <> true then raise exception '3E duplicate command FAIL: %', v_result; end if;
  select count(*) into v_count from ops.domain_commands where event_pk=v_event.event_pk;
  if v_count <> 1 then raise exception '3E duplicate count FAIL: %', v_count; end if;
  select command_pk into v_cmd_pk from ops.domain_commands where event_pk=v_event.event_pk;
  perform ops.finish_event_success(v_run.worker_run_pk,v_run.lease_token,'domain.command.prepared','test3e|candidate-valid|prepared','Candidate',null,v_cmd_pk::text,'{"wave":"3E"}'::jsonb,now());

  v_raw := 'WC-RAW-TEST3E-C2';
  insert into ops.raw_inputs(raw_input_id,source_system,channel,sender_type,content_type,original_ref,raw_summary,processing_status)
  values(v_raw,'test3e','TEST','system','text','test3e:candidate:invalid','candidate invalid','RAW_STORED');
  v_event := ops.register_event('2.1','test3e','event-candidate-invalid','test3e|candidate-invalid','trace-3e-c2','candidate.lead.received',now(),v_raw,null,null);
  update ops.events set processing_state='ROUTED' where event_pk=v_event.event_pk;
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'candidate_intake','wave3e-smoke',now()+interval '5 minutes','CLAIMED',1) returning * into v_run;
  v_result := ops.prepare_domain_command(v_event.event_pk,'candidate_intake',v_run.lease_token,'{}'::jsonb,'Candidate',null);
  if v_result->>'validation_status' <> 'INVALID' then raise exception '3E candidate invalid FAIL: %',v_result; end if;
  perform ops.finish_event_failure(v_run.worker_run_pk,v_run.lease_token,'VALIDATION','invalid candidate proposal','{"wave":"3E"}'::jsonb,now());
  select * into v_event from ops.events where event_pk=v_event.event_pk;
  if v_event.processing_state <> 'NEEDS_REVIEW' then raise exception '3E validation transition FAIL: %',v_event.processing_state; end if;

  v_raw := 'WC-RAW-TEST3E-B1';
  insert into ops.raw_inputs(raw_input_id,source_system,channel,sender_type,content_type,original_ref,raw_summary,processing_status)
  values(v_raw,'test3e','TEST','system','text','test3e:client:valid','client demand valid','RAW_STORED');
  v_event := ops.register_event('2.1','test3e','event-client-valid','test3e|client-valid','trace-3e-b1','client.demand.received',now(),v_raw,null,null);
  update ops.events set processing_state='ROUTED' where event_pk=v_event.event_pk;
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'client_job_worker','wave3e-smoke',now()+interval '5 minutes','CLAIMED',1) returning * into v_run;
  v_result := ops.prepare_domain_command(v_event.event_pk,'client_job_worker',v_run.lease_token,'{"client":{"company_name":"Test Client"},"job":{"position":"Warehouse Staff","headcount":5}}'::jsonb,'Client/Job',null);
  if v_result->>'validation_status' <> 'VALID' then raise exception '3E client valid FAIL: %',v_result; end if;
  select command_pk into v_cmd_pk from ops.domain_commands where event_pk=v_event.event_pk;
  perform ops.finish_event_success(v_run.worker_run_pk,v_run.lease_token,'domain.command.prepared','test3e|client-valid|prepared','Client/Job',null,v_cmd_pk::text,'{"wave":"3E"}'::jsonb,now());

  v_raw := 'WC-RAW-TEST3E-F1';
  insert into ops.raw_inputs(raw_input_id,source_system,channel,sender_type,content_type,original_ref,raw_summary,processing_status)
  values(v_raw,'test3e','TEST','system','file','test3e:file:valid','file valid','RAW_STORED');
  insert into ops.file_intake(raw_input_id,source_system,provider_file_ref,original_filename,content_type,mirror_status)
  values(v_raw,'test3e','provider-file-3e-1','test-slip.pdf','application/pdf','SOURCE_ONLY');
  v_event := ops.register_event('2.1','test3e','event-file-valid','test3e|file-valid','trace-3e-f1','file.uploaded',now(),v_raw,null,null);
  update ops.events set processing_state='ROUTED' where event_pk=v_event.event_pk;
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'file_evidence_worker','wave3e-smoke',now()+interval '5 minutes','CLAIMED',1) returning * into v_run;
  v_result := ops.prepare_domain_command(v_event.event_pk,'file_evidence_worker',v_run.lease_token,'{"file":{"provider_file_ref":"provider-file-3e-1"},"evidence":{"type":"PAYMENT_EVIDENCE"}}'::jsonb,'Evidence',null);
  if v_result->>'validation_status' <> 'VALID' then raise exception '3E evidence valid FAIL: %',v_result; end if;
  select command_pk into v_cmd_pk from ops.domain_commands where event_pk=v_event.event_pk;
  perform ops.finish_event_success(v_run.worker_run_pk,v_run.lease_token,'domain.command.prepared','test3e|file-valid|prepared','Evidence',null,v_cmd_pk::text,'{"wave":"3E"}'::jsonb,now());

  v_raw := 'WC-RAW-TEST3E-F2';
  insert into ops.raw_inputs(raw_input_id,source_system,channel,sender_type,content_type,original_ref,raw_summary,processing_status)
  values(v_raw,'test3e','TEST','system','file','test3e:file:missing','file missing','RAW_STORED');
  v_event := ops.register_event('2.1','test3e','event-file-missing','test3e|file-missing','trace-3e-f2','file.uploaded',now(),v_raw,null,null);
  update ops.events set processing_state='ROUTED' where event_pk=v_event.event_pk;
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'file_evidence_worker','wave3e-smoke',now()+interval '5 minutes','CLAIMED',1) returning * into v_run;
  v_result := ops.prepare_domain_command(v_event.event_pk,'file_evidence_worker',v_run.lease_token,'{"evidence":{"type":"OTHER"}}'::jsonb,'Evidence',null);
  if v_result->>'validation_status' <> 'INVALID' then raise exception '3E missing file should INVALID: %',v_result; end if;
  if not (v_result->'validation_errors' @> '[{"code":"FILE_INTAKE_REQUIRED"}]'::jsonb) then raise exception '3E missing file error code FAIL: %',v_result; end if;

  raise notice 'PASS: Part 3E candidate/client/evidence domain command smoke';
end $$;

delete from ops.event_effects where event_pk in (select event_pk from ops.events where source_system='test3e');
delete from ops.domain_commands where event_pk in (select event_pk from ops.events where source_system='test3e');
delete from ops.worker_runs where event_pk in (select event_pk from ops.events where source_system='test3e');
delete from ops.dead_letters where event_pk in (select event_pk from ops.events where source_system='test3e');
delete from ops.approvals where event_pk in (select event_pk from ops.events where source_system='test3e');
delete from ops.scheduled_signals where emitted_event_pk in (select event_pk from ops.events where source_system='test3e');
delete from ops.events where source_system='test3e';
delete from ops.file_intake where source_system='test3e';
delete from ops.raw_inputs where source_system='test3e';

commit;
