begin;

do $$
declare v config.id_allocators;
begin
  select * into v from config.id_allocators where entity_key='Candidate' for update;
  if found then
    if v.last_allocated_id is null and v.next_number=1 then
      update config.id_allocators
      set prefix='WC-C-',
          allocation_enabled=true,
          conflict_status='NONE',
          source_ref='Live 98_System_Config verified 2026-08-30',
          rule_notes='Stable Candidate ID Framework; MeYou Connect brand migration does not alter WC-* business IDs',
          source_snapshot_at=now(),
          updated_at=now()
      where entity_key='Candidate';
    elsif v.prefix<>'WC-C-' then
      raise exception 'Candidate allocator has allocations/state that require manual reconciliation before prefix sync';
    end if;
  end if;
end $$;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at)
values
 ('finance_write_enabled','false'::jsonb,'Persistent Finance schema writes remain disabled during TEST foundation.','Part4E / Accounting Ledger V1',now()),
 ('finance_posting_enabled','false'::jsonb,'Journal posting remains disabled except inside controlled TEST acceptance transactions.','Part4E / Accounting Ledger V1',now()),
 ('finance_collection_state_enabled','false'::jsonb,'Revenue transition to COLLECTED remains disabled except controlled TEST acceptance.','Founder Master + Part4E',now()),
 ('finance_commission_state_enabled','false'::jsonb,'Commission PAYABLE/PAID transitions remain disabled except controlled TEST acceptance.','Founder Master + Part4E',now()),
 ('finance_external_payment_execution_enabled','false'::jsonb,'No function in Part4E may initiate a real bank/payment transfer.','AI Permission Matrix / Part4E',now()),
 ('finance_tax_filing_enabled','false'::jsonb,'Tax document register is preparation/review only; no tax filing is enabled.','Accounting Ledger V1',now()),
 ('finance_unallocated_id_entities','["Revenue","Expense","Commission"]'::jsonb,'No live allocator prefix is defined in 98_System_Config for these business IDs; preserve source IDs and do not invent prefixes.','Live 98_System_Config verified 2026-08-30',now())
on conflict(setting_key) do update set
 setting_value=excluded.setting_value,
 description=excluded.description,
 source_ref=excluded.source_ref,
 updated_at=excluded.updated_at;

commit;