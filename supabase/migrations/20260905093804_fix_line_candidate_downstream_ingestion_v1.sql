-- MYC-DQ-000011: continue-state LINE downstream ingestion fix.
-- Keeps canonical LINE -> Raw -> Parse/Validate -> Route -> Master Effect flow.
-- Does not enable Postgres business-master writes or change the operational Source of Truth.

create or replace function ops.parse_line_candidate_raw_v1(p_raw_input_id text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_raw ops.raw_inputs;
  v_text text;
  v_lines text[];
  v_line text;
  v_name text;
  v_phone text;
  v_dob date;
  v_m text[];
  v_day int;
  v_month int;
  v_year int;
  v_mon text;
  v_education text;
  v_age int;
  v_weight int;
  v_height int;
  v_origin text;
  v_tattoo boolean;
  v_job_id text;
  v_partner_id text;
  v_classification text := 'CONTEXT_OR_OTHER';
  v_missing jsonb := '[]'::jsonb;
  v_conf numeric := 0;
  v_numeric_lines int[] := '{}';
  v_dedupe_key text;
begin
  select * into v_raw from ops.raw_inputs where raw_input_id=p_raw_input_id;
  if not found then raise exception 'RAW_INPUT_NOT_FOUND:%',p_raw_input_id; end if;
  v_text:=coalesce(v_raw.raw_summary,'');
  if v_raw.source_system<>'LINE' then
    return jsonb_build_object('classification','NOT_LINE','raw_input_id',p_raw_input_id,'confidence',100,'missing_fields','[]'::jsonb,'parser_version','line_candidate_v1');
  end if;
  if v_raw.content_type='LINE_IMAGE' then
    return jsonb_build_object('classification','EVIDENCE_IMAGE','raw_input_id',p_raw_input_id,'confidence',100,'missing_fields',jsonb_build_array('candidate_relation'),'parser_version','line_candidate_v1');
  end if;
  if v_raw.content_type<>'LINE_TEXT' then
    return jsonb_build_object('classification','UNSUPPORTED_CONTENT','raw_input_id',p_raw_input_id,'confidence',100,'missing_fields','[]'::jsonb,'parser_version','line_candidate_v1');
  end if;
  if v_text ~* 'MYC-(OFFICIAL|GROUP)-FINAL-[0-9]+' or v_text ilike '%bot ใช้ได้แล้ว%' or v_text ilike '%เทส%' then
    return jsonb_build_object('classification','TEST_CONTROL','raw_input_id',p_raw_input_id,'confidence',100,'missing_fields','[]'::jsonb,'parser_version','line_candidate_v1');
  end if;

  v_lines:=regexp_split_to_array(replace(v_text,E'\r',''),E'\n');
  foreach v_line in array v_lines loop
    v_line:=btrim(v_line);
    if v_line='' then continue; end if;
    if v_phone is null then
      v_m:=regexp_match(v_line,'(0[0-9]{9})');
      if v_m is not null then v_phone:=v_m[1]; end if;
    end if;
    if v_dob is null then
      v_m:=regexp_match(v_line,'([0-9]{1,2})/([0-9]{1,2})/([0-9]{4})');
      if v_m is not null then
        v_day:=v_m[1]::int; v_month:=v_m[2]::int; v_year:=v_m[3]::int;
        if v_year>=2400 then v_year:=v_year-543; end if;
        begin v_dob:=make_date(v_year,v_month,v_day); exception when others then v_dob:=null; end;
      else
        v_m:=regexp_match(v_line,'([0-9]{1,2})\s*(ม\.ค\.?|ก\.พ\.?|มี\.ค\.?|เม\.ย\.?|พ\.ค\.?|มิ\.ย\.?|ก\.ค\.?|ส\.ค\.?|ก\.ย\.?|ต\.ค\.?|พ\.ย\.?|ธ\.ค\.?)\s*([0-9]{4})');
        if v_m is not null then
          v_day:=v_m[1]::int; v_mon:=v_m[2]; v_year:=v_m[3]::int;
          if v_year>=2400 then v_year:=v_year-543; end if;
          v_month:=case when v_mon like 'ม.ค%' then 1 when v_mon like 'ก.พ%' then 2 when v_mon like 'มี.ค%' then 3 when v_mon like 'เม.ย%' then 4 when v_mon like 'พ.ค%' then 5 when v_mon like 'มิ.ย%' then 6 when v_mon like 'ก.ค%' then 7 when v_mon like 'ส.ค%' then 8 when v_mon like 'ก.ย%' then 9 when v_mon like 'ต.ค%' then 10 when v_mon like 'พ.ย%' then 11 when v_mon like 'ธ.ค%' then 12 end;
          begin v_dob:=make_date(v_year,v_month,v_day); exception when others then v_dob:=null; end;
        end if;
      end if;
    end if;
    if v_education is null and v_line ~* 'วุฒิ' then
      v_education:=nullif(btrim(regexp_replace(v_line,'^.*วุฒิ(การศึกษา)?\s*[:：]?\s*','','i')),'');
    end if;
    if v_age is null then
      v_m:=regexp_match(v_line,'อายุ\s*[:：]?\s*([0-9]{1,2})');
      if v_m is not null then v_age:=v_m[1]::int; end if;
    end if;
    if v_weight is null then
      v_m:=regexp_match(v_line,'(?:น้ำหนัก|น\.น)\s*[:：]?\s*([0-9]{2,3})','i');
      if v_m is not null then v_weight:=v_m[1]::int; end if;
    end if;
    if v_height is null then
      v_m:=regexp_match(v_line,'(?:ส่วนสูง|สูง|ส\.ส)\s*[:：]?\s*([0-9]{2,3})','i');
      if v_m is not null then v_height:=v_m[1]::int; end if;
    end if;
    if v_origin is null and v_line ~ 'มาจาก' then
      v_origin:=nullif(btrim(regexp_replace(v_line,'^.*มาจาก\s*','','i')),'');
    end if;
    if v_line ~ 'รอยสัก|ลอยสัก' then
      if v_line ~ 'ไม่มี' then v_tattoo:=false; elsif v_line ~ 'มี' then v_tattoo:=true; end if;
    end if;
    if v_line ~ '^[0-9]{2,3}$' then v_numeric_lines:=array_append(v_numeric_lines,v_line::int); end if;
    if v_name is null then
      if v_line ~ '^สมัครเน็กซ์แคนรอบวันจันทร์' then
        v_name:=nullif(btrim(regexp_replace(v_line,'^สมัครเน็กซ์แคนรอบวันจันทร์\s*','','i')),'');
      elsif v_line ~ '[ก-๙]+\s+[ก-๙]+' and v_line !~ 'สมัคร|เน็กซ์|วุฒิ|น้ำหนัก|ส่วนสูง|อายุ|เบอร์|โทร|รอยสัก|ลอยสัก|มาจาก|วันเดือนปีเกิด' then
        v_name:=v_line;
      end if;
      if v_name is not null then v_name:=btrim(regexp_replace(v_name,'^(นางสาว|นาง|นาย|น\.ส\.)\s*','','i')); end if;
    end if;
  end loop;
  if v_weight is null and cardinality(v_numeric_lines)>=1 then v_weight:=v_numeric_lines[1]; end if;
  if v_height is null and cardinality(v_numeric_lines)>=2 then v_height:=v_numeric_lines[2]; end if;
  if v_text ilike '%เน็กซ์แคน%' or v_text ilike '%next can%' then v_job_id:='MYC-J-000013'; end if;
  if v_raw.sender_ref='U1738e96a0eff5456a4656a2435712447' or coalesce(v_raw.metadata->>'sender_display_name','') ilike '%มิ้นท์%' then v_partner_id:='MYC-P-0001'; end if;
  if v_phone is not null and v_name is not null and v_job_id is not null and (v_dob is not null or v_education is not null or v_age is not null) then v_classification:='CANDIDATE_LEAD'; end if;
  if v_classification='CANDIDATE_LEAD' then
    if v_name is null then v_missing:=v_missing||jsonb_build_array('full_name'); end if;
    if v_phone is null then v_missing:=v_missing||jsonb_build_array('phone'); end if;
    if v_dob is null then v_missing:=v_missing||jsonb_build_array('date_of_birth'); end if;
    if v_education is null then v_missing:=v_missing||jsonb_build_array('education'); end if;
    if v_origin is null then v_missing:=v_missing||jsonb_build_array('origin_area'); end if;
    v_missing:=v_missing||jsonb_build_array('ready_date');
    v_conf:=case when v_name is not null and v_phone is not null and v_dob is not null and v_education is not null and v_partner_id is not null and v_job_id is not null then case when v_origin is null then 96 else 98 end else 90 end;
    v_dedupe_key:=encode(extensions.digest(lower(regexp_replace(coalesce(v_name,''),'\s+','','g'))||'|'||coalesce(v_phone,'')||'|'||coalesce(v_dob::text,''),'sha256'),'hex');
  else
    v_conf:=case when v_classification in ('TEST_CONTROL','EVIDENCE_IMAGE') then 100 else 85 end;
  end if;
  return jsonb_build_object('classification',v_classification,'raw_input_id',p_raw_input_id,'parser_version','line_candidate_v1','confidence',v_conf,'missing_fields',v_missing,'dedupe_rule','NAME_PHONE_DOB','dedupe_key',v_dedupe_key,'candidate',jsonb_strip_nulls(jsonb_build_object('full_name',v_name,'phone',v_phone,'date_of_birth',v_dob,'age',v_age,'education',v_education,'weight_kg',v_weight,'height_cm',v_height,'origin_area',v_origin,'tattoo_outside_clothing',v_tattoo,'preferred_job','Next Can','job_id',v_job_id,'partner_id',v_partner_id,'source_type','Sourcing Partner','status','SCREENING')),'job_id',v_job_id,'partner_id',v_partner_id);
end;
$$;

create or replace function ops.route_line_raw_event_v1(p_event_pk uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_event ops.events; v_raw ops.raw_inputs; v_parse jsonb; v_child ops.events; v_effect_key text;
begin
  select * into v_event from ops.events where event_pk=p_event_pk;
  if not found then raise exception 'EVENT_NOT_FOUND'; end if;
  if v_event.event_type<>'channel.raw.received' or v_event.source_system<>'LINE' then return jsonb_build_object('routed',false,'reason','NOT_LINE_RAW_EVENT'); end if;
  select * into v_raw from ops.raw_inputs where raw_input_id=v_event.raw_input_id;
  if not found then raise exception 'RAW_INPUT_NOT_FOUND'; end if;
  v_effect_key:='line_ingestion_classification|'||v_raw.raw_input_id;
  if exists(select 1 from ops.event_effects where effect_key=v_effect_key) then
    select coalesce(v_raw.metadata->'line_ingestion','{}'::jsonb) into v_parse;
    return jsonb_build_object('routed',true,'duplicate',true,'raw_input_id',v_raw.raw_input_id,'parse',v_parse);
  end if;
  v_parse:=ops.parse_line_candidate_raw_v1(v_raw.raw_input_id);
  update ops.raw_inputs set classification=v_parse->>'classification',entity_type=case when v_parse->>'classification'='CANDIDATE_LEAD' then 'CandidateLead' else entity_type end,ai_parsed=true,ai_confidence=nullif(v_parse->>'confidence','')::numeric,metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('line_ingestion',v_parse,'line_ingestion_routed_at',now()),updated_at=now() where raw_input_id=v_raw.raw_input_id;
  if v_parse->>'classification'='CANDIDATE_LEAD' then
    v_child:=ops.register_event(v_event.schema_version,'LINE','DERIVED:CANDIDATE_LEAD:'||v_raw.raw_input_id,encode(extensions.digest('candidate.lead.received|'||v_raw.raw_input_id,'sha256'),'hex'),v_event.trace_id,'candidate.lead.received',v_event.occurred_at,v_raw.raw_input_id,v_event.correlation_id,v_event.event_id);
    perform ops.register_effect(v_event.event_pk,'line_ingestion_classification',v_effect_key,'CandidateLead',null,'ops.events:'||v_child.event_pk::text);
    return jsonb_build_object('routed',true,'raw_input_id',v_raw.raw_input_id,'classification','CANDIDATE_LEAD','child_event_pk',v_child.event_pk,'parse',v_parse);
  end if;
  perform ops.register_effect(v_event.event_pk,'line_ingestion_classification',v_effect_key,'RawInput',v_raw.raw_input_id,'classification:'||(v_parse->>'classification'));
  return jsonb_build_object('routed',true,'raw_input_id',v_raw.raw_input_id,'classification',v_parse->>'classification','parse',v_parse);
end; $$;

create or replace function ops.run_line_candidate_ingestion_tick(p_now timestamptz default now(), p_limit integer default 100, p_actor text default 'db_scheduler')
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; v_route jsonb; v_parse jsonb; v_cmd jsonb; v_routed int:=0; v_candidate_events int:=0; v_commands int:=0; v_errors int:=0;
begin
  if p_limit<1 or p_limit>200 then raise exception 'limit must be between 1 and 200'; end if;
  perform ops.record_worker_heartbeat('candidate_intake','db_scheduler','test','HEALTHY','line-ingestion-v1',jsonb_build_object('actor',p_actor),p_now);
  for r in select e.event_pk from ops.events e where e.event_type='channel.raw.received' and e.source_system='LINE' and not exists(select 1 from ops.event_effects ee where ee.effect_key='line_ingestion_classification|'||e.raw_input_id) order by e.received_at,e.created_at limit p_limit loop
    begin v_route:=ops.route_line_raw_event_v1(r.event_pk); v_routed:=v_routed+1; if v_route->>'classification'='CANDIDATE_LEAD' then v_candidate_events:=v_candidate_events+1; end if; exception when others then v_errors:=v_errors+1; end;
  end loop;
  for r in select * from ops.claim_events('candidate_intake','db_scheduler',p_limit,120,p_now) loop
    begin
      v_parse:=ops.parse_line_candidate_raw_v1(r.raw_input_id);
      if v_parse->>'classification'<>'CANDIDATE_LEAD' then perform ops.finish_event_failure(r.worker_run_pk,r.lease_token,'VALIDATION','Derived candidate event no longer parses as candidate',jsonb_build_object('raw_input_id',r.raw_input_id),p_now); v_errors:=v_errors+1; continue; end if;
      v_cmd:=ops.prepare_domain_command(r.event_pk,'candidate_intake',r.lease_token,jsonb_build_object('candidate',coalesce(v_parse->'candidate','{}'::jsonb)||jsonb_build_object('source_type','Sourcing Partner','preferred_job','Next Can','status','SCREENING'),'private_contact',jsonb_build_object('full_name',v_parse#>>'{candidate,full_name}','phone',v_parse#>>'{candidate,phone}','date_of_birth',v_parse#>>'{candidate,date_of_birth}'),'partner_id',v_parse->>'partner_id','job_id',v_parse->>'job_id','dedupe_rule','NAME_PHONE_DOB','dedupe_key',v_parse->>'dedupe_key','ai_confidence',v_parse->'confidence','missing_fields',v_parse->'missing_fields','parser_version','line_candidate_v1','source_raw_input_id',r.raw_input_id,'operational_master_target','GOOGLE_SHEETS_DRIVE'),'Candidate',null);
      perform ops.finish_event_success(r.worker_run_pk,r.lease_token,'candidate_proposal_prepared','candidate_proposal|'||r.raw_input_id,'CandidateLead',null,'ops.domain_commands:'||(v_cmd->>'command_pk'),jsonb_build_object('raw_input_id',r.raw_input_id,'command_pk',v_cmd->>'command_pk','validation_status',v_cmd->>'validation_status','master_apply_deferred_to','GOOGLE_SHEETS_DRIVE'),p_now);
      update ops.raw_inputs set metadata=metadata||jsonb_build_object('candidate_command_pk',v_cmd->>'command_pk','candidate_command_validation',v_cmd->>'validation_status','candidate_worker_completed_at',p_now),updated_at=now() where raw_input_id=r.raw_input_id;
      v_commands:=v_commands+1;
    exception when others then
      begin perform ops.finish_event_failure(r.worker_run_pk,r.lease_token,'VALIDATION',sqlerrm,jsonb_build_object('raw_input_id',r.raw_input_id),p_now); exception when others then null; end;
      v_errors:=v_errors+1;
    end;
  end loop;
  return jsonb_build_object('routed_raw_events',v_routed,'candidate_events_created',v_candidate_events,'candidate_commands_prepared',v_commands,'errors',v_errors,'actor',p_actor,'ran_at',p_now);
end; $$;

-- Correct legacy Candidate ID validation to canonical MYC-C-######.
create or replace function ops.validate_domain_command(p_command_pk uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_cmd ops.domain_commands; v_event ops.events; v_contract ops.domain_worker_contracts; v_errors jsonb:='[]'::jsonb; v_status text:='VALID'; v_has_file boolean:=false;
begin
  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk for update;
  if not found then raise exception 'unknown command_pk: %',p_command_pk; end if;
  select * into v_event from ops.events where event_pk=v_cmd.event_pk;
  select * into v_contract from ops.domain_worker_contracts where worker_key=v_cmd.worker_key and active=true;
  if not found then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','CONTRACT_MISSING','message','active worker contract not found'));
  else
    if not (v_event.event_type=any(v_contract.allowed_event_types)) then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','EVENT_NOT_ALLOWED','message','event type is not allowed by worker contract')); end if;
    if v_cmd.command_type<>v_contract.command_type then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','COMMAND_TYPE_MISMATCH','message','command type does not match worker contract')); end if;
    if v_contract.requires_raw_input and v_cmd.source_raw_input_id is null then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','RAW_INPUT_REQUIRED','message','material domain command requires raw input provenance')); end if;
    if v_contract.requires_file_intake then select exists(select 1 from ops.file_intake f where f.raw_input_id=v_cmd.source_raw_input_id) into v_has_file; if not v_has_file then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','FILE_INTAKE_REQUIRED','message','evidence command requires registered file intake')); end if; end if;
  end if;
  if jsonb_typeof(v_cmd.payload)<>'object' or v_cmd.payload='{}'::jsonb then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','PAYLOAD_REQUIRED','message','command payload must be a non-empty JSON object')); end if;
  if v_cmd.worker_key in ('candidate_intake','candidate_worker') then
    if not (v_cmd.payload?'candidate' or v_cmd.payload?'fields') then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','CANDIDATE_FIELDS_REQUIRED','message','candidate command requires candidate or fields object')); end if;
    if v_cmd.target_entity_id is not null and v_cmd.target_entity_id !~ '^MYC-C-[0-9]{6}$' then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','INVALID_CANDIDATE_ID','message','known Candidate ID must match MYC-C-######')); end if;
  elsif v_cmd.worker_key in ('client_job_worker','job_worker') then
    if not (v_cmd.payload?'client' or v_cmd.payload?'job' or v_cmd.payload?'fields') then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','CLIENT_JOB_FIELDS_REQUIRED','message','client/job command requires client, job, or fields object')); end if;
  elsif v_cmd.worker_key='file_evidence_worker' then
    if not (v_cmd.payload?'file' or v_cmd.payload?'evidence' or v_cmd.payload?'file_intake_pk') then v_errors:=v_errors||jsonb_build_array(jsonb_build_object('code','EVIDENCE_FIELDS_REQUIRED','message','evidence command requires file/evidence reference')); end if;
  end if;
  if jsonb_array_length(v_errors)>0 then v_status:='INVALID'; end if;
  update ops.domain_commands set validation_status=v_status,validation_errors=v_errors,apply_status=case when v_status='VALID' then 'READY' else 'PROPOSED' end,updated_at=now() where command_pk=p_command_pk returning * into v_cmd;
  return jsonb_build_object('command_pk',v_cmd.command_pk,'command_key',v_cmd.command_key,'validation_status',v_cmd.validation_status,'apply_status',v_cmd.apply_status,'validation_errors',v_cmd.validation_errors);
end; $$;

create or replace function ops.complete_raw_capture_event(p_event_pk uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_event ops.events%rowtype; v_route jsonb;
begin
  select * into v_event from ops.events where event_pk=p_event_pk for update;
  if not found then return jsonb_build_object('ok',false,'reason','EVENT_NOT_FOUND'); end if;
  if v_event.event_type<>'channel.raw.received' then return jsonb_build_object('ok',false,'reason','NOT_RAW_CAPTURE_EVENT'); end if;
  begin v_route:=ops.route_line_raw_event_v1(p_event_pk); exception when others then v_route:=jsonb_build_object('routed',false,'reason','DOWNSTREAM_ROUTE_ERROR','error',left(sqlerrm,500)); update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('line_ingestion_route_error',left(sqlerrm,500),'line_ingestion_route_error_at',now()),updated_at=now() where raw_input_id=v_event.raw_input_id; end;
  if v_event.processing_state not in ('COMPLETED'::ops.event_processing_state,'CANCELLED'::ops.event_processing_state) then update ops.events set processing_state='COMPLETED'::ops.event_processing_state,updated_at=now() where event_pk=p_event_pk; end if;
  return jsonb_build_object('ok',true,'event_pk',p_event_pk,'processing_state','COMPLETED','downstream_route',v_route);
end; $$;

create or replace function ops.scheduler_tick(p_now timestamptz default now(), p_limit integer default 100, p_trigger_source text default 'MANUAL')
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_retry_created integer; v_result jsonb; v_ingest jsonb;
begin
  v_retry_created:=ops.sync_retry_schedules(p_now,p_limit);
  v_result:=ops.run_due_schedules(p_now,p_limit,p_trigger_source);
  update ops.scheduler_runs set retry_schedules_created=v_retry_created where scheduler_run_pk=(v_result->>'scheduler_run_pk')::uuid;
  begin v_ingest:=ops.run_line_candidate_ingestion_tick(p_now,least(p_limit,200),'scheduler_tick'); exception when others then v_ingest:=jsonb_build_object('errors',1,'scheduler_error',left(sqlerrm,500)); end;
  return v_result||jsonb_build_object('retry_schedules_created',v_retry_created,'line_candidate_ingestion',v_ingest);
end; $$;

-- Reconcile Candidate allocator to the operational Data Hub snapshot before Master Effect.
update config.id_allocators
set next_number=greatest(next_number,14),source_ref='Live DataHub:98_System_Config verified 2026-09-05 / MYC-DQ-000011',source_snapshot_at=now(),updated_at=now()
where entity_key='Candidate' and prefix='MYC-C-' and allocation_enabled=true and conflict_status='NONE';

-- Controlled backfill through the same downstream worker path; no direct Candidate Master write.
select ops.run_line_candidate_ingestion_tick(now(),100,'MYC-DQ-000011_BACKFILL');
