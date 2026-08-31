do $smoke$
declare
  v_status text;
  v_num numeric;
  v_den numeric;
  v_val numeric;
  v_reason text;
  v_count integer;
begin
  delete from analytics.stage_transition_fact where entity_id='MYC-C-999901';
  delete from analytics.placement_milestone_fact where placement_id='MYC-PL-999901';
  update finance.revenue set collection_bank_txn_id=null,collection_evidence_id=null where revenue_id='MYC-REV-999901';
  delete from finance.bank_transactions where bank_txn_id='MYC-BANK-999901';
  delete from finance.revenue where revenue_id='MYC-REV-999901';
  delete from docs.evidence where evidence_id='MYC-EV-999901';
  delete from docs.files where file_id='MYC-FILE-999901';
  delete from core.placements where placement_id='MYC-PL-999901';
  delete from core.jobs where job_id='MYC-J-999901';
  delete from core.candidates where candidate_id='MYC-C-999901';
  delete from core.clients where client_id='MYC-B2B-9999';
  delete from ops.raw_inputs where raw_input_id='MYC-RAW-999901';
  delete from analytics.source_freshness where source_key='SMOKE_STALE_SOURCE';

  insert into ops.raw_inputs(raw_input_id,received_at,channel,sender_type,content_type,raw_summary,classification,entity_type,entity_id,processing_status,source_system,metadata)
  values('MYC-RAW-999901',now()-interval '40 days','INTERNAL_TEST','SYSTEM','application/json','Part 6A semantic smoke','ANALYTICS_TEST','Candidate','MYC-C-999901','COMPLETED','PART6A_SMOKE','{}'::jsonb);

  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status)
  values('MYC-B2B-9999','TEST','Part6A Smoke Client','Saraburi','ACTIVE','VERIFIED');

  insert into core.candidates(candidate_id,nickname,source_type,status,relocation_ready)
  values('MYC-C-999901','Smoke Candidate','TEST','STARTED',true);

  insert into core.jobs(job_id,client_id,position_name,province,headcount,status,last_confirmed_at)
  values('MYC-J-999901','MYC-B2B-9999','Smoke Job','Saraburi',1,'ACTIVE',now()-interval '10 days');

  insert into core.placements(placement_id,candidate_id,job_id,status,start_date,submitted_at)
  values('MYC-PL-999901','MYC-C-999901','MYC-J-999901','STARTED',((now() at time zone 'Asia/Bangkok')::date-5),now()-interval '7 days');

  insert into analytics.stage_transition_fact(entity_type,entity_id,from_stage,to_stage,occurred_at,raw_input_id,actor_service,valid_transition,source_kind)
  values
  ('Candidate','MYC-C-999901',null,'LEAD',now()-interval '40 days','MYC-RAW-999901','PART6A_SMOKE',true,'MANUAL_VERIFIED'),
  ('Candidate','MYC-C-999901','LEAD','QUALIFIED',now()-interval '35 days','MYC-RAW-999901','PART6A_SMOKE',true,'MANUAL_VERIFIED');

  select status,numerator,denominator,metric_value,blocked_reason
  into v_status,v_num,v_den,v_val,v_reason
  from analytics.evaluate_kpi('KPI-RET-002',now(),true);
  if v_status<>'NOT_READY' or v_val is not null or v_reason<>'NO_ELIGIBLE_MATURE_COHORT' then
    raise exception 'AN-001_FAILED: expected D30 NOT_READY/no eligible cohort, got %, %, %',v_status,v_val,v_reason;
  end if;

  select status,numerator,denominator,metric_value
  into v_status,v_num,v_den,v_val
  from analytics.evaluate_kpi('KPI-CAN-003',now(),true);
  if v_status<>'READY' or v_num<>1 or v_den<>1 or v_val<>100 then
    raise exception 'AN-002_FAILED: historical funnel did not preserve LEAD->QUALIFIED after current STARTED';
  end if;
  select count(*) into v_count from analytics.candidate_current_v where candidate_id='MYC-C-999901' and current_status='STARTED';
  if v_count<>1 then raise exception 'AN-002_FAILED: current snapshot missing STARTED candidate'; end if;
  select count(*) into v_count from analytics.candidate_stage_events_v where candidate_id='MYC-C-999901' and upper(to_stage)='LEAD';
  if v_count<>1 then raise exception 'AN-002_FAILED: historical LEAD transition missing'; end if;

  insert into finance.revenue(revenue_id,transaction_date,client_id,placement_id,revenue_type,gross,status,notes,created_by)
  values('MYC-REV-999901',(now() at time zone 'Asia/Bangkok')::date,'MYC-B2B-9999','MYC-PL-999901','TEST',100,'EARNED','Chat says paid; no payment evidence or bank match.','PART6A_SMOKE');

  select status,metric_value into v_status,v_val from analytics.evaluate_kpi('KPI-FIN-004',now(),true);
  if v_val<>0 then raise exception 'AN-005_FAILED: chat-only payment changed official Collected KPI'; end if;

  insert into docs.files(file_id,provider,provider_file_ref,original_filename,visibility,sensitivity,storage_status,created_by)
  values('MYC-FILE-999901','GOOGLE_DRIVE','PART6A-SMOKE-EVIDENCE','smoke-payment-evidence.txt','PRIVATE','FINANCE','SOURCE_ONLY','PART6A_SMOKE');

  insert into docs.evidence(evidence_id,file_id,evidence_type,evidence_class,evidence_date,verification_status,verified_by,verified_at,source_authority,created_by)
  values('MYC-EV-999901','MYC-FILE-999901','PAYMENT_EVIDENCE','TRANSACTION_EVIDENCE',now(),'VERIFIED','PART6A_SMOKE',now(),'TEST_BANK_EVIDENCE','PART6A_SMOKE');

  insert into finance.bank_transactions(bank_txn_id,txn_at,account_wallet,bank_ref,direction,amount,counterparty,description,evidence_id,file_id,client_id,placement_id,revenue_id,reconciled,reconciled_at,reconciled_by)
  values('MYC-BANK-999901',now(),'TEST_WALLET','PART6A-SMOKE-BANK','IN',100,'Smoke Client','Matched payment smoke','MYC-EV-999901','MYC-FILE-999901','MYC-B2B-9999','MYC-PL-999901','MYC-REV-999901',true,now(),'PART6A_SMOKE');

  update finance.revenue
  set status='COLLECTED',collection_date=(now() at time zone 'Asia/Bangkok')::date,net_received=100,payment_ref='PART6A-SMOKE-BANK',collection_evidence_id='MYC-EV-999901',collection_bank_txn_id='MYC-BANK-999901',updated_at=now()
  where revenue_id='MYC-REV-999901';

  select status,metric_value into v_status,v_val from analytics.evaluate_kpi('KPI-FIN-004',now(),true);
  if v_status<>'READY' or v_val<>100 then
    raise exception 'AN-006_FAILED: verified/reconciled collection expected 100 READY, got %, %',v_status,v_val;
  end if;

  insert into analytics.source_freshness(source_key,source_type,last_source_at,last_refresh_at,freshness_window_minutes,readiness_status,source_ref)
  values('SMOKE_STALE_SOURCE','TEST',now()-interval '2 hours',now()-interval '2 hours',10,'READY','PART6A_SMOKE');
  select count(*) into v_count from analytics.source_readiness_v where source_key='SMOKE_STALE_SOURCE' and readiness_status='STALE' and blocked_reason='SOURCE_REFRESH_STALE';
  if v_count<>1 then raise exception 'AN-009_FAILED: stale source did not show STALE badge'; end if;

  select status,blocked_reason into v_status,v_reason from analytics.evaluate_kpi('KPI-CLI-001',now(),false);
  if v_status<>'NOT_READY' or v_reason<>'POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE' then
    raise exception 'SOURCE_GATE_FAILED: official KPI API path must remain NOT_READY in shadow mode';
  end if;

  update finance.revenue set collection_bank_txn_id=null,collection_evidence_id=null where revenue_id='MYC-REV-999901';
  delete from finance.bank_transactions where bank_txn_id='MYC-BANK-999901';
  delete from finance.revenue where revenue_id='MYC-REV-999901';
  delete from docs.evidence where evidence_id='MYC-EV-999901';
  delete from docs.files where file_id='MYC-FILE-999901';
  delete from analytics.stage_transition_fact where entity_id='MYC-C-999901';
  delete from analytics.placement_milestone_fact where placement_id='MYC-PL-999901';
  delete from core.placements where placement_id='MYC-PL-999901';
  delete from core.jobs where job_id='MYC-J-999901';
  delete from core.candidates where candidate_id='MYC-C-999901';
  delete from core.clients where client_id='MYC-B2B-9999';
  delete from ops.raw_inputs where raw_input_id='MYC-RAW-999901';
  delete from analytics.source_freshness where source_key='SMOKE_STALE_SOURCE';

  update analytics.acceptance_catalog
  set status='PASS',evidence_ref='part6_wave6a_semantic_acceptance_smoke',last_tested_at=now(),updated_at=now()
  where test_id in ('AN-001','AN-002','AN-005','AN-006','AN-009');
end
$smoke$;