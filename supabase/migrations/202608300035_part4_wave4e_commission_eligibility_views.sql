begin;

create or replace view finance.commission_payable_candidates_v as
select
  c.commission_id,
  c.partner_id,
  c.placement_id,
  c.revenue_id,
  c.milestone,
  c.commission_amount,
  c.state,
  r.status as revenue_status,
  r.collection_date,
  r.net_received,
  r.collection_evidence_id,
  case when c.state='WAITING_COLLECTION' and r.status='COLLECTED' then true else false end as payable_eligible
from finance.commissions c
left join finance.revenue r on r.revenue_id=c.revenue_id;

create or replace function finance.commission_transition_allowed(p_commission_id text,p_new_state text)
returns boolean
language sql
security definer
set search_path=''
as $$
  select exists(
    select 1
    from finance.commissions c
    join finance.state_transition_rules r
      on r.entity_type='COMMISSION'
     and r.from_state=c.state
     and r.to_state=upper(p_new_state)
    where c.commission_id=p_commission_id
      and upper(p_new_state)<>'PAID'
      and (
        upper(p_new_state)<>'PAYABLE'
        or exists(select 1 from finance.revenue rv where rv.revenue_id=c.revenue_id and rv.status='COLLECTED')
      )
  );
$$;

revoke all on function finance.commission_transition_allowed(text,text) from public;
grant execute on function finance.commission_transition_allowed(text,text) to service_role;

commit;