do $smoke$
declare
  v_status text;v_num numeric;v_den numeric;v_val numeric;v_reason text;v_count integer;v_bool boolean;v_old_publish jsonb;
  v_founder uuid:='11111111-1111-4111-8111-111111119902'::uuid;
  v_content uuid:='22222222-2222-4222-8222-222222229902'::uuid;
  v_appt timestamptz:=timestamptz '2030-11-10 02:00:00+00';
begin
  select setting_value into v_old_publish from config.system_settings where setting_key='analytics_postgres_publish_enabled';
  delete from analytics.appointment_outcome_fact where placement_id='MYC-PL-999902';delete from analytics.partner_attribution_fact where candidate_id='MYC-C-999902';
  delete from finance.journal_lines where journal_batch_id='MYC-JRN-999902';delete from finance.journal_batches where journal_batch_id='MYC-JRN-999902';delete from finance.monthly_close_checks where close_month=date '2030-12-01';
  delete from core.placements where placement_id='MYC-PL-999902';delete from core.jobs where job_id='MYC-J-999902';delete from core.candidates where candidate_id='MYC-C-999902';delete from core.partners where partner_id='MYC-P-9999';delete from core.clients where client_id='MYC-B2B-9998';
  delete from ops.raw_inputs where raw_input_id in ('MYC-RAW-999902','MYC-RAW-999903');delete from authz.user_roles where auth_user_id in (v_founder,v_content);delete from auth.users where id in (v_founder,v_content);

  insert into ops.raw_inputs(raw_input_id,received_at,channel,sender_type,content_type,raw_summary,classification,entity_type,entity_id,processing_status,source_system,metadata) values
  ('MYC-RAW-999902',now(),'INTERNAL_TEST','SYSTEM','application/json','6B appointment/attribution smoke','ANALYTICS_TEST','Candidate','MYC-C-999902','COMPLETED','PART6B_SMOKE','{}'::jsonb),
  ('MYC-RAW-999903',now(),'PARTNER_TEST','PARTNER','application/json','Partner responded; no attribution decision yet','ANALYTICS_TEST','Candidate','MYC-C-999902','COMPLETED','PART6B_SMOKE','{}'::jsonb);
  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status) values('MYC-B2B-9998','TEST','Part6B Smoke Client','Saraburi','ACTIVE','VERIFIED');
  insert into core.partners(partner_id,partner_name,partner_type,province,status) values('MYC-P-9999','Part6B Smoke Partner','TEST','Saraburi','ACTIVE');
  insert into core.candidates(candidate_id,nickname,source_type,partner_id,status,relocation_ready) values('MYC-C-999902','Smoke 6B','PARTNER','MYC-P-9999','QUALIFIED',true);
  insert into core.jobs(job_id,client_id,position_name,province,headcount,status,last_confirmed_at) values('MYC-J-999902','MYC-B2B-9998','Smoke Job 6B','Saraburi',1,'ACTIVE',now());
  insert into core.placements(placement_id,candidate_id,job_id,status,appointment_at) values('MYC-PL-999902','MYC-C-999902','MYC-J-999902','APPOINTED',v_appt);

  perform analytics.record_appointment_outcome('MYC-PL-999902',v_appt,'NO_SHOW',v_appt+interval '1 hour',null,'MYC-RAW-999902',null,'MANUAL_VERIFIED',true,'PART6B_SMOKE','{}'::jsonb);
  perform analytics.record_appointment_outcome('MYC-PL-999902',v_appt,'NO_SHOW',v_appt+interval '1 hour',null,'MYC-RAW-999902',null,'MANUAL_VERIFIED',true,'PART6B_SMOKE','{}'::jsonb);
  select count(*) into v_count from analytics.appointment_outcome_fact where placement_id='MYC-PL-999902' and appointment_at=v_appt;if v_count<>1 then raise exception 'APPOINTMENT_IDEMPOTENCY_FAILED';end if;
  select s.status,s.numerator,s.denominator,s.metric_value into v_status,v_num,v_den,v_val from analytics.evaluate_kpi_v2('KPI-CAN-006',timestamptz '2030-11-11 00:00:00+00',true) s;
  if v_status<>'READY' or v_num<>1 or v_den<>1 or v_val<>100 then raise exception 'AN-003_FAILED: %,%,%,%',v_status,v_num,v_den,v_val;end if;
  perform analytics.record_appointment_outcome('MYC-PL-999902',v_appt+interval '1 day','UNKNOWN',v_appt+interval '1 day 1 hour',null,'MYC-RAW-999902',null,'EVENT',false,'PART6B_SMOKE','{}'::jsonb);
  select s.status,s.blocked_reason into v_status,v_reason from analytics.evaluate_kpi_v2('KPI-CAN-006',timestamptz '2030-11-12 12:00:00+00',true) s;
  if v_status<>'NOT_READY' or v_reason<>'APPOINTMENT_OUTCOME_AMBIGUOUS_OR_UNVERIFIED' then raise exception 'AN-004_FAILED: %,%',v_status,v_reason;end if;

  select a.data_ready into v_bool from analytics.partner_attribution_current_v a where a.candidate_id='MYC-C-999902';if coalesce(v_bool,false) then raise exception 'AN-007_FAILED_CURRENT_FIELD';end if;
  select s.status,s.metric_value into v_status,v_val from analytics.evaluate_kpi_v2('KPI-PAR-001',now(),true) s;if v_status='READY' and coalesce(v_val,0)>0 then raise exception 'AN-007_FAILED_CREDIT';end if;
  perform analytics.record_partner_attribution('MYC-C-999902','MYC-P-9999',now(),'APPROVED',null,'MYC-RAW-999903','MANUAL_VERIFIED','PART6B_REVIEWER',now(),'PART6B_SMOKE','{}'::jsonb);
  perform analytics.record_partner_attribution('MYC-C-999902','MYC-P-9999',now(),'APPROVED',null,'MYC-RAW-999903','MANUAL_VERIFIED','PART6B_REVIEWER',now(),'PART6B_SMOKE','{}'::jsonb);
  select count(*) into v_count from analytics.partner_attribution_fact where candidate_id='MYC-C-999902' and attribution_status='APPROVED';if v_count<>1 then raise exception 'ATTRIBUTION_IDEMPOTENCY_FAILED';end if;

  insert into finance.journal_batches(journal_batch_id,journal_date,source_type,source_ref,description,status,posted_at,posted_by,created_by) values('MYC-JRN-999902',date '2030-12-15','TEST','PART6B_SMOKE','Part6B journal semantic smoke','POSTED',now(),'PART6B_SMOKE','PART6B_SMOKE');
  insert into finance.journal_lines(journal_batch_id,line_no,account_code,line_description,debit,credit) values('MYC-JRN-999902',1,'1100','Smoke cash',100,0),('MYC-JRN-999902',2,'4000','Smoke revenue',0,100);
  insert into finance.monthly_close_checks(close_month,close_id,check_description,owner,status) values
  ('2030-12-01','CLOSE-001','Smoke close 1','Finance','PASS'),('2030-12-01','CLOSE-002','Smoke close 2','Finance','PASS'),('2030-12-01','CLOSE-003','Smoke close 3','Finance','PASS'),('2030-12-01','CLOSE-004','Smoke close 4','Finance','PASS'),('2030-12-01','CLOSE-005','Smoke close 5','Finance','PASS'),('2030-12-01','CLOSE-006','Smoke close 6','Finance','PASS');
  select count(*) into v_count from analytics.finance_monthly_v f where f.month_start='2030-12-01' and f.posted_debit=100 and f.posted_credit=100 and f.revenue_amount=100 and f.expense_amount=0 and f.net_result=100 and f.accounting_close_status='CLOSED' and f.journal_balance_status='BALANCED';if v_count<>1 then raise exception 'AN-012_FAILED';end if;

  insert into auth.users(id) values(v_founder),(v_content);
  update authz.user_profiles set display_name='Part6B Founder Smoke',status='ACTIVE' where auth_user_id=v_founder;
  update authz.user_profiles set display_name='Part6B Content Smoke',status='ACTIVE' where auth_user_id=v_content;
  insert into authz.user_roles(auth_user_id,role_key,assigned_by,reason) values(v_founder,'founder','PART6B_SMOKE','Acceptance'),(v_content,'content_studio','PART6B_SMOKE','Acceptance');
  update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key='analytics_postgres_publish_enabled';

  perform set_config('request.jwt.claim.sub',v_content::text,true);execute 'set local role authenticated';
  begin perform * from api.analytics_kpi_result('KPI-CAN-006');raise exception 'AN-008_FAILED';exception when others then if position('ACCESS_DENIED:analytics_read' in sqlerrm)=0 then raise;end if;end;execute 'reset role';
  perform set_config('request.jwt.claim.sub',v_founder::text,true);execute 'set local role authenticated';
  select count(*) into v_count from api.analytics_kpi_drillthrough('KPI-PAR-001',10) d where d.entity_id='MYC-C-999902' and d.related_entity_id='MYC-P-9999' and d.raw_input_id='MYC-RAW-999903';if v_count<>1 then raise exception 'AN-010_FAILED';end if;execute 'reset role';perform set_config('request.jwt.claim.sub','',true);

  update config.system_settings set setting_value=coalesce(v_old_publish,'false'::jsonb),updated_at=now() where setting_key='analytics_postgres_publish_enabled';
  delete from authz.user_roles where auth_user_id in (v_founder,v_content);delete from auth.users where id in (v_founder,v_content);
  delete from analytics.appointment_outcome_fact where placement_id='MYC-PL-999902';delete from analytics.partner_attribution_fact where candidate_id='MYC-C-999902';delete from finance.journal_lines where journal_batch_id='MYC-JRN-999902';delete from finance.journal_batches where journal_batch_id='MYC-JRN-999902';delete from finance.monthly_close_checks where close_month=date '2030-12-01';
  delete from core.placements where placement_id='MYC-PL-999902';delete from core.jobs where job_id='MYC-J-999902';delete from core.candidates where candidate_id='MYC-C-999902';delete from core.partners where partner_id='MYC-P-9999';delete from core.clients where client_id='MYC-B2B-9998';delete from ops.raw_inputs where raw_input_id in ('MYC-RAW-999902','MYC-RAW-999903');
  update analytics.acceptance_catalog set status='PASS',evidence_ref='part6_wave6b_core_analytics_acceptance_smoke',last_tested_at=now(),updated_at=now() where test_id in ('AN-003','AN-004','AN-007','AN-008','AN-010','AN-012');
end
$smoke$;