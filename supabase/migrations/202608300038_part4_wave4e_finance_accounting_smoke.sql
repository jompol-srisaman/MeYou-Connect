begin;

do $$
declare
  v_batch text;
  v_res jsonb;
  v_ar_alloc jsonb;
  v_ap_alloc jsonb;
  v_tax_alloc jsonb;
  v_ar_id text;
  v_ap_id text;
  v_tax_id text;
  v_count int;
  v_amt numeric;
  v_next_jrn bigint;
  v_next_ar bigint;
  v_next_ap bigint;
  v_next_tax bigint;
  v_fin_user uuid:='00000000-0000-4000-8000-000000004e01';
  v_content_user uuid:='00000000-0000-4000-8000-000000004e02';
  v_blocked boolean:=false;
begin
  if not exists(select 1 from config.id_allocators where entity_key='Candidate' and prefix='WC-C-' and allocation_enabled and conflict_status='NONE') then
    raise exception 'Candidate allocator source conflict was not resolved';
  end if;

  select next_number into v_next_jrn from config.id_allocators where entity_key='Journal Batch';
  select next_number into v_next_ar from config.id_allocators where entity_key='AR';
  select next_number into v_next_ap from config.id_allocators where entity_key='AP';
  select next_number into v_next_tax from config.id_allocators where entity_key='Tax Doc';

  if config.setting_is_true('finance_write_enabled') or config.setting_is_true('finance_posting_enabled') or config.setting_is_true('finance_collection_state_enabled') or config.setting_is_true('finance_commission_state_enabled') or config.setting_is_true('finance_external_payment_execution_enabled') then
    raise exception 'one or more finance safety gates unexpectedly enabled';
  end if;

  begin
    perform finance.create_journal_batch(current_date,'TEST','GATE-CHECK',null,null,null,'must block','part4e-smoke');
  exception when others then
    v_blocked:=true;
  end;
  if not v_blocked then raise exception 'finance write gate did not block'; end if;

  insert into ops.raw_inputs(raw_input_id,source_system,channel,original_ref,processing_status)
  values('TST4E-RAW-INV','TEST','TEST','test://4e/invoice','RAW_STORED'),
        ('TST4E-RAW-COLL','TEST','TEST','test://4e/collection','RAW_STORED');
  insert into docs.files(file_id,raw_input_id,provider,source_url,original_filename,visibility,sensitivity,storage_status,created_by)
  values('WC-FILE-999998','TST4E-RAW-INV','OTHER','test://4e/invoice.pdf','invoice.pdf','PRIVATE','FINANCE','SOURCE_NOT_MIRRORED','part4e-smoke'),
        ('WC-FILE-999997','TST4E-RAW-COLL','OTHER','test://4e/slip.jpg','slip.jpg','PRIVATE','FINANCE','SOURCE_NOT_MIRRORED','part4e-smoke');
  insert into docs.evidence(evidence_id,file_id,evidence_type,evidence_class,verification_status,verified_by,verified_at,source_authority,created_by)
  values('WC-EV-999998','WC-FILE-999998','INVOICE','TRANSACTION_EVIDENCE','VERIFIED','part4e-smoke',now(),'TEST','part4e-smoke'),
        ('WC-EV-999997','WC-FILE-999997','BANK_SLIP','TRANSACTION_EVIDENCE','VERIFIED','part4e-smoke',now(),'TEST','part4e-smoke');

  insert into core.clients(client_id,company_name,province,crm_status) values('WC-B2B-9999','Part4E Test Client','สระบุรี','ACTIVE');
  insert into core.partners(partner_id,partner_name,status) values('WC-P-9999','Part4E Test Partner','ACTIVE');
  insert into core.candidates(candidate_id,nickname,status,partner_id) values('WC-C-999999','Part4E Candidate','ACTIVE','WC-P-9999');
  insert into core.jobs(job_id,client_id,position_name,status) values('WC-J-999999','WC-B2B-9999','Warehouse Staff','ACTIVE');
  insert into core.placements(placement_id,candidate_id,job_id,status,start_date) values('WC-PL-999999','WC-C-999999','WC-J-999999','STARTED',current_date);

  insert into finance.revenue(revenue_id,transaction_date,client_id,placement_id,revenue_type,milestone,gross,wht,status,invoice_no,invoice_date,due_date,net_received,source_raw_input_id,created_by)
  values('TST-REV-4E-001',current_date,'WC-B2B-9999','WC-PL-999999','Placement','D7',1000,30,'EXPECTED','INV-TST-001',current_date,current_date+30,970,'TST4E-RAW-INV','part4e-smoke');
  insert into finance.expenses(expense_id,expense_date,placement_id,expense_category,description,gross_before_tax,net_paid,evidence_id,created_by)
  values('TST-EXP-4E-001',current_date,'WC-PL-999999','Transport','Test expense',100,100,'WC-EV-999998','part4e-smoke');
  insert into finance.commissions(commission_id,partner_id,placement_id,revenue_id,milestone,commission_amount,state,notes,created_by)
  values('TST-COM-4E-001','WC-P-9999','WC-PL-999999','TST-REV-4E-001','D7',250,'WAITING_COLLECTION','Test only','part4e-smoke');

  update config.system_settings set setting_value='true'::jsonb where setting_key in ('finance_write_enabled','finance_posting_enabled','finance_collection_state_enabled','finance_commission_state_enabled');

  v_batch:=finance.create_journal_batch(current_date,'REVENUE','TST-REV-4E-001','TST4E-RAW-INV','WC-EV-999998','WC-FILE-999998','Part4E balanced journal','part4e-smoke');
  perform finance.add_journal_line(v_batch,1,'1200',1000,0,'AR',null,null);
  begin
    perform finance.post_journal_batch(v_batch,'part4e-smoke');
    raise exception 'unbalanced journal unexpectedly posted';
  exception when others then
    if sqlerrm='unbalanced journal unexpectedly posted' then raise; end if;
  end;
  perform finance.add_journal_line(v_batch,2,'4000',0,1000,'Placement revenue',null,null);
  v_res:=finance.post_journal_batch(v_batch,'part4e-smoke');
  if v_res->>'status'<>'POSTED' then raise exception 'balanced journal did not post'; end if;
  v_res:=finance.post_journal_batch(v_batch,'part4e-smoke');
  if coalesce((v_res->>'duplicate_post')::boolean,false) is not true then raise exception 'duplicate journal post not idempotent'; end if;
  select amount into v_amt from finance.pnl_internal_v where account_code='4000';
  if v_amt<>1000 then raise exception 'PnL posted revenue mismatch'; end if;

  v_res:=finance.transition_revenue_state('TST-REV-4E-001','EARNED',null,null,'test earned','part4e-smoke');
  v_res:=finance.transition_revenue_state('TST-REV-4E-001','INVOICED','WC-EV-999998',null,'invoice issued','part4e-smoke');
  if (select status from finance.revenue where revenue_id='TST-REV-4E-001')<>'INVOICED' then raise exception 'revenue did not reach INVOICED'; end if;

  v_ar_alloc:=config.allocate_business_id('AR','part4e-smoke',jsonb_build_object('source','Part4E smoke'));
  v_ar_id:=v_ar_alloc->>'allocated_id';
  insert into finance.accounts_receivable(ar_id,client_id,placement_id,revenue_id,invoice_no,invoice_date,due_date,gross_amount,deduction,collected,evidence_id,file_id,journal_batch_id)
  values(v_ar_id,'WC-B2B-9999','WC-PL-999999','TST-REV-4E-001','INV-TST-001',current_date,current_date+30,1000,30,0,'WC-EV-999998','WC-FILE-999998',v_batch);

  insert into finance.bank_transactions(bank_txn_id,txn_at,account_wallet,bank_ref,direction,amount,counterparty,description,raw_input_id,evidence_id,file_id,client_id,placement_id,revenue_id,reconciled,reconciled_at,reconciled_by)
  values('WC-BANK-999999',now(),'TEST BANK','BANK-TST-IN-001','IN',970,'Part4E Test Client','Collected test only','TST4E-RAW-COLL','WC-EV-999997','WC-FILE-999997','WC-B2B-9999','WC-PL-999999','TST-REV-4E-001',true,now(),'part4e-smoke');
  v_res:=finance.transition_revenue_state('TST-REV-4E-001','COLLECTED','WC-EV-999997','WC-BANK-999999','matched collection','part4e-smoke');
  if (select status from finance.revenue where revenue_id='TST-REV-4E-001')<>'COLLECTED' then raise exception 'revenue did not reach COLLECTED'; end if;
  if (select derived_status from finance.accounts_receivable_v where ar_id=v_ar_id)<>'PAID' then raise exception 'AR did not reconcile to PAID'; end if;

  if not finance.commission_transition_allowed('TST-COM-4E-001','PAYABLE') then raise exception 'commission PAYABLE eligibility should be true after collection'; end if;
  if finance.commission_transition_allowed('TST-COM-4E-001','PAID') then raise exception 'PAID transition must remain unavailable in Part4E'; end if;
  if not exists(select 1 from finance.commission_payable_candidates_v where commission_id='TST-COM-4E-001' and payable_eligible) then raise exception 'commission payable candidate view failed'; end if;

  v_ap_alloc:=config.allocate_business_id('AP','part4e-smoke',jsonb_build_object('source','Part4E smoke'));
  v_ap_id:=v_ap_alloc->>'allocated_id';
  insert into finance.accounts_payable(ap_id,payee_ref,partner_id,placement_id,commission_id,due_date,gross_amount,deduction,paid,evidence_id)
  values(v_ap_id,'WC-P-9999','WC-P-9999','WC-PL-999999','TST-COM-4E-001',current_date+7,250,0,0,'WC-EV-999997');
  if (select outstanding from finance.accounts_payable_v where ap_id=v_ap_id)<>250 then raise exception 'AP derived outstanding mismatch'; end if;

  v_tax_alloc:=config.allocate_business_id('Tax Doc','part4e-smoke',jsonb_build_object('source','Part4E smoke'));
  v_tax_id:=v_tax_alloc->>'allocated_id';
  insert into finance.tax_documents(tax_doc_id,document_type,document_date,counterparty,counterparty_entity_id,invoice_ref_no,gross_amount,wht_amount,evidence_id,file_id,journal_batch_id,period,status)
  values(v_tax_id,'WHT_TEST',current_date,'Part4E Test Client','WC-B2B-9999','INV-TST-001',1000,30,'WC-EV-999998','WC-FILE-999998',v_batch,to_char(current_date,'YYYY-MM'),'REVIEW_REQUIRED');
  if config.setting_is_true('finance_tax_filing_enabled') then raise exception 'tax filing gate must remain disabled'; end if;
  if config.setting_is_true('finance_external_payment_execution_enabled') then raise exception 'external payment execution gate must remain disabled'; end if;

  insert into finance.monthly_close_checks(close_month,close_id,check_description,owner,status)
  values
   (date_trunc('month',current_date)::date,'CLOSE-001','ตรวจ Bank/Cash กับ Slip และ Journal ครบ','Founder/AI','OPEN'),
   (date_trunc('month',current_date)::date,'CLOSE-002','ตรวจ AR: Invoice / Due / Collection','Founder/AI','OPEN'),
   (date_trunc('month',current_date)::date,'CLOSE-003','ตรวจ AP / Commission Payable และ Payment Evidence','Founder/AI','OPEN'),
   (date_trunc('month',current_date)::date,'CLOSE-004','Journal ทุก Batch สมดุล Debit = Credit','Founder/AI','OPEN'),
   (date_trunc('month',current_date)::date,'CLOSE-005','ตรวจ Revenue/Expense ใน Data Hub กับ Ledger','Founder/AI','OPEN'),
   (date_trunc('month',current_date)::date,'CLOSE-006','รวบรวม Tax/WHT Documents ส่งผู้ทำบัญชี','Founder','OPEN');
  select count(*) into v_count from finance.monthly_close_checks where close_month=date_trunc('month',current_date)::date;
  if v_count<>6 then raise exception 'monthly close checklist mismatch'; end if;

  insert into auth.users(id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values(v_fin_user,'authenticated','authenticated','part4e-finance@test.invalid','',now(),'{}','{}',now(),now()),
        (v_content_user,'authenticated','authenticated','part4e-content@test.invalid','',now(),'{}','{}',now(),now());
  perform authz.assign_role(v_fin_user,'finance_control','part4e-smoke','acceptance',null);
  perform authz.assign_role(v_content_user,'content_studio','part4e-smoke','acceptance',null);

  perform set_config('request.jwt.claim.sub',v_fin_user::text,true);
  select count(*) into v_count from api.finance_revenue_overview(null);
  if v_count<>1 then raise exception 'finance_control revenue API failed'; end if;
  select count(*) into v_count from api.finance_trial_balance();
  if v_count<1 then raise exception 'finance_control trial balance API failed'; end if;

  perform set_config('request.jwt.claim.sub',v_content_user::text,true);
  v_blocked:=false;
  begin
    perform * from api.finance_revenue_overview(null);
  exception when others then
    v_blocked:=true;
  end;
  if not v_blocked then raise exception 'content_studio received finance API access'; end if;

  if has_table_privilege('authenticated','finance.revenue','SELECT') then raise exception 'authenticated has direct finance.revenue SELECT'; end if;
  if has_table_privilege('authenticated','finance.bank_transactions','SELECT') then raise exception 'authenticated has direct bank transaction SELECT'; end if;

  if (select next_number from config.id_allocators where entity_key='Journal Batch')<=v_next_jrn then raise exception 'Journal allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='AR')<=v_next_ar then raise exception 'AR allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='AP')<=v_next_ap then raise exception 'AP allocator not exercised'; end if;
  if (select next_number from config.id_allocators where entity_key='Tax Doc')<=v_next_tax then raise exception 'Tax allocator not exercised'; end if;
end $$;

rollback;