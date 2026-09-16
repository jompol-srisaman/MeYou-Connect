create table if not exists finance.payment_allocations (
  allocation_pk uuid primary key default gen_random_uuid(),
  bank_txn_id text not null references finance.bank_transactions(bank_txn_id) on delete restrict,
  revenue_id text references finance.revenue(revenue_id) on delete restrict,
  ar_id text references finance.accounts_receivable(ar_id) on delete restrict,
  allocated_amount numeric not null check (allocated_amount > 0),
  evidence_id text not null references docs.evidence(evidence_id) on delete restrict,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(revenue_id, ar_id) = 1)
);

create unique index if not exists payment_allocations_bank_revenue_uq
  on finance.payment_allocations(bank_txn_id, revenue_id)
  where revenue_id is not null;
create unique index if not exists payment_allocations_bank_ar_uq
  on finance.payment_allocations(bank_txn_id, ar_id)
  where ar_id is not null;
create index if not exists payment_allocations_revenue_idx on finance.payment_allocations(revenue_id) where revenue_id is not null;
create index if not exists payment_allocations_ar_idx on finance.payment_allocations(ar_id) where ar_id is not null;

create or replace function finance.guard_payment_allocation_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, finance
as $$
declare
  v_direction text;
  v_amount numeric;
  v_existing numeric;
begin
  select direction, amount into v_direction, v_amount
  from finance.bank_transactions
  where bank_txn_id = new.bank_txn_id
  for update;

  if not found then raise exception 'bank transaction not found'; end if;
  if v_direction <> 'IN' then raise exception 'Revenue/AR allocation requires inbound bank transaction'; end if;

  select coalesce(sum(allocated_amount),0) into v_existing
  from finance.payment_allocations
  where bank_txn_id = new.bank_txn_id
    and allocation_pk <> new.allocation_pk;

  if v_existing + new.allocated_amount > v_amount then
    raise exception 'allocation exceeds bank transaction amount';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function finance.guard_payment_allocation_v1() from public, anon, authenticated;

drop trigger if exists payment_allocations_guard_v1 on finance.payment_allocations;
create trigger payment_allocations_guard_v1
before insert or update on finance.payment_allocations
for each row execute function finance.guard_payment_allocation_v1();

create table if not exists finance.partner_adjustments (
  adjustment_pk uuid primary key default gen_random_uuid(),
  partner_id text not null references core.partners(partner_id) on delete restrict,
  adjustment_type text not null check (adjustment_type in ('ADVANCE','DEDUCTION','REIMBURSEMENT')),
  amount numeric not null check (amount > 0),
  effective_at timestamptz not null,
  evidence_id text not null references docs.evidence(evidence_id) on delete restrict,
  bank_txn_id text references finance.bank_transactions(bank_txn_id) on delete restrict,
  source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  notes text,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists partner_adjustments_partner_time_idx
  on finance.partner_adjustments(partner_id, effective_at desc);
create index if not exists partner_adjustments_bank_idx
  on finance.partner_adjustments(bank_txn_id) where bank_txn_id is not null;
create index if not exists partner_adjustments_raw_idx
  on finance.partner_adjustments(source_raw_input_id) where source_raw_input_id is not null;

create table if not exists finance.partner_adjustment_applications (
  application_pk uuid primary key default gen_random_uuid(),
  adjustment_pk uuid not null references finance.partner_adjustments(adjustment_pk) on delete restrict,
  ap_id text not null references finance.accounts_payable(ap_id) on delete restrict,
  applied_amount numeric not null check (applied_amount > 0),
  evidence_id text not null references docs.evidence(evidence_id) on delete restrict,
  created_by text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(adjustment_pk, ap_id)
);

create index if not exists partner_adjustment_applications_ap_idx
  on finance.partner_adjustment_applications(ap_id);

create or replace function finance.guard_partner_adjustment_application_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, finance
as $$
declare
  v_amount numeric;
  v_existing numeric;
begin
  select amount into v_amount
  from finance.partner_adjustments
  where adjustment_pk = new.adjustment_pk
  for update;

  if not found then raise exception 'partner adjustment not found'; end if;

  select coalesce(sum(applied_amount),0) into v_existing
  from finance.partner_adjustment_applications
  where adjustment_pk = new.adjustment_pk
    and application_pk <> new.application_pk;

  if v_existing + new.applied_amount > v_amount then
    raise exception 'application exceeds adjustment amount';
  end if;

  new.updated_at := now();
  return new;
end;
$$;

revoke all on function finance.guard_partner_adjustment_application_v1() from public, anon, authenticated;

drop trigger if exists partner_adjustment_application_guard_v1 on finance.partner_adjustment_applications;
create trigger partner_adjustment_application_guard_v1
before insert or update on finance.partner_adjustment_applications
for each row execute function finance.guard_partner_adjustment_application_v1();

create or replace view finance.payment_allocation_summary_v as
select
  b.bank_txn_id,
  b.txn_at,
  b.bank_ref,
  b.direction,
  b.amount,
  coalesce(sum(a.allocated_amount),0) as allocated_amount,
  greatest(b.amount - coalesce(sum(a.allocated_amount),0),0) as unallocated_amount,
  count(a.allocation_pk) as allocation_count,
  b.reconciled,
  b.reconciled_at
from finance.bank_transactions b
left join finance.payment_allocations a on a.bank_txn_id=b.bank_txn_id
group by b.bank_txn_id,b.txn_at,b.bank_ref,b.direction,b.amount,b.reconciled,b.reconciled_at;

create or replace view finance.partner_adjustment_balance_v as
select
  a.adjustment_pk,
  a.partner_id,
  a.adjustment_type,
  a.amount,
  coalesce(sum(x.applied_amount),0) as applied_amount,
  greatest(a.amount - coalesce(sum(x.applied_amount),0),0) as open_balance,
  case
    when coalesce(sum(x.applied_amount),0)=0 then 'OPEN'
    when coalesce(sum(x.applied_amount),0) < a.amount then 'PARTIAL'
    else 'APPLIED'
  end as balance_state,
  case
    when a.adjustment_type in ('ADVANCE','DEDUCTION') then -greatest(a.amount - coalesce(sum(x.applied_amount),0),0)
    when a.adjustment_type='REIMBURSEMENT' then greatest(a.amount - coalesce(sum(x.applied_amount),0),0)
  end as open_settlement_effect,
  a.effective_at,
  a.evidence_id,
  a.bank_txn_id,
  a.source_raw_input_id
from finance.partner_adjustments a
left join finance.partner_adjustment_applications x on x.adjustment_pk=a.adjustment_pk
group by a.adjustment_pk,a.partner_id,a.adjustment_type,a.amount,a.effective_at,a.evidence_id,a.bank_txn_id,a.source_raw_input_id;

create or replace view finance.duplicate_bank_reference_v as
select bank_ref, direction, count(*) as duplicate_count, min(txn_at) as first_seen_at, max(txn_at) as latest_seen_at
from finance.bank_transactions
where bank_ref is not null and btrim(bank_ref) <> ''
group by bank_ref,direction
having count(*) > 1;

alter table finance.payment_allocations enable row level security;
alter table finance.partner_adjustments enable row level security;
alter table finance.partner_adjustment_applications enable row level security;

drop policy if exists finance_deny_anon on finance.payment_allocations;
create policy finance_deny_anon on finance.payment_allocations for all to anon using(false) with check(false);
drop policy if exists finance_deny_authenticated on finance.payment_allocations;
create policy finance_deny_authenticated on finance.payment_allocations for all to authenticated using(false) with check(false);
drop policy if exists finance_deny_anon on finance.partner_adjustments;
create policy finance_deny_anon on finance.partner_adjustments for all to anon using(false) with check(false);
drop policy if exists finance_deny_authenticated on finance.partner_adjustments;
create policy finance_deny_authenticated on finance.partner_adjustments for all to authenticated using(false) with check(false);
drop policy if exists finance_deny_anon on finance.partner_adjustment_applications;
create policy finance_deny_anon on finance.partner_adjustment_applications for all to anon using(false) with check(false);
drop policy if exists finance_deny_authenticated on finance.partner_adjustment_applications;
create policy finance_deny_authenticated on finance.partner_adjustment_applications for all to authenticated using(false) with check(false);

revoke all on finance.payment_allocations from public, anon, authenticated;
revoke all on finance.partner_adjustments from public, anon, authenticated;
revoke all on finance.partner_adjustment_applications from public, anon, authenticated;
revoke all on finance.payment_allocation_summary_v from public, anon, authenticated;
revoke all on finance.partner_adjustment_balance_v from public, anon, authenticated;
revoke all on finance.duplicate_bank_reference_v from public, anon, authenticated;

grant select,insert,update on finance.payment_allocations to service_role;
grant select,insert,update on finance.partner_adjustments to service_role;
grant select,insert,update on finance.partner_adjustment_applications to service_role;
grant select on finance.payment_allocation_summary_v, finance.partner_adjustment_balance_v, finance.duplicate_bank_reference_v to service_role;

comment on table finance.payment_allocations is 'Finance V1.0.1 allocation bridge. Supports many bank transactions to many Revenue/AR targets without changing operational SoT or executing money movement.';
comment on table finance.partner_adjustments is 'Finance V1.0.1 evidence-backed Partner ADVANCE/DEDUCTION/REIMBURSEMENT ledger. Separate from Commission entitlement and payment execution.';
comment on view finance.partner_adjustment_balance_v is 'Derived open balance and settlement effect only. It does not authorize or execute a payment/deduction.';

do $$
declare v jsonb;
begin
  select setting_value into v from config.system_settings where setting_key='finance_external_payment_execution_enabled';
  if v is distinct from 'false'::jsonb then
    raise exception 'finance_external_payment_execution_enabled must remain false';
  end if;
  if exists(select 1 from finance.payment_allocations) then
    raise exception 'foundation migration must not create payment allocations';
  end if;
  if exists(select 1 from finance.partner_adjustments) then
    raise exception 'foundation migration must not create partner adjustment business facts';
  end if;
end $$;
