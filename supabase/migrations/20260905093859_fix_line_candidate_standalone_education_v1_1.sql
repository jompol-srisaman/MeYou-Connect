-- MYC-DQ-000011 parser point-fix: recognize standalone education lines such as ม.3.
-- Preserves the existing parser/router architecture and refreshes the same backfill proposals idempotently.

alter function ops.parse_line_candidate_raw_v1(text) rename to parse_line_candidate_raw_base_v1;

create or replace function ops.parse_line_candidate_raw_v1(p_raw_input_id text)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v jsonb;
  v_raw ops.raw_inputs;
  v_line text;
  v_education text;
  v_missing jsonb;
  v_new_missing jsonb := '[]'::jsonb;
  x jsonb;
  v_origin text;
begin
  v:=ops.parse_line_candidate_raw_base_v1(p_raw_input_id);
  if v->>'classification'<>'CANDIDATE_LEAD' or nullif(v#>>'{candidate,education}','') is not null then
    return jsonb_set(v,'{parser_version}',to_jsonb('line_candidate_v1.1'::text),true);
  end if;
  select * into v_raw from ops.raw_inputs where raw_input_id=p_raw_input_id;
  foreach v_line in array regexp_split_to_array(replace(coalesce(v_raw.raw_summary,''),E'\r',''),E'\n') loop
    v_line:=btrim(v_line);
    if v_line ~* '^(ม\.?\s*[0-9]+|ป\.?\s*[0-9]+|ปวช\.?|ปวส\.?)' then
      v_education:=v_line;
      exit;
    end if;
  end loop;
  if v_education is not null then
    v:=jsonb_set(v,'{candidate,education}',to_jsonb(v_education),true);
    v_missing:=coalesce(v->'missing_fields','[]'::jsonb);
    for x in select value from jsonb_array_elements(v_missing) loop
      if x#>>'{}'<>'education' then v_new_missing:=v_new_missing||jsonb_build_array(x); end if;
    end loop;
    v:=jsonb_set(v,'{missing_fields}',v_new_missing,true);
    v_origin:=nullif(v#>>'{candidate,origin_area}','');
    v:=jsonb_set(v,'{confidence}',to_jsonb(case when v_origin is null then 96 else 98 end),true);
  end if;
  v:=jsonb_set(v,'{parser_version}',to_jsonb('line_candidate_v1.1'::text),true);
  return v;
end;
$$;

do $$
declare
  r record;
  v_parse jsonb;
  v_payload jsonb;
begin
  for r in
    select dc.command_pk,dc.source_raw_input_id
    from ops.domain_commands dc
    where dc.worker_key='candidate_intake'
      and dc.source_raw_input_id in ('MYC-RAW-000018','MYC-RAW-000019','MYC-RAW-000020')
      and dc.apply_status in ('READY','PROPOSED','BLOCKED')
  loop
    v_parse:=ops.parse_line_candidate_raw_v1(r.source_raw_input_id);
    update ops.raw_inputs set
      ai_confidence=nullif(v_parse->>'confidence','')::numeric,
      metadata=jsonb_set(jsonb_set(coalesce(metadata,'{}'::jsonb),'{line_ingestion}',v_parse,true),'{candidate_command_validation}',to_jsonb('PENDING_REFRESH'::text),true),
      updated_at=now()
    where raw_input_id=r.source_raw_input_id;

    v_payload:=jsonb_build_object(
      'candidate',coalesce(v_parse->'candidate','{}'::jsonb)||jsonb_build_object('source_type','Sourcing Partner','preferred_job','Next Can','status','SCREENING'),
      'private_contact',jsonb_build_object('full_name',v_parse#>>'{candidate,full_name}','phone',v_parse#>>'{candidate,phone}','date_of_birth',v_parse#>>'{candidate,date_of_birth}'),
      'partner_id',v_parse->>'partner_id','job_id',v_parse->>'job_id','dedupe_rule','NAME_PHONE_DOB','dedupe_key',v_parse->>'dedupe_key',
      'ai_confidence',v_parse->'confidence','missing_fields',v_parse->'missing_fields','parser_version','line_candidate_v1.1','source_raw_input_id',r.source_raw_input_id,
      'operational_master_target','GOOGLE_SHEETS_DRIVE'
    );
    update ops.domain_commands set payload=v_payload,validation_status='PENDING',validation_errors='[]'::jsonb,apply_status='PROPOSED',updated_at=now() where command_pk=r.command_pk;
    perform ops.validate_domain_command(r.command_pk);
    update ops.raw_inputs set metadata=metadata||jsonb_build_object('candidate_command_validation','VALID','candidate_proposal_refreshed_at',now()),updated_at=now() where raw_input_id=r.source_raw_input_id;
  end loop;
end;
$$;
