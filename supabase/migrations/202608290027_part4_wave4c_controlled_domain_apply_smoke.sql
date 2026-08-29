begin;

do $$
declare
  v_raw text;
  v_event ops.events;
  v_run uuid;
  v_cmd uuid;
  v_cmd_client uuid;
  v_cmd_job_conflict uuid;
  v_cmd_candidate_create uuid;
  v_cmd_evidence uuid;
  v_cmd_consent uuid;
  v_cmd_attribution uuid;
  v_res jsonb;
  v_client_id text;
  v_job_id text;
  v_evidence_id text;
  v_file_id text;
  v_consent_id text;
  v_file_intake uuid;
  v_count int;
  v_wage numeric;
  v_next_client bigint;
  v_next_job bigint;
  v_next_file bigint;
  v_next_evidence bigint;
  v_next_consent bigint;
  v_next_dq bigint;
begin
  select next_number into v_next_client from config.id_allocators where entity_key='Client';
  select next_number into v_next_job from config.id_allocators where entity_key='Job';
  select next_number into v_next_file from config.id_allocators where entity_key='File Registry';
  select next_number into v_next_evidence from config.id_allocators where entity_key='Evidence';
  select next_number into v_next_consent from config.id_allocators where entity_key='Consent';
  select next_number into v_next_dq from config.id_allocators where entity_key='DQ Issue';

  insert into core.partners(partner_id,partner_name,status) values('WC-P-9999','Part4C Test Partner','ACTIVE');
  insert into core.candidates(candidate_id,nickname,preferred_job,status) values('TST-C-4C-000001','Test Candidate','OLD JOB','ACTIVE');

  -- Candidate update command: first prove gate blocks, then enable TEST gate and retry.
  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4C-RAW-CAND-UPD','TEST','TEST','test://4c/candidate-update','RAW_STORED');
  v_event:=ops.register_event('1.0','TEST','TST4C-EVT-CAND-UPD','TST4C-IDEM-CAND-UPD','TST4C-TRACE-CAND-UPD','candidate.profile.updated',now(),'TST4C-RAW-CAND-UPD',null,null);
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'candidate_worker','4c-smoke',now()+interval '10 minutes','CLAIMED',1) returning worker_run_pk into v_run;
  insert into ops.domain_commands(command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,target_entity_id,source_raw_input_id,payload,validation_status,apply_status)
  values('TST4C-CMD-CAND-UPD',v_event.event_pk,v_run,'candidate_worker','candidate.update_proposal','Candidate','TST-C-4C-000001','TST4C-RAW-CAND-UPD',jsonb_build_object('fields',jsonb_build_object('preferred_job','NEW JOB','relocation_ready',true)),'VALID','READY') returning command_pk into v_cmd;

  v_res:=ops.apply_domain_command(v_cmd,'part4c-smoke');
  if v_res->>'apply_status'<>'BLOCKED' or v_res->>'reason'<>'GATE_DISABLED' then raise exception '4C gate-block test failed: %',v_res; end if;
  if (select preferred_job from core.candidates where candidate_id='TST-C-4C-000001')<>'OLD JOB' then raise exception 'gate-block mutated Candidate'; end if;

  update config.system_settings set setting_value='true'::jsonb where setting_key='business_master_apply_enabled';
  update config.system_settings set setting_value='true'::jsonb where setting_key='postgres_docs_write_enabled';
  update config.system_settings set setting_value='true'::jsonb where setting_key='postgres_consent_write_enabled';

  v_res:=ops.apply_domain_command(v_cmd,'part4c-smoke');
  if v_res->>'apply_status'<>'APPLIED' then raise exception 'Candidate update apply failed: %',v_res; end if;
  if (select preferred_job from core.candidates where candidate_id='TST-C-4C-000001')<>'NEW JOB' then raise exception 'Candidate update not applied'; end if;

  -- Partner attribution.
  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4C-RAW-ATTR','TEST','TEST','test://4c/attribution','RAW_STORED');
  v_event:=ops.register_event('1.0','TEST','TST4C-EVT-ATTR','TST4C-IDEM-ATTR','TST4C-TRACE-ATTR','partner.referral.received',now(),'TST4C-RAW-ATTR',null,null);
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'attribution_worker','4c-smoke',now()+interval '10 minutes','CLAIMED',1) returning worker_run_pk into v_run;
  insert into ops.domain_commands(command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,target_entity_id,source_raw_input_id,payload,validation_status,apply_status)
  values('TST4C-CMD-ATTR',v_event.event_pk,v_run,'attribution_worker','partner_attribution.proposal','Candidate/Partner','TST-C-4C-000001','TST4C-RAW-ATTR',jsonb_build_object('fields',jsonb_build_object('candidate_id','TST-C-4C-000001','partner_id','WC-P-9999')),'VALID','READY') returning command_pk into v_cmd_attribution;
  v_res:=ops.apply_domain_command(v_cmd_attribution,'part4c-smoke');
  if v_res->>'apply_status'<>'APPLIED' or (select partner_id from core.candidates where candidate_id='TST-C-4C-000001')<>'WC-P-9999' then raise exception 'Attribution apply failed: %',v_res; end if;

  -- Candidate create must stay blocked while Candidate ID source conflict exists.
  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4C-RAW-CAND-NEW','TEST','TEST','test://4c/candidate-new','RAW_STORED');
  v_event:=ops.register_event('1.0','TEST','TST4C-EVT-CAND-NEW','TST4C-IDEM-CAND-NEW','TST4C-TRACE-CAND-NEW','candidate.lead.received',now(),'TST4C-RAW-CAND-NEW',null,null);
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'candidate_intake','4c-smoke',now()+interval '10 minutes','CLAIMED',1) returning worker_run_pk into v_run;
  insert into ops.domain_commands(command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,source_raw_input_id,payload,validation_status,apply_status)
  values('TST4C-CMD-CAND-NEW',v_event.event_pk,v_run,'candidate_intake','candidate.upsert_proposal','Candidate','TST4C-RAW-CAND-NEW',jsonb_build_object('candidate',jsonb_build_object('nickname','Blocked New Candidate')),'VALID','READY') returning command_pk into v_cmd_candidate_create;
  v_res:=ops.apply_domain_command(v_cmd_candidate_create,'part4c-smoke');
  if v_res->>'apply_status'<>'BLOCKED' or v_res->>'reason'<>'CANDIDATE_ID_SOURCE_CONFLICT' then raise exception 'Candidate conflict block failed: %',v_res; end if;

  -- Client + Job create.
  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4C-RAW-CLIENTJOB','TEST','TEST','test://4c/client-job','RAW_STORED');
  v_event:=ops.register_event('1.0','TEST','TST4C-EVT-CLIENTJOB','TST4C-IDEM-CLIENTJOB','TST4C-TRACE-CLIENTJOB','client.demand.received',now(),'TST4C-RAW-CLIENTJOB',null,null);
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'client_job_worker','4c-smoke',now()+interval '10 minutes','CLAIMED',1) returning worker_run_pk into v_run;
  insert into ops.domain_commands(command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,source_raw_input_id,payload,validation_status,apply_status)
  values('TST4C-CMD-CLIENTJOB',v_event.event_pk,v_run,'client_job_worker','client_job.upsert_proposal','Client/Job','TST4C-RAW-CLIENTJOB',jsonb_build_object(
    'client',jsonb_build_object('company_name','Part4C Factory','province','สระบุรี','payment_term','30 DAYS'),
    'job',jsonb_build_object('position_name','Warehouse Staff','province','สระบุรี','headcount',5,'wage',20000,'shift','DAY','start_date','2026-09-01','payment_term','30 DAYS','status','OPEN')
  ),'VALID','READY') returning command_pk into v_cmd_client;
  v_res:=ops.apply_domain_command(v_cmd_client,'part4c-smoke');
  if v_res->>'apply_status'<>'APPLIED' then raise exception 'Client/Job apply failed: %',v_res; end if;
  select target_entity_id into v_job_id from ops.domain_commands where command_pk=v_cmd_client;
  select client_id into v_client_id from core.jobs where job_id=v_job_id;
  if v_client_id is null or v_job_id is null then raise exception 'Client/Job IDs missing'; end if;
  select count(*) into v_count from core.clients where client_id=v_client_id; if v_count<>1 then raise exception 'Client not created'; end if;
  select count(*) into v_count from core.jobs where job_id=v_job_id; if v_count<>1 then raise exception 'Job not created'; end if;

  -- Idempotent replay must not duplicate master/effect.
  v_res:=ops.apply_domain_command(v_cmd_client,'part4c-smoke');
  if coalesce((v_res->>'duplicate_apply')::boolean,false) is not true then raise exception 'Duplicate apply not recognized: %',v_res; end if;
  select count(*) into v_count from ops.event_effects where event_pk=(select event_pk from ops.domain_commands where command_pk=v_cmd_client) and effect_key='master_apply|TST4C-CMD-CLIENTJOB';
  if v_count<>1 then raise exception 'Master effect duplicated'; end if;

  -- Protected Job term conflict must open DQ and preserve wage.
  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4C-RAW-JOB-CONFLICT','TEST','TEST','test://4c/job-conflict','RAW_STORED');
  v_event:=ops.register_event('1.0','TEST','TST4C-EVT-JOB-CONFLICT','TST4C-IDEM-JOB-CONFLICT','TST4C-TRACE-JOB-CONFLICT','job.detail.confirmed',now(),'TST4C-RAW-JOB-CONFLICT',null,null);
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'job_worker','4c-smoke',now()+interval '10 minutes','CLAIMED',1) returning worker_run_pk into v_run;
  insert into ops.domain_commands(command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,target_entity_id,source_raw_input_id,payload,validation_status,apply_status)
  values('TST4C-CMD-JOB-CONFLICT',v_event.event_pk,v_run,'job_worker','job.update_proposal','Job',v_job_id,'TST4C-RAW-JOB-CONFLICT',jsonb_build_object('fields',jsonb_build_object('wage',21000)),'VALID','READY') returning command_pk into v_cmd_job_conflict;
  v_res:=ops.apply_domain_command(v_cmd_job_conflict,'part4c-smoke');
  if v_res->>'apply_status'<>'BLOCKED' or v_res->>'reason'<>'DQ_CONFLICT' then raise exception 'DQ conflict did not block: %',v_res; end if;
  select wage into v_wage from core.jobs where job_id=v_job_id; if v_wage<>20000 then raise exception 'Protected wage overwritten'; end if;
  select count(*) into v_count from ops.data_quality_issues where issue_type='DOMAIN_APPLY_CONFLICT' and entity_id=v_job_id and field_name='wage' and status='OPEN'; if v_count<>1 then raise exception 'DQ issue not created exactly once'; end if;
  v_res:=ops.apply_domain_command(v_cmd_job_conflict,'part4c-smoke');
  select count(*) into v_count from ops.data_quality_issues where issue_type='DOMAIN_APPLY_CONFLICT' and entity_id=v_job_id and field_name='wage' and status='OPEN'; if v_count<>1 then raise exception 'DQ issue duplicated on retry'; end if;

  -- File Intake -> File Registry -> Evidence -> Candidate link.
  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4C-RAW-FILE','TEST','TEST','test://4c/file','RAW_STORED');
  insert into ops.file_intake(raw_input_id,source_system,provider_file_ref,original_filename,content_type,size_bytes,checksum_sha256,mirror_status,sensitive,metadata)
  values('TST4C-RAW-FILE','TEST','test-provider-file-ref','candidate.jpg','image/jpeg',1234,repeat('a',64),'SOURCE_NOT_MIRRORED',true,jsonb_build_object('source_url','test://source/candidate.jpg','description','Part4C smoke evidence')) returning file_intake_pk into v_file_intake;
  v_event:=ops.register_event('1.0','TEST','TST4C-EVT-FILE','TST4C-IDEM-FILE','TST4C-TRACE-FILE','file.uploaded',now(),'TST4C-RAW-FILE',null,null);
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'file_evidence_worker','4c-smoke',now()+interval '10 minutes','CLAIMED',1) returning worker_run_pk into v_run;
  insert into ops.domain_commands(command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,source_raw_input_id,payload,validation_status,apply_status)
  values('TST4C-CMD-EVIDENCE',v_event.event_pk,v_run,'file_evidence_worker','evidence.register_proposal','Evidence','TST4C-RAW-FILE',jsonb_build_object('file_intake_pk',v_file_intake::text,'evidence',jsonb_build_object('evidence_type','PROFILE_PHOTO','evidence_class','OPERATIONAL_EVIDENCE','entity_type','Candidate','entity_id','TST-C-4C-000001','link_role','PROFILE_PHOTO')),'VALID','READY') returning command_pk into v_cmd_evidence;
  v_res:=ops.apply_domain_command(v_cmd_evidence,'part4c-smoke');
  if v_res->>'apply_status'<>'APPLIED' then raise exception 'Evidence apply failed: %',v_res; end if;
  v_evidence_id:=v_res->>'target_entity_id';
  select file_id into v_file_id from docs.evidence where evidence_id=v_evidence_id;
  if v_file_id is null then raise exception 'Evidence file missing'; end if;
  if (select storage_status from docs.files where file_id=v_file_id)<>'SOURCE_NOT_MIRRORED' then raise exception 'SOURCE_NOT_MIRRORED not preserved'; end if;
  select count(*) into v_count from docs.evidence_links where evidence_id=v_evidence_id and entity_type='Candidate' and entity_id='TST-C-4C-000001' and link_role='PROFILE_PHOTO'; if v_count<>1 then raise exception 'Evidence link missing'; end if;

  -- Consent backed by Evidence.
  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4C-RAW-CONSENT','TEST','TEST','test://4c/consent','RAW_STORED');
  v_event:=ops.register_event('1.0','TEST','TST4C-EVT-CONSENT','TST4C-IDEM-CONSENT','TST4C-TRACE-CONSENT','candidate.consent.received',now(),'TST4C-RAW-CONSENT',null,null);
  insert into ops.worker_runs(event_pk,worker_key,worker_instance,lease_until,status,attempt_no)
  values(v_event.event_pk,'consent_worker','4c-smoke',now()+interval '10 minutes','CLAIMED',1) returning worker_run_pk into v_run;
  insert into ops.domain_commands(command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,target_entity_id,source_raw_input_id,payload,validation_status,apply_status)
  values('TST4C-CMD-CONSENT',v_event.event_pk,v_run,'consent_worker','consent.record_proposal','Consent','TST-C-4C-000001','TST4C-RAW-CONSENT',jsonb_build_object('consent',jsonb_build_object('candidate_id','TST-C-4C-000001','purpose_code','JOB_MATCHING','decision','GRANTED','effective_at',now()::text,'evidence_id',v_evidence_id)),'VALID','READY') returning command_pk into v_cmd_consent;
  v_res:=ops.apply_domain_command(v_cmd_consent,'part4c-smoke');
  if v_res->>'apply_status'<>'APPLIED' then raise exception 'Consent apply failed: %',v_res; end if;
  v_consent_id:=v_res->>'target_entity_id';
  if not exists(select 1 from privacy.consents where consent_id=v_consent_id and candidate_id='TST-C-4C-000001' and evidence_id=v_evidence_id and decision='GRANTED') then raise exception 'Consent record missing'; end if;

  -- Audit and contract coverage.
  select count(*) into v_count from ops.master_apply_contracts where active=true; if v_count<>8 then raise exception 'Expected 8 active apply contracts, got %',v_count; end if;
  select count(*) into v_count from ops.domain_command_apply_audit where command_pk in (v_cmd,v_cmd_attribution,v_cmd_candidate_create,v_cmd_client,v_cmd_job_conflict,v_cmd_evidence,v_cmd_consent); if v_count<>7 then raise exception 'Apply audit coverage mismatch: %',v_count; end if;

  -- Verify test transaction advanced allocators internally (proving allocators were actually used).
  if (select next_number from config.id_allocators where entity_key='Client')<=v_next_client then raise exception 'Client allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='Job')<=v_next_job then raise exception 'Job allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='File Registry')<=v_next_file then raise exception 'File allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='Evidence')<=v_next_evidence then raise exception 'Evidence allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='Consent')<=v_next_consent then raise exception 'Consent allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='DQ Issue')<=v_next_dq then raise exception 'DQ allocator not exercised'; end if;
end $$;

rollback;