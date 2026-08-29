do $$
declare v_count bigint;
begin
  select
    (select count(*) from core.candidates)+
    (select count(*) from core.jobs)+
    (select count(*) from core.clients)+
    (select count(*) from core.partners)+
    (select count(*) from core.placements)+
    (select count(*) from core.transport_providers)+
    (select count(*) from docs.files)+
    (select count(*) from docs.evidence)+
    (select count(*) from privacy.consents)+
    (select count(*) from finance.journal_batches)+
    (select count(*) from finance.accounts_receivable)+
    (select count(*) from finance.accounts_payable)+
    (select count(*) from finance.bank_transactions)+
    (select count(*) from finance.tax_documents)+
    (select count(*) from ops.raw_inputs)+
    (select count(*) from ops.data_quality_issues)
  into v_count;
  if v_count<>0 then
    raise exception 'canonical ID namespace realignment requires zero persisted business rows; found %',v_count;
  end if;
end $$;

insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
('canonical_business_id_namespace','"MYC"'::jsonb,'Canonical stable business ID namespace. Never infer this from historical migrations.','Founder Master V1 + Control Index V3.6 + live 98_System_Config verified 2026-08-30'),
('canonical_business_id_source','"FOUNDER_MASTER_AND_98_SYSTEM_CONFIG"'::jsonb,'Authoritative source for current stable business ID prefixes.','Founder Master V1 + live 98_System_Config verified 2026-08-30')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

update config.id_allocators a
set prefix=v.prefix,
    next_number=v.next_number,
    digits=v.digits,
    active=true,
    allocation_enabled=true,
    conflict_status='NONE',
    source_ref='Founder Master V1 + live DataHub:98_System_Config verified 2026-08-30',
    rule_notes=v.rule_notes,
    last_allocated_id=v.last_allocated_id,
    source_snapshot_at=now(),
    updated_at=now()
from (values
  ('Candidate','MYC-C-',1,6,'Stable Candidate ID Framework; MeYou Connect brand migration preserves MYC-* business IDs',null::text),
  ('Job','MYC-J-',1,6,'Data Hub ID format',null::text),
  ('Client','MYC-B2B-',1,4,'Founder Master ID Framework',null::text),
  ('Partner','MYC-P-',3,4,'Founder Master ID Framework','MYC-P-0002'),
  ('Placement','MYC-PL-',1,6,'Founder Master ID Framework',null::text),
  ('Transport','MYC-TR-',1,4,'System implementation ID',null::text),
  ('Evidence','MYC-EV-',1,6,'System implementation ID',null::text),
  ('Consent','MYC-CN-',1,6,'System implementation ID',null::text),
  ('Content','MYC-CT-',3,6,'System implementation ID','MYC-CT-000002'),
  ('Activity','MYC-ACT-',1,6,'System implementation ID',null::text),
  ('AI Run','MYC-AI-',1,6,'System implementation ID',null::text),
  ('Risk','MYC-RSK-',37,3,'Architecture risk register currently reserves/uses through MYC-RSK-036','MYC-RSK-036'),
  ('Raw Input','MYC-RAW-',3,6,'Raw input provenance ID','MYC-RAW-000002'),
  ('File Registry','MYC-FILE-',3,6,'File registry ID','MYC-FILE-000002'),
  ('DQ Issue','MYC-DQ-',1,6,'Data quality issue ID',null::text),
  ('Journal Batch','MYC-JRN-',1,6,'Accounting journal batch',null::text),
  ('AR','MYC-AR-',1,6,'Accounts receivable record',null::text),
  ('AP','MYC-AP-',1,6,'Accounts payable record',null::text),
  ('Bank Txn','MYC-BANK-',1,6,'Bank/cash transaction',null::text),
  ('Tax Doc','MYC-TAX-',1,6,'Accounting tax/document register',null::text)
) as v(entity_key,prefix,next_number,digits,rule_notes,last_allocated_id)
where a.entity_key=v.entity_key;

alter table core.candidates drop constraint if exists candidates_candidate_id_check;
alter table core.candidates add constraint candidates_candidate_id_check check(candidate_id ~ '^MYC-C-[0-9]{6}$');
alter table core.jobs drop constraint if exists jobs_job_id_check;
alter table core.jobs add constraint jobs_job_id_check check(job_id ~ '^MYC-J-[0-9]{6}$');
alter table core.clients drop constraint if exists clients_client_id_check;
alter table core.clients add constraint clients_client_id_check check(client_id ~ '^MYC-B2B-[0-9]{4}$');
alter table core.partners drop constraint if exists partners_partner_id_check;
alter table core.partners add constraint partners_partner_id_check check(partner_id ~ '^MYC-P-[0-9]{4}$');
alter table core.placements drop constraint if exists placements_placement_id_check;
alter table core.placements add constraint placements_placement_id_check check(placement_id ~ '^MYC-PL-[0-9]{6}$');
alter table core.transport_providers drop constraint if exists transport_providers_transport_id_check;
alter table core.transport_providers add constraint transport_providers_transport_id_check check(transport_id ~ '^MYC-TR-[0-9]{4}$');

alter table docs.files drop constraint if exists files_file_id_check;
alter table docs.files add constraint files_file_id_check check(file_id ~ '^MYC-FILE-[0-9]{6}$');
alter table docs.evidence drop constraint if exists evidence_evidence_id_check;
alter table docs.evidence add constraint evidence_evidence_id_check check(evidence_id ~ '^MYC-EV-[0-9]{6}$');

alter table privacy.consents drop constraint if exists consents_consent_id_check;
alter table privacy.consents add constraint consents_consent_id_check check(consent_id ~ '^MYC-CN-[0-9]{6}$');

alter table finance.journal_batches drop constraint if exists journal_batches_journal_batch_id_check;
alter table finance.journal_batches add constraint journal_batches_journal_batch_id_check check(journal_batch_id ~ '^MYC-JRN-[0-9]{6}$');
alter table finance.accounts_receivable drop constraint if exists accounts_receivable_ar_id_check;
alter table finance.accounts_receivable add constraint accounts_receivable_ar_id_check check(ar_id ~ '^MYC-AR-[0-9]{6}$');
alter table finance.accounts_payable drop constraint if exists accounts_payable_ap_id_check;
alter table finance.accounts_payable add constraint accounts_payable_ap_id_check check(ap_id ~ '^MYC-AP-[0-9]{6}$');
alter table finance.bank_transactions drop constraint if exists bank_transactions_bank_txn_id_check;
alter table finance.bank_transactions add constraint bank_transactions_bank_txn_id_check check(bank_txn_id ~ '^MYC-BANK-[0-9]{6}$');
alter table finance.tax_documents drop constraint if exists tax_documents_tax_doc_id_check;
alter table finance.tax_documents add constraint tax_documents_tax_doc_id_check check(tax_doc_id ~ '^MYC-TAX-[0-9]{6}$');

alter table ops.raw_inputs drop constraint if exists raw_inputs_raw_input_id_check;
alter table ops.raw_inputs add constraint raw_inputs_raw_input_id_check check(raw_input_id ~ '^MYC-RAW-[0-9]{6}$');
alter table ops.data_quality_issues drop constraint if exists data_quality_issues_dq_issue_id_check;
alter table ops.data_quality_issues add constraint data_quality_issues_dq_issue_id_check check(dq_issue_id ~ '^MYC-DQ-[0-9]{6}$');

update ops.migration_entity_map set id_regex='^MYC-C-[0-9]{6}$',updated_at=now() where entity_key='Candidate';
update ops.migration_entity_map set id_regex='^MYC-J-[0-9]{6}$',updated_at=now() where entity_key='Job';
update ops.migration_entity_map set id_regex='^MYC-B2B-[0-9]{4}$',updated_at=now() where entity_key='Client';
update ops.migration_entity_map set id_regex='^MYC-P-[0-9]{4}$',updated_at=now() where entity_key='Partner';
update ops.migration_entity_map set id_regex='^MYC-PL-[0-9]{6}$',updated_at=now() where entity_key='Placement';
update ops.migration_entity_map set id_regex='^MYC-TR-[0-9]{4}$',updated_at=now() where entity_key='Transport';
update ops.migration_entity_map set id_regex='^MYC-EV-[0-9]{6}$',updated_at=now() where entity_key='Evidence';
update ops.migration_entity_map set id_regex='^MYC-CN-[0-9]{6}$',updated_at=now() where entity_key='Consent';
update ops.migration_entity_map set id_regex='^MYC-RAW-[0-9]{6}$',updated_at=now() where entity_key='Raw Input';
update ops.migration_entity_map set id_regex='^MYC-FILE-[0-9]{6}$',updated_at=now() where entity_key='File Registry';
update ops.migration_entity_map set id_regex='^MYC-DQ-[0-9]{6}$',updated_at=now() where entity_key='Data_Quality';
update ops.migration_entity_map set id_regex='^MYC-RSK-[0-9]{3}$',updated_at=now() where entity_key='Risk';
