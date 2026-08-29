begin;

create or replace function finance.transition_revenue_state(
  p_revenue_id text,
  p_new_state text,
  p_evidence_id text default null,
  p_bank_txn_id text default null,
  p_reason text default null,
  p_actor text default 'system'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v finance.revenue;
  r finance.state_transition_rules;
  b finance.bank_transactions;
  v_state text:=upper(p_new_state);
  v_net numeric;
begin
  perform finance.require_write_gate();
  select * into v from finance.revenue where revenue_id=p_revenue_id for update;
  if not found then raise exception 'unknown revenue_id'; end if;
  if v.status=v_state then return jsonb_build_object('revenue_id',p_revenue_id,'status',v.status,'duplicate_transition',true); end if;
  select * into r from finance.state_transition_rules where entity_type='REVENUE' and from_state=v.status and to_state=v_state;
  if not found then raise exception 'revenue transition not allowed'; end if;
  if r.requires_evidence and p_evidence_id is null and v.evidence_id is null and v.collection_evidence_id is null then raise exception 'evidence required for revenue transition'; end if;

  if v_state='INVOICED' then
    if v.invoice_no is null or v.invoice_date is null or v.due_date is null then raise exception 'invoice fields required before INVOICED'; end if;
    update finance.revenue set evidence_id=coalesce(p_evidence_id,evidence_id),updated_at=now() where revenue_id=p_revenue_id;
  elsif v_state='COLLECTED' then
    if not config.setting_is_true('finance_collection_state_enabled') then raise exception 'finance collection-state gate is disabled'; end if;
    if p_evidence_id is null or p_bank_txn_id is null then raise exception 'COLLECTED requires evidence and bank transaction'; end if;
    select * into b from finance.bank_transactions where bank_txn_id=p_bank_txn_id;
    if not found or b.direction<>'IN' or not b.reconciled then raise exception 'COLLECTED requires reconciled incoming bank transaction'; end if;
    v_net:=coalesce(v.net_received,v.gross-v.wht);
    if b.amount<>v_net then raise exception 'bank amount does not equal revenue net received'; end if;
    if b.evidence_id is distinct from p_evidence_id then raise exception 'bank transaction evidence mismatch'; end if;
    update finance.revenue set
      collection_date=coalesce(collection_date,b.txn_at::date),
      net_received=coalesce(net_received,v_net),
      payment_ref=coalesce(payment_ref,b.bank_ref,b.bank_txn_id),
      collection_evidence_id=p_evidence_id,
      collection_bank_txn_id=p_bank_txn_id,
      updated_at=now()
    where revenue_id=p_revenue_id;
    update finance.accounts_receivable
      set collected=least(gross_amount-deduction,v_net),updated_at=now()
      where revenue_id=p_revenue_id;
  end if;

  update finance.revenue set status=v_state,updated_at=now() where revenue_id=p_revenue_id;
  insert into finance.financial_state_history(entity_type,entity_id,old_state,new_state,reason,evidence_id,bank_txn_id,actor)
  values('REVENUE',p_revenue_id,v.status,v_state,p_reason,p_evidence_id,p_bank_txn_id,p_actor);
  return jsonb_build_object('revenue_id',p_revenue_id,'old_state',v.status,'new_state',v_state,'duplicate_transition',false);
end;
$$;

revoke all on function finance.transition_revenue_state(text,text,text,text,text,text) from public;
grant execute on function finance.transition_revenue_state(text,text,text,text,text,text) to service_role;

commit;