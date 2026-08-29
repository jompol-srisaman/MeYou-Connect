begin;

create table if not exists finance.accounts (
  account_code text primary key,
  account_name text not null,
  account_type text not null check (account_type in ('Asset','Liability','Equity','Revenue','Expense')),
  category text,
  normal_balance text not null check (normal_balance in ('Debit','Credit')),
  active boolean not null default true,
  data_hub_category text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into finance.accounts(account_code,account_name,account_type,category,normal_balance,active,data_hub_category,notes)
values
 ('1100','เงินฝากธนาคาร','Asset','Cash/Bank','Debit',true,'Collected / Bank',null),
 ('1110','เงินสดย่อย','Asset','Cash','Debit',true,null,null),
 ('1200','ลูกหนี้การค้า','Asset','AR','Debit',true,'INVOICED',null),
 ('1300','ค่าใช้จ่ายจ่ายล่วงหน้า','Asset','Prepaid','Debit',true,null,null),
 ('1500','อุปกรณ์ / สินทรัพย์สำนักงาน','Asset','Fixed Asset','Debit',true,null,'ทบทวนเกณฑ์สินทรัพย์กับผู้ทำบัญชี'),
 ('2000','เจ้าหนี้การค้า','Liability','AP','Credit',true,null,null),
 ('2100','ค่านายหน้า Partner ค้างจ่าย','Liability','Commission Payable','Credit',true,'Commission PAYABLE',null),
 ('2200','ภาษี/ยอดหัก ณ ที่จ่ายรอตรวจ','Liability','Tax Review','Credit',true,null,'ห้ามใช้ยื่นจริงก่อนผู้ทำบัญชีทบทวน'),
 ('3000','เงินลงทุน Founder','Equity','Owner Contribution','Credit',true,null,null),
 ('3100','ถอนใช้ส่วนตัว Founder','Equity','Owner Draw','Debit',true,null,null),
 ('4000','รายได้ Placement / Recruitment','Revenue','Placement','Credit',true,'Started/D3/D7/D30/D90',null),
 ('4100','รายได้ Relocation Concierge','Revenue','Concierge','Credit',true,null,null),
 ('4200','รายได้ Dorm Referral','Revenue','Dorm','Credit',true,null,null),
 ('4300','รายได้ Campaign / Content','Revenue','Campaign','Credit',true,null,null),
 ('4400','รายได้ Transport / Referral','Revenue','Transport','Credit',true,null,null),
 ('4900','รายได้อื่น','Revenue','Other','Credit',true,null,null),
 ('5000','ค่า Commission Partner','Expense','Partner Commission','Debit',true,null,null),
 ('5100','ค่าน้ำมัน','Expense','Fuel','Debit',true,null,null),
 ('5110','ค่าทางด่วน / ที่จอด','Expense','Toll/Parking','Debit',true,null,null),
 ('5200','ค่าขนส่ง / รถรับส่ง','Expense','Transport','Debit',true,null,null),
 ('5300','ค่าโฆษณา / Content','Expense','Ads/Content','Debit',true,null,null),
 ('5400','Software / Subscription','Expense','Software','Debit',true,null,null),
 ('5500','โทรศัพท์ / พิมพ์เอกสาร','Expense','Phone/Printing','Debit',true,null,null),
 ('5600','ค่าบริการวิชาชีพ','Expense','Professional Fee','Debit',true,null,null),
 ('5700','ค่าตรวจ/เอกสาร','Expense','Medical/Document','Debit',true,null,null),
 ('5800','ค่าเยี่ยมหอ / ประสานที่พัก','Expense','Dorm Visit','Debit',true,null,null),
 ('5900','ค่าใช้จ่ายอื่น','Expense','Other','Debit',true,null,null)
on conflict(account_code) do update set
 account_name=excluded.account_name, account_type=excluded.account_type, category=excluded.category,
 normal_balance=excluded.normal_balance, active=excluded.active, data_hub_category=excluded.data_hub_category,
 notes=excluded.notes, updated_at=now();

create table if not exists finance.revenue (
  revenue_id text primary key,
  transaction_date date not null,
  client_id text references core.clients(client_id) on delete restrict,
  placement_id text references core.placements(placement_id) on delete restrict,
  revenue_type text not null,
  milestone text,
  gross numeric(14,2) not null check (gross>=0),
  wht numeric(14,2) not null default 0 check (wht>=0),
  status text not null check (status in ('EXPECTED','EARNED','INVOICED','COLLECTED','CANCELLED')),
  invoice_no text,
  invoice_date date,
  due_date date,
  collection_date date,
  net_received numeric(14,2) check (net_received is null or net_received>=0),
  payment_ref text,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  collection_evidence_id text references docs.evidence(evidence_id) on delete restrict,
  collection_bank_txn_id text,
  source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  notes text,
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status<>'INVOICED' or (invoice_no is not null and invoice_date is not null and due_date is not null)),
  check (status<>'COLLECTED' or (collection_date is not null and net_received is not null and net_received>=0))
);

create index if not exists revenue_client_idx on finance.revenue(client_id);
create index if not exists revenue_placement_idx on finance.revenue(placement_id);
create index if not exists revenue_status_due_idx on finance.revenue(status,due_date);
create index if not exists revenue_evidence_idx on finance.revenue(evidence_id);
create index if not exists revenue_collection_evidence_idx on finance.revenue(collection_evidence_id);

create table if not exists finance.expenses (
  expense_id text primary key,
  expense_date date not null,
  placement_id text references core.placements(placement_id) on delete restrict,
  expense_category text not null,
  description text,
  gross_before_tax numeric(14,2) not null default 0 check (gross_before_tax>=0),
  vat numeric(14,2) not null default 0 check (vat>=0),
  wht numeric(14,2) not null default 0 check (wht>=0),
  net_paid numeric(14,2) not null default 0 check (net_paid>=0),
  payment_method text,
  payer text,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  notes text,
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists expenses_placement_idx on finance.expenses(placement_id);
create index if not exists expenses_evidence_idx on finance.expenses(evidence_id);
create index if not exists expenses_date_idx on finance.expenses(expense_date);

create table if not exists finance.commissions (
  commission_id text primary key,
  partner_id text not null references core.partners(partner_id) on delete restrict,
  placement_id text references core.placements(placement_id) on delete restrict,
  revenue_id text references finance.revenue(revenue_id) on delete restrict,
  milestone text,
  commission_amount numeric(14,2) not null check (commission_amount>=0),
  state text not null check (state in ('PENDING','EARNED','WAITING_COLLECTION','PAYABLE','PAID','CANCELLED')),
  earned_date date,
  payable_date date,
  paid_date date,
  payment_ref text,
  payment_evidence_id text references docs.evidence(evidence_id) on delete restrict,
  payment_bank_txn_id text,
  override_from_partner_id text references core.partners(partner_id) on delete restrict,
  override_40 boolean not null default false,
  notes text,
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (state<>'EARNED' or earned_date is not null),
  check (state<>'PAYABLE' or payable_date is not null),
  check (state<>'PAID' or (paid_date is not null and payment_ref is not null))
);
create index if not exists commissions_partner_idx on finance.commissions(partner_id);
create index if not exists commissions_placement_idx on finance.commissions(placement_id);
create index if not exists commissions_revenue_idx on finance.commissions(revenue_id);
create index if not exists commissions_state_idx on finance.commissions(state);
create index if not exists commissions_payment_evidence_idx on finance.commissions(payment_evidence_id);

create table if not exists finance.journal_batches (
  journal_batch_id text primary key check (journal_batch_id ~ '^WC-JRN-[0-9]{6}$'),
  journal_date date not null,
  source_type text,
  source_ref text,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  file_id text references docs.files(file_id) on delete restrict,
  client_id text references core.clients(client_id) on delete restrict,
  candidate_id text references core.candidates(candidate_id) on delete restrict,
  placement_id text references core.placements(placement_id) on delete restrict,
  partner_id text references core.partners(partner_id) on delete restrict,
  description text,
  currency text not null default 'THB',
  status text not null default 'DRAFT' check (status in ('DRAFT','POSTED','CANCELLED')),
  posted_at timestamptz,
  posted_by text,
  notes text,
  created_by text not null default 'system',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (status<>'POSTED' or (posted_at is not null and posted_by is not null))
);
create index if not exists journal_batches_evidence_idx on finance.journal_batches(evidence_id);
create index if not exists journal_batches_source_idx on finance.journal_batches(source_type,source_ref);

create table if not exists finance.journal_lines (
  journal_batch_id text not null references finance.journal_batches(journal_batch_id) on delete restrict,
  line_no integer not null check (line_no>0),
  account_code text not null references finance.accounts(account_code) on delete restrict,
  line_description text,
  debit numeric(14,2) not null default 0 check (debit>=0),
  credit numeric(14,2) not null default 0 check (credit>=0),
  currency text not null default 'THB',
  tax_document_ref text,
  bank_cash_ref text,
  created_at timestamptz not null default now(),
  primary key(journal_batch_id,line_no),
  check ((debit>0 and credit=0) or (credit>0 and debit=0))
);
create index if not exists journal_lines_account_idx on finance.journal_lines(account_code);

create table if not exists finance.accounts_receivable (
  ar_id text primary key check (ar_id ~ '^WC-AR-[0-9]{6}$'),
  client_id text not null references core.clients(client_id) on delete restrict,
  placement_id text references core.placements(placement_id) on delete restrict,
  revenue_id text not null references finance.revenue(revenue_id) on delete restrict,
  invoice_no text not null,
  invoice_date date not null,
  due_date date not null,
  gross_amount numeric(14,2) not null check (gross_amount>=0),
  deduction numeric(14,2) not null default 0 check (deduction>=0),
  collected numeric(14,2) not null default 0 check (collected>=0),
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  file_id text references docs.files(file_id) on delete restrict,
  journal_batch_id text references finance.journal_batches(journal_batch_id) on delete restrict,
  contact_ref text,
  next_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(revenue_id),
  check (deduction<=gross_amount),
  check (collected<=gross_amount)
);
create index if not exists ar_client_idx on finance.accounts_receivable(client_id);
create index if not exists ar_due_idx on finance.accounts_receivable(due_date);
create index if not exists ar_evidence_idx on finance.accounts_receivable(evidence_id);
create index if not exists ar_batch_idx on finance.accounts_receivable(journal_batch_id);

create table if not exists finance.accounts_payable (
  ap_id text primary key check (ap_id ~ '^WC-AP-[0-9]{6}$'),
  payee_ref text,
  partner_id text references core.partners(partner_id) on delete restrict,
  placement_id text references core.placements(placement_id) on delete restrict,
  expense_id text references finance.expenses(expense_id) on delete restrict,
  commission_id text references finance.commissions(commission_id) on delete restrict,
  bill_ref_no text,
  bill_date date,
  due_date date not null,
  gross_amount numeric(14,2) not null check (gross_amount>=0),
  deduction numeric(14,2) not null default 0 check (deduction>=0),
  paid numeric(14,2) not null default 0 check (paid>=0),
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  file_id text references docs.files(file_id) on delete restrict,
  journal_batch_id text references finance.journal_batches(journal_batch_id) on delete restrict,
  payment_ref text,
  next_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (deduction<=gross_amount),
  check (paid<=gross_amount),
  check (partner_id is not null or payee_ref is not null),
  check (expense_id is not null or commission_id is not null or payee_ref is not null)
);
create index if not exists ap_partner_idx on finance.accounts_payable(partner_id);
create index if not exists ap_due_idx on finance.accounts_payable(due_date);
create index if not exists ap_expense_idx on finance.accounts_payable(expense_id);
create index if not exists ap_commission_idx on finance.accounts_payable(commission_id);
create index if not exists ap_evidence_idx on finance.accounts_payable(evidence_id);
create index if not exists ap_batch_idx on finance.accounts_payable(journal_batch_id);

create table if not exists finance.bank_transactions (
  bank_txn_id text primary key check (bank_txn_id ~ '^WC-BANK-[0-9]{6}$'),
  txn_at timestamptz not null,
  account_wallet text not null,
  bank_ref text,
  direction text not null check (direction in ('IN','OUT')),
  amount numeric(14,2) not null check (amount>0),
  counterparty text,
  description text,
  raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  file_id text references docs.files(file_id) on delete restrict,
  journal_batch_id text references finance.journal_batches(journal_batch_id) on delete restrict,
  client_id text references core.clients(client_id) on delete restrict,
  placement_id text references core.placements(placement_id) on delete restrict,
  partner_id text references core.partners(partner_id) on delete restrict,
  revenue_id text references finance.revenue(revenue_id) on delete restrict,
  expense_id text references finance.expenses(expense_id) on delete restrict,
  commission_id text references finance.commissions(commission_id) on delete restrict,
  reconciled boolean not null default false,
  reconciled_at timestamptz,
  reconciled_by text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not reconciled or (reconciled_at is not null and reconciled_by is not null))
);
create index if not exists bank_txn_evidence_idx on finance.bank_transactions(evidence_id);
create index if not exists bank_txn_batch_idx on finance.bank_transactions(journal_batch_id);
create index if not exists bank_txn_revenue_idx on finance.bank_transactions(revenue_id);
create index if not exists bank_txn_commission_idx on finance.bank_transactions(commission_id);
create index if not exists bank_txn_reconciled_idx on finance.bank_transactions(reconciled,txn_at);

alter table finance.revenue
  drop constraint if exists revenue_collection_bank_txn_id_fkey;
alter table finance.revenue
  add constraint revenue_collection_bank_txn_id_fkey foreign key(collection_bank_txn_id) references finance.bank_transactions(bank_txn_id) on delete restrict;
create index if not exists revenue_collection_bank_idx on finance.revenue(collection_bank_txn_id);

alter table finance.commissions
  drop constraint if exists commissions_payment_bank_txn_id_fkey;
alter table finance.commissions
  add constraint commissions_payment_bank_txn_id_fkey foreign key(payment_bank_txn_id) references finance.bank_transactions(bank_txn_id) on delete restrict;
create index if not exists commissions_payment_bank_idx on finance.commissions(payment_bank_txn_id);

create table if not exists finance.tax_documents (
  tax_doc_id text primary key check (tax_doc_id ~ '^WC-TAX-[0-9]{6}$'),
  document_type text not null,
  document_date date not null,
  counterparty text,
  counterparty_entity_id text,
  invoice_ref_no text,
  gross_amount numeric(14,2) not null default 0 check (gross_amount>=0),
  wht_amount numeric(14,2) not null default 0 check (wht_amount>=0),
  tax_other_amount numeric(14,2) not null default 0 check (tax_other_amount>=0),
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  file_id text references docs.files(file_id) on delete restrict,
  journal_batch_id text references finance.journal_batches(journal_batch_id) on delete restrict,
  period text,
  status text not null default 'PREPARED' check (status in ('PREPARED','REVIEW_REQUIRED','REVIEWED','VOID')),
  accountant_reviewed boolean not null default false,
  reviewed_by text,
  reviewed_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (not accountant_reviewed or (reviewed_by is not null and reviewed_at is not null))
);
create index if not exists tax_documents_evidence_idx on finance.tax_documents(evidence_id);
create index if not exists tax_documents_batch_idx on finance.tax_documents(journal_batch_id);
create index if not exists tax_documents_period_idx on finance.tax_documents(period,status);

create table if not exists finance.monthly_close_checks (
  close_month date not null check (date_trunc('month',close_month)::date=close_month),
  close_id text not null check (close_id in ('CLOSE-001','CLOSE-002','CLOSE-003','CLOSE-004','CLOSE-005','CLOSE-006')),
  check_description text not null,
  owner text not null,
  status text not null default 'OPEN' check (status in ('OPEN','PASS','ISSUE','WAIVED')),
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  issue_gap text,
  resolved_at timestamptz,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(close_month,close_id)
);

create table if not exists finance.financial_state_history (
  state_history_id uuid primary key default gen_random_uuid(),
  entity_type text not null check (entity_type in ('REVENUE','COMMISSION')),
  entity_id text not null,
  old_state text,
  new_state text not null,
  reason text,
  evidence_id text references docs.evidence(evidence_id) on delete restrict,
  bank_txn_id text references finance.bank_transactions(bank_txn_id) on delete restrict,
  actor text not null,
  created_at timestamptz not null default now()
);
create index if not exists financial_state_history_entity_idx on finance.financial_state_history(entity_type,entity_id,created_at);
create index if not exists financial_state_history_evidence_idx on finance.financial_state_history(evidence_id);
create index if not exists financial_state_history_bank_idx on finance.financial_state_history(bank_txn_id);

create table if not exists finance.state_transition_rules (
  entity_type text not null check (entity_type in ('REVENUE','COMMISSION')),
  from_state text not null,
  to_state text not null,
  requires_evidence boolean not null default false,
  requires_bank_reconciliation boolean not null default false,
  protected_transition boolean not null default false,
  notes text,
  primary key(entity_type,from_state,to_state)
);

insert into finance.state_transition_rules(entity_type,from_state,to_state,requires_evidence,requires_bank_reconciliation,protected_transition,notes)
values
 ('REVENUE','EXPECTED','EARNED',false,false,false,'Business milestone earned.'),
 ('REVENUE','EARNED','INVOICED',true,false,false,'Invoice evidence/reference required.'),
 ('REVENUE','INVOICED','COLLECTED',true,true,true,'Only matched/reconciled incoming money is collected.'),
 ('REVENUE','EXPECTED','CANCELLED',false,false,false,'Cancel before earning.'),
 ('REVENUE','EARNED','CANCELLED',false,false,false,'Cancel before invoice.'),
 ('REVENUE','INVOICED','CANCELLED',true,false,true,'Cancellation after invoice requires evidence/review.'),
 ('COMMISSION','PENDING','EARNED',false,false,false,'Milestone earned.'),
 ('COMMISSION','EARNED','WAITING_COLLECTION',false,false,false,'Wait until linked revenue is collected.'),
 ('COMMISSION','WAITING_COLLECTION','PAYABLE',true,false,true,'Linked revenue must be COLLECTED.'),
 ('COMMISSION','PAYABLE','PAID',true,true,true,'Recording an observed/reconciled outbound payment only; does not execute transfer.'),
 ('COMMISSION','PENDING','CANCELLED',false,false,false,'Cancelled before earned.'),
 ('COMMISSION','EARNED','CANCELLED',false,false,false,'Cancelled before payable.'),
 ('COMMISSION','WAITING_COLLECTION','CANCELLED',false,false,false,'Cancelled before payable.'),
 ('COMMISSION','PAYABLE','CANCELLED',true,false,true,'Cancellation of payable requires evidence/review.')
on conflict do nothing;

create or replace view finance.accounts_receivable_v as
select ar.*,
       greatest(ar.gross_amount-ar.deduction,0)::numeric(14,2) as net_due,
       greatest((ar.gross_amount-ar.deduction)-ar.collected,0)::numeric(14,2) as outstanding,
       case
         when greatest((ar.gross_amount-ar.deduction)-ar.collected,0)<=0 then 'PAID'
         when ar.collected>0 then 'PARTIAL'
         when ar.due_date<current_date then 'OVERDUE'
         else 'OPEN'
       end as derived_status,
       greatest(current_date-ar.due_date,0) as days_overdue
from finance.accounts_receivable ar;

create or replace view finance.accounts_payable_v as
select ap.*,
       greatest(ap.gross_amount-ap.deduction,0)::numeric(14,2) as net_payable,
       greatest((ap.gross_amount-ap.deduction)-ap.paid,0)::numeric(14,2) as outstanding,
       case
         when greatest((ap.gross_amount-ap.deduction)-ap.paid,0)<=0 then 'PAID'
         when ap.paid>0 then 'PARTIAL'
         when ap.due_date<current_date then 'OVERDUE'
         else 'OPEN'
       end as derived_status,
       greatest(current_date-ap.due_date,0) as days_due
from finance.accounts_payable ap;

create or replace view finance.trial_balance_v as
select a.account_code,a.account_name,a.account_type,a.normal_balance,
       coalesce(sum(case when jb.status='POSTED' then jl.debit else 0 end),0)::numeric(16,2) as total_debit,
       coalesce(sum(case when jb.status='POSTED' then jl.credit else 0 end),0)::numeric(16,2) as total_credit,
       case when a.normal_balance='Debit'
            then coalesce(sum(case when jb.status='POSTED' then jl.debit-jl.credit else 0 end),0)
            else coalesce(sum(case when jb.status='POSTED' then jl.credit-jl.debit else 0 end),0)
       end::numeric(16,2) as normal_balance_amount
from finance.accounts a
left join finance.journal_lines jl on jl.account_code=a.account_code
left join finance.journal_batches jb on jb.journal_batch_id=jl.journal_batch_id
group by a.account_code,a.account_name,a.account_type,a.normal_balance;

create or replace view finance.pnl_internal_v as
select a.account_code,a.account_name,a.account_type,
       case when a.account_type='Revenue'
            then coalesce(sum(case when jb.status='POSTED' then jl.credit-jl.debit else 0 end),0)
            when a.account_type='Expense'
            then coalesce(sum(case when jb.status='POSTED' then jl.debit-jl.credit else 0 end),0)
            else 0 end::numeric(16,2) as amount
from finance.accounts a
left join finance.journal_lines jl on jl.account_code=a.account_code
left join finance.journal_batches jb on jb.journal_batch_id=jl.journal_batch_id
where a.account_type in ('Revenue','Expense')
group by a.account_code,a.account_name,a.account_type;

commit;