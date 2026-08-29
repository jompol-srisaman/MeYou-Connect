begin;

insert into auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous) values
 ('40000000-0000-0000-0000-000000000001','authenticated','authenticated','tst4d-founder@example.invalid',now(),now(),false,false),
 ('40000000-0000-0000-0000-000000000002','authenticated','authenticated','tst4d-candidate@example.invalid',now(),now(),false,false),
 ('40000000-0000-0000-0000-000000000003','authenticated','authenticated','tst4d-sales@example.invalid',now(),now(),false,false),
 ('40000000-0000-0000-0000-000000000004','authenticated','authenticated','tst4d-finance@example.invalid',now(),now(),false,false),
 ('40000000-0000-0000-0000-000000000005','authenticated','authenticated','tst4d-content@example.invalid',now(),now(),false,false),
 ('40000000-0000-0000-0000-000000000006','authenticated','authenticated','tst4d-norole@example.invalid',now(),now(),false,false);

select authz.assign_role('40000000-0000-0000-0000-000000000001','founder','part4d-smoke','synthetic founder',null);
select authz.assign_role('40000000-0000-0000-0000-000000000002','candidate_ops','part4d-smoke','synthetic candidate ops',null);
select authz.assign_role('40000000-0000-0000-0000-000000000003','client_sales','part4d-smoke','synthetic sales',null);
select authz.assign_role('40000000-0000-0000-0000-000000000004','finance_control','part4d-smoke','synthetic finance',null);
select authz.assign_role('40000000-0000-0000-0000-000000000005','content_studio','part4d-smoke','synthetic content',null);

insert into core.clients(client_id,client_type,company_name,province,area,crm_status,payment_term,billing_cycle,verification_status)
values('WC-B2B-9999','DIRECT_EMPLOYER','Part4D Test Factory','สระบุรี','TEST','ACTIVE','30 DAYS','MONTHLY','VERIFIED');
insert into private.client_contacts(client_id,contact_name,contact_role,phone,line_id,email)
values('WC-B2B-9999','Test HR','HR','0800000001','testhr','hr@example.invalid');
insert into core.jobs(job_id,client_id,workplace_name,province,area,position_name,headcount,wage,shift,start_date,milestone_deal,payment_term,status,last_confirmed_at)
values('WC-J-999999','WC-B2B-9999','Part4D Test Factory','สระบุรี','TEST','Warehouse Staff',5,20000,'DAY',date '2026-09-01','TEST DEAL','30 DAYS','OPEN',now());
insert into core.candidates(candidate_id,nickname,origin_province,education,primary_experience,preferred_job,expected_income,shift_preference,relocation_ready,ready_date,has_vehicle,dorm_needed,dorm_budget,documents_ready,medical_ready,status,next_action)
values('TST-C-4D-000001','Test Candidate','นครราชสีมา','M6','Warehouse','Warehouse Staff',18000,'DAY',true,date '2026-09-01',true,true,2500,true,true,'READY','Match job');
insert into private.candidate_contacts(candidate_id,full_name,phone,line_id,email,current_address,national_id)
values('TST-C-4D-000001','Synthetic Candidate','0800000002','candidate-line','candidate@example.invalid','TEST ADDRESS','0000000000000');
insert into core.placements(placement_id,candidate_id,job_id,status,start_date)
values('WC-PL-999999','TST-C-4D-000001','WC-J-999999','SUBMITTED',date '2026-09-01');
insert into core.followups(followup_id,placement_id,followed_up_at,milestone,result,next_followup_at)
values('TST4D-FU-1','WC-PL-999999',now(),'D1','OK',now()+interval '2 days');
insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
values('TST4D-RAW-CONSENT','TEST','TEST','test://4d/consent','RAW_STORED');
insert into docs.files(file_id,raw_input_id,provider,storage_profile_key,provider_file_ref,source_url,original_filename,visibility,sensitivity,storage_status)
values('WC-FILE-999999','TST4D-RAW-CONSENT','GOOGLE_DRIVE','evidence-private','test-file-ref','test://4d/consent.jpg','consent.jpg','PRIVATE','PII','SOURCE_ONLY');
insert into docs.evidence(evidence_id,file_id,evidence_type,evidence_class,verification_status,source_authority,created_by)
values('WC-EV-999999','WC-FILE-999999','CONSENT_SCREENSHOT','CONSENT_EVIDENCE','UNVERIFIED','CANDIDATE','part4d-smoke');
insert into privacy.consents(consent_id,candidate_id,purpose_code,decision,effective_at,evidence_id,source_raw_input_id,created_by)
values('WC-CN-999999','TST-C-4D-000001','JOB_MATCHING','GRANTED',now(),'WC-EV-999999','TST4D-RAW-CONSENT','part4d-smoke');

select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000002',true);
set local role authenticated;
do $$
declare v jsonb; v_count int; v_phone text; v_pref text; begin
  v:=api.current_access_context();
  if not (v->'roles' ? 'candidate_ops') then raise exception 'candidate_ops role missing from access context: %',v; end if;
  select count(*) into v_count from api.list_job_catalog(null); if v_count<>1 then raise exception 'candidate_ops job catalog failed'; end if;
  select preferred_job into v_pref from api.get_candidate_summary('TST-C-4D-000001'); if v_pref<>'Warehouse Staff' then raise exception 'candidate_ops candidate summary failed'; end if;
  select phone into v_phone from api.get_candidate_contact('TST-C-4D-000001'); if v_phone<>'0800000002' then raise exception 'candidate_ops contact access failed'; end if;
  select count(*) into v_count from api.get_consent_status('TST-C-4D-000001'); if v_count<>1 then raise exception 'candidate_ops consent access failed'; end if;
  begin perform 1 from core.candidates limit 1; raise exception 'direct core select unexpectedly allowed'; exception when insufficient_privilege then null; end;
  begin perform authz.assign_role('40000000-0000-0000-0000-000000000002','founder','bad-client-call',null,null); raise exception 'authenticated role assignment unexpectedly allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000003',true);
do $$
declare v_phone text; v_pref text; begin
  select phone into v_phone from api.get_client_record('WC-B2B-9999'); if v_phone<>'0800000001' then raise exception 'client_sales client contact missing'; end if;
  select preferred_job into v_pref from api.get_candidate_summary('TST-C-4D-000001'); if v_pref<>'Warehouse Staff' then raise exception 'client_sales limited candidate summary missing'; end if;
  begin perform * from api.get_candidate_contact('TST-C-4D-000001'); raise exception 'client_sales candidate PII unexpectedly allowed'; exception when others then if position('ACCESS_DENIED' in sqlerrm)=0 then raise; end if; end;
end $$;

select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000004',true);
do $$
declare v_term text; v_phone text; v_pref text; v_status text; begin
  select payment_term,phone into v_term,v_phone from api.get_client_record('WC-B2B-9999');
  if v_term<>'30 DAYS' or v_phone is not null then raise exception 'finance client projection failed'; end if;
  select preferred_job,status into v_pref,v_status from api.get_candidate_summary('TST-C-4D-000001');
  if v_pref is not null or v_status<>'READY' then raise exception 'finance candidate masking failed'; end if;
  begin perform * from api.get_candidate_contact('TST-C-4D-000001'); raise exception 'finance candidate PII unexpectedly allowed'; exception when others then if position('ACCESS_DENIED' in sqlerrm)=0 then raise; end if; end;
end $$;

select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000005',true);
do $$
declare v_count int; begin
  select count(*) into v_count from api.job_catalog_v; if v_count<>1 then raise exception 'content job catalog failed'; end if;
  begin perform * from api.get_candidate_summary('TST-C-4D-000001'); raise exception 'content candidate summary unexpectedly allowed'; exception when others then if position('ACCESS_DENIED' in sqlerrm)=0 then raise; end if; end;
end $$;

select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000001',true);
do $$
declare v jsonb; begin
  v:=api.current_access_context();
  if not (v->'capabilities' ? 'protected_action_approve') then raise exception 'founder protected approval capability missing: %',v; end if;
end $$;

select set_config('request.jwt.claim.sub','40000000-0000-0000-0000-000000000006',true);
do $$
declare v jsonb; begin
  v:=api.current_access_context();
  if jsonb_array_length(v->'roles')<>0 then raise exception 'no-role user unexpectedly has roles'; end if;
  begin perform * from api.list_job_catalog(null); raise exception 'no-role job access unexpectedly allowed'; exception when others then if position('ACCESS_DENIED' in sqlerrm)=0 then raise; end if; end;
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform api.current_access_context(); raise exception 'anon API execution unexpectedly allowed'; exception when insufficient_privilege then null; end;
end $$;

reset role;
rollback;