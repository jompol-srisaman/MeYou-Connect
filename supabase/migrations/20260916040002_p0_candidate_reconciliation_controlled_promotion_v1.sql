-- P0 Candidate reconciliation controlled-promotion extension.
-- Continues the existing Event Kernel + candidate_intake command path.
-- Does not apply a business Master write and does not change Google Data Hub authority.

do $$
declare
  v_population integer;
  v_promotions integer;
begin
  select count(*) into v_population
  from ops.candidate_reconciliation_workbench_v
  where reconciliation_category='NEEDS_DQ'
    and received_at < timestamptz '2026-09-16 03:18:55+00';
  if v_population <> 61 then
    raise exception 'accepted reconciliation population drift: expected 61 got %',v_population;
  end if;

  select count(*) into v_promotions
  from ops.candidate_reconciliation_workbench_v
  where reconciliation_category='NEEDS_DQ'
    and received_at < timestamptz '2026-09-16 03:18:55+00'
    and raw_input_id not in ('MYC-RAW-000885','MYC-RAW-000930','MYC-RAW-001223');
  if v_promotions <> 58 then
    raise exception 'accepted promotion population drift: expected 58 got %',v_promotions;
  end if;
end $$;

update ops.raw_inputs r
set metadata = coalesce(r.metadata,'{}'::jsonb) || jsonb_build_object(
  'candidate_reconciliation',jsonb_build_object(
    'decision','NEW_CANDIDATE_NEEDS_PROMOTION',
    'reason','CANDIDATE_OPS_LIVE_MASTER_RECONCILIATION_ACCEPTED',
    'evidence_ref','github:issue#16:comment:5691426260',
    'accepted_at','2026-09-16T03:05:18Z',
    'accepted_by','CANDIDATE_OPS_AI/DISPATCHER',
    'master_authority','GOOGLE_SHEETS_DRIVE',
    'master_effect_required',true
  )
), updated_at=now()
where r.raw_input_id in (
  select w.raw_input_id
  from ops.candidate_reconciliation_workbench_v w
  where w.reconciliation_category='NEEDS_DQ'
    and w.received_at < timestamptz '2026-09-16 03:18:55+00'
    and w.raw_input_id not in ('MYC-RAW-000885','MYC-RAW-000930','MYC-RAW-001223')
);

update ops.raw_inputs r
set metadata = coalesce(r.metadata,'{}'::jsonb) || jsonb_build_object(
  'candidate_reconciliation',jsonb_build_object(
    'decision','DUPLICATE',
    'reason','BUSINESS_DUPLICATE_SAME_PHONE_MATCHING_EXPLICIT_PROFILE_FACTS',
    'duplicate_of_raw_input_id','MYC-RAW-000932',
    'evidence_ref','github:issue#16:comment:5691426260',
    'accepted_at','2026-09-16T03:05:18Z',
    'accepted_by','CANDIDATE_OPS_AI/DISPATCHER',
    'master_authority','GOOGLE_SHEETS_DRIVE',
    'master_effect_required',false
  )
), updated_at=now()
where r.raw_input_id='MYC-RAW-000930';

update ops.raw_inputs r
set metadata = coalesce(r.metadata,'{}'::jsonb) || jsonb_build_object(
  'candidate_reconciliation',jsonb_build_object(
    'decision','NEEDS_DQ',
    'reason','NAME_MATCH_PHONE_CONFLICT_WITH_MYC-C-000009',
    'candidate_master_ref','MYC-C-000009',
    'evidence_ref','github:issue#16:comment:5691426260',
    'accepted_at','2026-09-16T03:05:18Z',
    'accepted_by','CANDIDATE_OPS_AI/DISPATCHER',
    'master_authority','GOOGLE_SHEETS_DRIVE',
    'master_effect_required',false
  )
), updated_at=now()
where r.raw_input_id='MYC-RAW-000885';

update ops.raw_inputs r
set metadata = coalesce(r.metadata,'{}'::jsonb) || jsonb_build_object(
  'candidate_reconciliation',jsonb_build_object(
    'decision','NEEDS_DQ',
    'reason','MISSING_EXPLICIT_CANDIDATE_NAME',
    'evidence_ref','github:issue#16:comment:5691426260',
    'accepted_at','2026-09-16T03:05:18Z',
    'accepted_by','CANDIDATE_OPS_AI/DISPATCHER',
    'master_authority','GOOGLE_SHEETS_DRIVE',
    'master_effect_required',false
  )
), updated_at=now()
where r.raw_input_id='MYC-RAW-001223';

create or replace view ops.candidate_reconciliation_workbench_v as
with base as (
  select
    v.raw_input_id,v.received_at,v.updated_at,v.gap_state,v.readiness,
    r.source_account_ref,r.thread_id,r.message_id,r.sender_ref,r.raw_summary,
    nullif(r.metadata#>>'{line_ingestion,candidate,full_name}','') candidate_name,
    nullif(r.metadata#>>'{line_ingestion,candidate,phone}','') candidate_phone,
    nullif(r.metadata#>>'{line_ingestion,candidate,date_of_birth}','') candidate_dob,
    nullif(r.metadata#>>'{line_ingestion,candidate,education}','') candidate_education,
    nullif(r.metadata#>>'{line_ingestion,candidate,partner_id}','') parsed_partner_id,
    nullif(r.metadata#>>'{line_ingestion,job_id}','') parsed_job_id,
    nullif(r.metadata#>>'{operational_master_effect,candidate_id}','') operational_candidate_id,
    nullif(r.metadata#>>'{candidate_reconciliation,decision}','') explicit_decision,
    nullif(r.metadata#>>'{candidate_reconciliation,reason}','') explicit_reason,
    nullif(r.metadata#>>'{candidate_reconciliation,evidence_ref}','') reconciliation_evidence_ref,
    lower(regexp_replace(regexp_replace(coalesce(nullif(r.metadata#>>'{line_ingestion,candidate,full_name}',''),''),'^(ชื่อ[- ]?นามสกุล|ชื่อนามสกุล|ชื่อ)\s*[:：]?\s*','','i'),'\s+','','g')) normalized_name,
    (coalesce(r.raw_summary,'') ~* 'วันเดือนปีเกิด|วันเกิด|เกิด\s*[:：]')::integer +
    (coalesce(r.raw_summary,'') ~* 'วุฒิ|วุติ|การศึกษา|ปวช|ปวส')::integer +
    (coalesce(r.raw_summary,'') ~* 'น้ำหนัก|น\.น|นน\.')::integer +
    (coalesce(r.raw_summary,'') ~* 'ส่วนสูง|สูง\s*[:：]?\s*[0-9]|ส\.ส')::integer +
    (coalesce(r.raw_summary,'') ~* 'อายุ\s*[:：]?\s*[0-9]')::integer +
    (coalesce(r.raw_summary,'') ~* 'เบอร์โทร|โทร\s*[:：]?\s*0[0-9]{9}')::integer +
    (coalesce(r.raw_summary,'') ~* 'โรงงาน|โรงาน')::integer +
    (coalesce(r.raw_summary,'') ~* 'รอยสัก|ลอยสัก')::integer structured_signal_count,
    case when btrim(coalesce(r.raw_summary,'')) ~* '^(ใช่(ค่ะ|ครับ)?|คนนี้|อันนี้(นะ)?|รูปนี้|เอาอันนี้|ลบ|แก้|แก้ไข|เปลี่ยน)' then true else false end context_like,
    case when coalesce(r.raw_summary,'') ~* 'ลูกทีม|เบอร์ติดต่อ|ติดต่อ.*(แพร|เจน|เจด้า|คิม)|ผู้แนะนำ\s*[:：]?\s*[ก-๙A-Za-z]+$' then true else false end contact_or_internal_like
  from ops.candidate_promotion_gap_v v
  join ops.raw_inputs r on r.raw_input_id=v.raw_input_id
  where v.readiness='NOT_READY'
), fingerprinted as (
  select b.*,concat_ws('|',coalesce(b.candidate_phone,''),b.normalized_name,coalesce(b.candidate_dob,'')) candidate_fingerprint
  from base b
), ranked as (
  select f.*,
    row_number() over(partition by f.candidate_fingerprint order by f.received_at,f.raw_input_id) fingerprint_row_no,
    count(*) over(partition by f.candidate_fingerprint) fingerprint_raw_count
  from fingerprinted f
  where f.candidate_fingerprint<>'||'
)
select
  raw_input_id canonical_id,raw_input_id,received_at,updated_at,source_account_ref,thread_id,message_id,sender_ref,raw_summary,
  candidate_name,candidate_phone,candidate_dob,candidate_education,parsed_partner_id,parsed_job_id,operational_candidate_id,
  candidate_fingerprint,fingerprint_raw_count,structured_signal_count,
  case
    when explicit_decision in ('ALREADY_IN_MASTER_LINK_MISSING','NEW_CANDIDATE_NEEDS_PROMOTION','DUPLICATE','CONTEXT_ONLY','INVALID/NOISE','NEEDS_DQ') then explicit_decision
    when contact_or_internal_like and structured_signal_count<=1 then 'INVALID/NOISE'
    when context_like and structured_signal_count<=1 then 'CONTEXT_ONLY'
    when structured_signal_count<=1 and char_length(btrim(coalesce(raw_summary,'')))<120 then 'CONTEXT_ONLY'
    when structured_signal_count>=2 and fingerprint_row_no>1 then 'DUPLICATE'
    else 'NEEDS_DQ'
  end reconciliation_category,
  case
    when explicit_decision is not null and explicit_reason is not null then explicit_reason
    when structured_signal_count>=2 and fingerprint_row_no=1 then 'LIVE_DATAHUB_MASTER_LOOKUP_REQUIRED'
    when structured_signal_count>=2 and fingerprint_row_no>1 then 'RAW_DUPLICATE_OF_EARLIER_FINGERPRINT'
    when contact_or_internal_like and structured_signal_count<=1 then 'NON_CANDIDATE_CONTACT_SHAPE'
    when context_like or structured_signal_count<=1 then 'CONTEXT_NOT_STANDALONE_CANDIDATE'
    else 'REVIEW_REQUIRED'
  end reconciliation_reason,
  'GOOGLE_SHEETS_DRIVE'::text master_authority,
  case
    when explicit_decision='NEW_CANDIDATE_NEEDS_PROMOTION' and reconciliation_evidence_ref is not null then 'VERIFIED_PROPOSAL'
    when explicit_decision in ('DUPLICATE','CONTEXT_ONLY','INVALID/NOISE') and reconciliation_evidence_ref is not null then 'RESOLVED'
    when explicit_decision='ALREADY_IN_MASTER_LINK_MISSING' and reconciliation_evidence_ref is not null then 'VERIFIED_LINKAGE_PROPOSAL'
    when explicit_decision='NEEDS_DQ' and reconciliation_evidence_ref is not null then 'DQ_REQUIRED'
    else 'NOT_READY'
  end master_lookup_readiness
from ranked;

create or replace function ops.build_candidate_reconciliation_payload_v1(p_raw_input_id text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_raw ops.raw_inputs;
  v_candidate jsonb;
  v_safe_candidate jsonb := '{}'::jsonb;
  v_name text;
  v_phone text;
  v_dob text;
  v_education text;
  v_partner_id text;
  v_job_id text;
  v_fingerprint text;
  v_evidence_ref text;
begin
  select * into v_raw from ops.raw_inputs where raw_input_id=p_raw_input_id;
  if not found then raise exception 'RAW_INPUT_NOT_FOUND:%',p_raw_input_id; end if;
  if v_raw.metadata#>>'{candidate_reconciliation,decision}' <> 'NEW_CANDIDATE_NEEDS_PROMOTION' then
    raise exception 'RAW_NOT_ACCEPTED_FOR_PROMOTION:%',p_raw_input_id;
  end if;
  v_evidence_ref:=nullif(v_raw.metadata#>>'{candidate_reconciliation,evidence_ref}','');
  if v_evidence_ref is null then raise exception 'RECONCILIATION_EVIDENCE_REQUIRED:%',p_raw_input_id; end if;

  v_candidate:=coalesce(v_raw.metadata#>'{line_ingestion,candidate}','{}'::jsonb);
  v_name:=nullif(v_candidate->>'full_name','');
  v_phone:=nullif(v_candidate->>'phone','');
  v_dob:=nullif(v_candidate->>'date_of_birth','');
  v_education:=nullif(v_candidate->>'education','');
  v_partner_id:=nullif(v_candidate->>'partner_id','');
  v_job_id:=nullif(v_raw.metadata#>>'{line_ingestion,job_id}','');
  if v_name is null or v_phone is null then raise exception 'NAME_PHONE_REQUIRED:%',p_raw_input_id; end if;

  v_safe_candidate:=jsonb_build_object('status','SCREENING');
  if v_education is not null then v_safe_candidate:=v_safe_candidate||jsonb_build_object('education',v_education); end if;
  if v_partner_id is not null then v_safe_candidate:=v_safe_candidate||jsonb_build_object('source_type','Sourcing Partner'); end if;
  if v_job_id is not null then v_safe_candidate:=v_safe_candidate||jsonb_build_object('preferred_job',case when v_job_id='MYC-J-000013' then 'Next Can' else null end); end if;
  v_fingerprint:=concat_ws('|',v_phone,lower(regexp_replace(regexp_replace(v_name,'^(ชื่อ[- ]?นามสกุล|ชื่อนามสกุล|ชื่อ)\s*[:：]?\s*','','i'),'\s+','','g')),coalesce(v_dob,''));

  return jsonb_build_object(
    'candidate',jsonb_strip_nulls(v_safe_candidate),
    'private_contact',jsonb_strip_nulls(jsonb_build_object('full_name',v_name,'phone',v_phone,'date_of_birth',v_dob)),
    'partner_id',v_partner_id,'job_id',v_job_id,
    'dedupe_rule','NAME_PHONE_DOB','dedupe_key',v_fingerprint,
    'source_raw_input_id',p_raw_input_id,
    'reconciliation_evidence_ref',v_evidence_ref,
    'operational_master_target','GOOGLE_SHEETS_DRIVE','auto_submit',false
  );
end;
$$;

create or replace function ops.enqueue_candidate_reconciliation_v1(p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_parent ops.events;
  v_child ops.events;
  v_enqueued integer:=0;
  v_existing integer:=0;
  v_errors integer:=0;
begin
  if p_limit<1 or p_limit>500 then raise exception 'limit must be between 1 and 500'; end if;
  for r in
    select w.raw_input_id,w.received_at
    from ops.candidate_reconciliation_workbench_v w
    where w.reconciliation_category='NEW_CANDIDATE_NEEDS_PROMOTION'
      and w.master_lookup_readiness='VERIFIED_PROPOSAL'
    order by w.received_at,w.raw_input_id
    limit p_limit
  loop
    begin
      if exists(select 1 from ops.event_effects where effect_key='candidate_reconciliation_enqueued|'||r.raw_input_id) then
        v_existing:=v_existing+1; continue;
      end if;
      select * into v_parent from ops.events
      where raw_input_id=r.raw_input_id and event_type='channel.raw.received' and source_system='LINE'
      order by created_at limit 1;
      if not found then raise exception 'PARENT_RAW_EVENT_NOT_FOUND:%',r.raw_input_id; end if;
      v_child:=ops.register_event(v_parent.schema_version,'LINE','DERIVED:CANDIDATE_RECONCILIATION:'||r.raw_input_id,encode(extensions.digest('candidate.reconciliation.accepted|'||r.raw_input_id,'sha256'),'hex'),v_parent.trace_id,'candidate.lead.received',coalesce(v_parent.occurred_at,r.received_at),r.raw_input_id,v_parent.correlation_id,v_parent.event_id);
      perform ops.register_effect(v_parent.event_pk,'candidate_reconciliation_enqueued','candidate_reconciliation_enqueued|'||r.raw_input_id,'CandidateLead',null,'ops.events:'||v_child.event_pk::text);
      update ops.raw_inputs set metadata=jsonb_set(jsonb_set(coalesce(metadata,'{}'::jsonb),'{candidate_reconciliation,enqueued_event_pk}',to_jsonb(v_child.event_pk::text),true),'{candidate_reconciliation,enqueued_at}',to_jsonb(now()::text),true),updated_at=now() where raw_input_id=r.raw_input_id;
      v_enqueued:=v_enqueued+1;
    exception when others then v_errors:=v_errors+1;
    end;
  end loop;
  return jsonb_build_object('enqueued',v_enqueued,'already_enqueued',v_existing,'errors',v_errors);
end;
$$;

create or replace function ops.run_line_candidate_ingestion_tick(p_now timestamptz default now(), p_limit integer default 100, p_actor text default 'db_scheduler')
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  r record;
  v_route jsonb;
  v_parse jsonb;
  v_payload jsonb;
  v_cmd jsonb;
  v_finish jsonb;
  v_candidate jsonb;
  v_routed int:=0;
  v_candidate_events int:=0;
  v_commands int:=0;
  v_reconciled_commands int:=0;
  v_errors int:=0;
begin
  if p_limit<1 or p_limit>200 then raise exception 'limit must be between 1 and 200'; end if;
  perform ops.record_worker_heartbeat('candidate_intake','db_scheduler','test','HEALTHY','line-ingestion-v1.2',jsonb_build_object('actor',p_actor),p_now);

  for r in select e.event_pk from ops.events e where e.event_type='channel.raw.received' and e.source_system='LINE' and not exists(select 1 from ops.event_effects ee where ee.effect_key='line_ingestion_classification|'||e.raw_input_id) order by e.received_at,e.created_at limit p_limit loop
    begin
      v_route:=ops.route_line_raw_event_v1(r.event_pk); v_routed:=v_routed+1;
      if v_route->>'classification'='CANDIDATE_LEAD' then v_candidate_events:=v_candidate_events+1; end if;
    exception when others then v_errors:=v_errors+1;
    end;
  end loop;

  for r in select * from ops.claim_events('candidate_intake','db_scheduler',p_limit,120,p_now) loop
    begin
      if r.event_id like 'DERIVED:CANDIDATE_RECONCILIATION:%' then
        v_payload:=ops.build_candidate_reconciliation_payload_v1(r.raw_input_id);
        v_cmd:=ops.prepare_domain_command(r.event_pk,'candidate_intake',r.lease_token,v_payload,'Candidate',null);
        v_finish:=ops.finish_event_success(r.worker_run_pk,r.lease_token,'candidate_reconciliation_proposal_prepared','candidate_reconciliation_proposal|'||r.raw_input_id,'CandidateLead',null,'ops.domain_commands:'||(v_cmd->>'command_pk'),jsonb_build_object('raw_input_id',r.raw_input_id,'command_pk',v_cmd->>'command_pk','validation_status',v_cmd->>'validation_status','master_apply_deferred_to','GOOGLE_SHEETS_DRIVE','reconciliation',true),p_now);
        update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('candidate_command_pk',v_cmd->>'command_pk','candidate_command_validation',v_cmd->>'validation_status','candidate_worker_completed_at',p_now,'candidate_reconciliation_command_ready',true),updated_at=now() where raw_input_id=r.raw_input_id;
        v_commands:=v_commands+1; v_reconciled_commands:=v_reconciled_commands+1; continue;
      end if;

      v_parse:=ops.parse_line_candidate_raw_v1(r.raw_input_id);
      if v_parse->>'classification'<>'CANDIDATE_LEAD' then
        perform ops.finish_event_failure(r.worker_run_pk,r.lease_token,'VALIDATION','Derived candidate event no longer parses as candidate',jsonb_build_object('raw_input_id',r.raw_input_id),p_now);
        v_errors:=v_errors+1; continue;
      end if;
      v_candidate:=coalesce(v_parse->'candidate','{}'::jsonb)||jsonb_build_object('status','SCREENING');
      if nullif(v_parse->>'partner_id','') is not null then v_candidate:=v_candidate||jsonb_build_object('source_type','Sourcing Partner'); end if;
      v_payload:=jsonb_build_object('candidate',v_candidate,'private_contact',jsonb_build_object('full_name',v_parse#>>'{candidate,full_name}','phone',v_parse#>>'{candidate,phone}','date_of_birth',v_parse#>>'{candidate,date_of_birth}'),'partner_id',v_parse->>'partner_id','job_id',v_parse->>'job_id','dedupe_rule','NAME_PHONE_DOB','dedupe_key',v_parse->>'dedupe_key','ai_confidence',v_parse->'confidence','missing_fields',v_parse->'missing_fields','parser_version','line_candidate_v1','source_raw_input_id',r.raw_input_id,'operational_master_target','GOOGLE_SHEETS_DRIVE','auto_submit',false);
      v_cmd:=ops.prepare_domain_command(r.event_pk,'candidate_intake',r.lease_token,v_payload,'Candidate',null);
      v_finish:=ops.finish_event_success(r.worker_run_pk,r.lease_token,'candidate_proposal_prepared','candidate_proposal|'||r.raw_input_id,'CandidateLead',null,'ops.domain_commands:'||(v_cmd->>'command_pk'),jsonb_build_object('raw_input_id',r.raw_input_id,'command_pk',v_cmd->>'command_pk','validation_status',v_cmd->>'validation_status','master_apply_deferred_to','GOOGLE_SHEETS_DRIVE'),p_now);
      update ops.raw_inputs set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('candidate_command_pk',v_cmd->>'command_pk','candidate_command_validation',v_cmd->>'validation_status','candidate_worker_completed_at',p_now),updated_at=now() where raw_input_id=r.raw_input_id;
      v_commands:=v_commands+1;
    exception when others then
      begin perform ops.finish_event_failure(r.worker_run_pk,r.lease_token,'VALIDATION',sqlerrm,jsonb_build_object('raw_input_id',r.raw_input_id),p_now); exception when others then null; end;
      v_errors:=v_errors+1;
    end;
  end loop;

  return jsonb_build_object('routed_raw_events',v_routed,'candidate_events_created',v_candidate_events,'candidate_commands_prepared',v_commands,'reconciled_commands_prepared',v_reconciled_commands,'errors',v_errors,'actor',p_actor,'ran_at',p_now);
end;
$$;

revoke all on function ops.build_candidate_reconciliation_payload_v1(text) from public,anon,authenticated;
revoke all on function ops.enqueue_candidate_reconciliation_v1(integer) from public,anon,authenticated;
grant execute on function ops.build_candidate_reconciliation_payload_v1(text) to service_role;
grant execute on function ops.enqueue_candidate_reconciliation_v1(integer) to service_role;

comment on function ops.enqueue_candidate_reconciliation_v1(integer) is 'Evidence-gated backlog re-entry into existing candidate.lead.received Event Kernel. Does not write Candidate Master.';
comment on function ops.build_candidate_reconciliation_payload_v1(text) is 'Builds an evidence-backed candidate.upsert_proposal payload without inventing Job/Partner/Consent facts.';
