begin;

insert into authz.role_capabilities(role_key,capability_key)
values
 ('founder','finance_read'),('founder','finance_accounting_read'),
 ('secretary','finance_read'),
 ('finance_control','finance_read'),('finance_control','finance_accounting_read'),
 ('data_audit','finance_read'),('data_audit','finance_accounting_read')
on conflict do nothing;

alter table finance.accounts enable row level security;
alter table finance.revenue enable row level security;
alter table finance.expenses enable row level security;
alter table finance.commissions enable row level security;
alter table finance.journal_batches enable row level security;
alter table finance.journal_lines enable row level security;
alter table finance.accounts_receivable enable row level security;
alter table finance.accounts_payable enable row level security;
alter table finance.bank_transactions enable row level security;
alter table finance.tax_documents enable row level security;
alter table finance.monthly_close_checks enable row level security;
alter table finance.financial_state_history enable row level security;
alter table finance.state_transition_rules enable row level security;

do $$
declare t text;
begin
  foreach t in array array[
    'accounts','revenue','expenses','commissions','journal_batches','journal_lines',
    'accounts_receivable','accounts_payable','bank_transactions','tax_documents',
    'monthly_close_checks','financial_state_history','state_transition_rules'
  ] loop
    execute format('drop policy if exists finance_deny_authenticated on finance.%I',t);
    execute format('create policy finance_deny_authenticated on finance.%I as restrictive for all to authenticated using (false) with check (false)',t);
    execute format('drop policy if exists finance_deny_anon on finance.%I',t);
    execute format('create policy finance_deny_anon on finance.%I as restrictive for all to anon using (false) with check (false)',t);
  end loop;
end $$;

revoke all on all tables in schema finance from anon,authenticated;
revoke all on all sequences in schema finance from anon,authenticated;

create or replace function api.finance_revenue_overview(p_revenue_id text default null)
returns table(
  revenue_id text, transaction_date date, client_id text, placement_id text,
  revenue_type text, milestone text, gross numeric, wht numeric, net_after_wht numeric,
  status text, invoice_no text, invoice_date date, due_date date, collection_date date,
  net_received numeric, payment_ref text
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not authz.has_capability('finance_read') then raise exception 'not authorized'; end if;
  return query
  select r.revenue_id,r.transaction_date,r.client_id,r.placement_id,r.revenue_type,r.milestone,
         r.gross,r.wht,(r.gross-r.wht)::numeric,r.status,r.invoice_no,r.invoice_date,r.due_date,
         r.collection_date,r.net_received,r.payment_ref
  from finance.revenue r
  where p_revenue_id is null or r.revenue_id=p_revenue_id
  order by r.transaction_date desc,r.revenue_id;
end;
$$;

create or replace function api.finance_ar_aging()
returns table(
  ar_id text, client_id text, placement_id text, revenue_id text, invoice_no text,
  invoice_date date, due_date date, gross_amount numeric, deduction numeric, net_due numeric,
  collected numeric, outstanding numeric, derived_status text, days_overdue integer, next_action text
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not authz.has_capability('finance_read') then raise exception 'not authorized'; end if;
  return query
  select a.ar_id,a.client_id,a.placement_id,a.revenue_id,a.invoice_no,a.invoice_date,a.due_date,
         a.gross_amount,a.deduction,a.net_due,a.collected,a.outstanding,a.derived_status,a.days_overdue,a.next_action
  from finance.accounts_receivable_v a
  order by case when a.derived_status='OVERDUE' then 0 else 1 end,a.due_date,a.ar_id;
end;
$$;

create or replace function api.finance_commission_overview()
returns table(
  commission_id text, partner_id text, placement_id text, revenue_id text, milestone text,
  commission_amount numeric, state text, earned_date date, payable_date date, paid_date date,
  payable_eligible boolean, payment_ref text
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not authz.has_capability('finance_read') then raise exception 'not authorized'; end if;
  return query
  select c.commission_id,c.partner_id,c.placement_id,c.revenue_id,c.milestone,c.commission_amount,
         c.state,c.earned_date,c.payable_date,c.paid_date,
         coalesce(v.payable_eligible,false),
         case when authz.has_any_role(array['founder','finance_control']) then c.payment_ref else null end
  from finance.commissions c
  left join finance.commission_payable_candidates_v v on v.commission_id=c.commission_id
  order by c.created_at desc,c.commission_id;
end;
$$;

create or replace function api.finance_trial_balance()
returns table(
  account_code text, account_name text, account_type text, normal_balance text,
  total_debit numeric, total_credit numeric, normal_balance_amount numeric
)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not authz.has_capability('finance_accounting_read') then raise exception 'not authorized'; end if;
  return query select t.account_code,t.account_name,t.account_type,t.normal_balance,t.total_debit,t.total_credit,t.normal_balance_amount
  from finance.trial_balance_v t order by t.account_code;
end;
$$;

create or replace function api.finance_pnl_internal()
returns table(account_code text,account_name text,account_type text,amount numeric)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not authz.has_capability('finance_accounting_read') then raise exception 'not authorized'; end if;
  return query select p.account_code,p.account_name,p.account_type,p.amount from finance.pnl_internal_v p order by p.account_code;
end;
$$;

create or replace function api.finance_monthly_close(p_month date)
returns table(close_month date,close_id text,check_description text,owner text,status text,issue_gap text,resolved_at timestamptz,notes text)
language plpgsql
security definer
set search_path=''
as $$
begin
  if auth.uid() is null or not authz.has_capability('finance_read') then raise exception 'not authorized'; end if;
  return query
  select m.close_month,m.close_id,m.check_description,m.owner,m.status,m.issue_gap,m.resolved_at,m.notes
  from finance.monthly_close_checks m
  where m.close_month=date_trunc('month',p_month)::date
  order by m.close_id;
end;
$$;

revoke all on function api.finance_revenue_overview(text) from public;
revoke all on function api.finance_ar_aging() from public;
revoke all on function api.finance_commission_overview() from public;
revoke all on function api.finance_trial_balance() from public;
revoke all on function api.finance_pnl_internal() from public;
revoke all on function api.finance_monthly_close(date) from public;
grant execute on function api.finance_revenue_overview(text) to authenticated;
grant execute on function api.finance_ar_aging() to authenticated;
grant execute on function api.finance_commission_overview() to authenticated;
grant execute on function api.finance_trial_balance() to authenticated;
grant execute on function api.finance_pnl_internal() to authenticated;
grant execute on function api.finance_monthly_close(date) to authenticated;

commit;