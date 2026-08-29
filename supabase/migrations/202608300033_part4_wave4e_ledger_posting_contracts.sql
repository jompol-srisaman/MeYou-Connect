begin;

create or replace function finance.require_write_gate()
returns void
language plpgsql
security definer
set search_path=''
as $$
begin
  if not config.setting_is_true('finance_write_enabled') then
    raise exception 'finance write gate is disabled';
  end if;
end;
$$;

create or replace function finance.create_journal_batch(
  p_journal_date date,
  p_source_type text,
  p_source_ref text,
  p_raw_input_id text default null,
  p_evidence_id text default null,
  p_file_id text default null,
  p_description text default null,
  p_actor text default 'system'
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare v_alloc jsonb; v_id text;
begin
  perform finance.require_write_gate();
  v_alloc:=config.allocate_business_id('Journal Batch',p_actor,jsonb_build_object('source','Part4E finance.create_journal_batch'));
  v_id:=v_alloc->>'allocated_id';
  insert into finance.journal_batches(journal_batch_id,journal_date,source_type,source_ref,raw_input_id,evidence_id,file_id,description,created_by)
  values(v_id,p_journal_date,p_source_type,p_source_ref,p_raw_input_id,p_evidence_id,p_file_id,p_description,p_actor);
  return v_id;
end;
$$;

create or replace function finance.add_journal_line(
  p_journal_batch_id text,
  p_line_no integer,
  p_account_code text,
  p_debit numeric,
  p_credit numeric,
  p_description text default null,
  p_tax_document_ref text default null,
  p_bank_cash_ref text default null
)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_status text;
begin
  perform finance.require_write_gate();
  select status into v_status from finance.journal_batches where journal_batch_id=p_journal_batch_id for update;
  if not found then raise exception 'unknown journal batch'; end if;
  if v_status<>'DRAFT' then raise exception 'journal lines may only change while batch is DRAFT'; end if;
  insert into finance.journal_lines(journal_batch_id,line_no,account_code,line_description,debit,credit,tax_document_ref,bank_cash_ref)
  values(p_journal_batch_id,p_line_no,p_account_code,p_description,coalesce(p_debit,0),coalesce(p_credit,0),p_tax_document_ref,p_bank_cash_ref)
  on conflict(journal_batch_id,line_no) do update set
    account_code=excluded.account_code,line_description=excluded.line_description,
    debit=excluded.debit,credit=excluded.credit,tax_document_ref=excluded.tax_document_ref,
    bank_cash_ref=excluded.bank_cash_ref;
end;
$$;

create or replace function finance.post_journal_batch(
  p_journal_batch_id text,
  p_actor text default 'system'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_status text; v_debit numeric; v_credit numeric; v_lines int;
begin
  perform finance.require_write_gate();
  if not config.setting_is_true('finance_posting_enabled') then raise exception 'finance posting gate is disabled'; end if;
  select status into v_status from finance.journal_batches where journal_batch_id=p_journal_batch_id for update;
  if not found then raise exception 'unknown journal batch'; end if;
  if v_status='POSTED' then
    select count(*),coalesce(sum(debit),0),coalesce(sum(credit),0) into v_lines,v_debit,v_credit from finance.journal_lines where journal_batch_id=p_journal_batch_id;
    return jsonb_build_object('journal_batch_id',p_journal_batch_id,'status','POSTED','duplicate_post',true,'line_count',v_lines,'debit',v_debit,'credit',v_credit);
  end if;
  if v_status<>'DRAFT' then raise exception 'only DRAFT journal batches can be posted'; end if;
  select count(*),coalesce(sum(debit),0),coalesce(sum(credit),0) into v_lines,v_debit,v_credit from finance.journal_lines where journal_batch_id=p_journal_batch_id;
  if v_lines<2 then raise exception 'journal batch requires at least 2 lines'; end if;
  if v_debit<=0 or v_credit<=0 or v_debit<>v_credit then raise exception 'journal batch is not balanced'; end if;
  update finance.journal_batches set status='POSTED',posted_at=now(),posted_by=p_actor,updated_at=now() where journal_batch_id=p_journal_batch_id;
  return jsonb_build_object('journal_batch_id',p_journal_batch_id,'status','POSTED','duplicate_post',false,'line_count',v_lines,'debit',v_debit,'credit',v_credit);
end;
$$;

revoke all on function finance.require_write_gate() from public;
revoke all on function finance.create_journal_batch(date,text,text,text,text,text,text,text) from public;
revoke all on function finance.add_journal_line(text,integer,text,numeric,numeric,text,text,text) from public;
revoke all on function finance.post_journal_batch(text,text) from public;
grant execute on function finance.require_write_gate() to service_role;
grant execute on function finance.create_journal_batch(date,text,text,text,text,text,text,text) to service_role;
grant execute on function finance.add_journal_line(text,integer,text,numeric,numeric,text,text,text) to service_role;
grant execute on function finance.post_journal_batch(text,text) to service_role;

commit;