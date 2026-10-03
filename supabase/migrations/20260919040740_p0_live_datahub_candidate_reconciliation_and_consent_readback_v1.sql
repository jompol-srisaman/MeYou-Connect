-- P0 live Data Hub reconciliation + authoritative empty-consent read-back.
-- Existing Raw/Event/Command architecture only; no protected business Master write.
do $$
declare v_existing int; v_new int;
begin
  select count(*) into v_existing from ops.candidate_reconciliation_workbench_v
  where master_lookup_readiness='NOT_READY'
    and raw_input_id in ('MYC-RAW-002056','MYC-RAW-002058','MYC-RAW-002059','MYC-RAW-002068','MYC-RAW-002086','MYC-RAW-002087','MYC-RAW-002099','MYC-RAW-002164','MYC-RAW-002166','MYC-RAW-002198','MYC-RAW-002199','MYC-RAW-002254','MYC-RAW-002266','MYC-RAW-002268');
  if v_existing<>14 then raise exception 'existing-master reconciliation drift: expected 14 got %',v_existing; end if;
  select count(*) into v_new from ops.candidate_reconciliation_workbench_v
  where master_lookup_readiness='NOT_READY'
    and raw_input_id in ('MYC-RAW-001450','MYC-RAW-001453','MYC-RAW-001533','MYC-RAW-001534','MYC-RAW-001546','MYC-RAW-001549','MYC-RAW-001578','MYC-RAW-001579','MYC-RAW-001678','MYC-RAW-001680','MYC-RAW-001684','MYC-RAW-001730','MYC-RAW-001790','MYC-RAW-001791','MYC-RAW-001792','MYC-RAW-001825','MYC-RAW-001858','MYC-RAW-001866','MYC-RAW-001867','MYC-RAW-001937','MYC-RAW-001939','MYC-RAW-001970','MYC-RAW-002015','MYC-RAW-002016','MYC-RAW-002018');
  if v_new<>25 then raise exception 'new-candidate reconciliation drift: expected 25 got %',v_new; end if;
end $$;

with m(raw_input_id,candidate_id) as (values
 ('MYC-RAW-002056','MYC-C-000028'),('MYC-RAW-002058','MYC-C-000029'),
 ('MYC-RAW-002059','MYC-C-000030'),('MYC-RAW-002068','MYC-C-000030'),
 ('MYC-RAW-002086','MYC-C-000017'),('MYC-RAW-002087','MYC-C-000018'),
 ('MYC-RAW-002099','MYC-C-000019'),('MYC-RAW-002164','MYC-C-000021'),
 ('MYC-RAW-002166','MYC-C-000022'),('MYC-RAW-002198','MYC-C-000023'),
 ('MYC-RAW-002199','MYC-C-000024'),('MYC-RAW-002254','MYC-C-000025'),
 ('MYC-RAW-002266','MYC-C-000026'),('MYC-RAW-002268','MYC-C-000027')
)
update ops.raw_inputs r
set metadata=coalesce(r.metadata,'{}'::jsonb)||jsonb_build_object(
 'candidate_reconciliation',jsonb_build_object(
  'decision','ALREADY_IN_MASTER_LINK_MISSING',
  'reason','LIVE_DATAHUB_01_CANDIDATE_EXACT_NAME_PHONE_MATCH_WITH_RAW_DOB_EVIDENCE',
  'candidate_master_ref',m.candidate_id,
  'evidence_ref','GOOGLE_DATA_HUB:01_Candidate:2026-09-19T04:00Z:30_ROWS',
  'accepted_at',now(),'accepted_by','DATA_AI_SYSTEM_MANAGER_V2',
  'master_authority','GOOGLE_SHEETS_DRIVE','master_effect_required',false),
 'operational_master_effect',jsonb_build_object(
  'sheet','01_Candidate','provider','GOOGLE_SHEETS_DRIVE','candidate_id',m.candidate_id,
  'verified_at',now(),'source_evidence','GOOGLE_DATA_HUB:01_Candidate:2026-09-19T04:00Z:30_ROWS')
),updated_at=now()
from m where r.raw_input_id=m.raw_input_id
and r.metadata#>>'{operational_master_effect,candidate_id}' is null;

update ops.raw_inputs
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
 'candidate_reconciliation',jsonb_build_object(
  'decision','NEW_CANDIDATE_NEEDS_PROMOTION',
  'reason','LIVE_DATAHUB_01_CANDIDATE_NO_MATCH_NAME_PHONE_DOB_EVIDENCE',
  'evidence_ref','GOOGLE_DATA_HUB:01_Candidate:2026-09-19T04:00Z:30_ROWS',
  'accepted_at',now(),'accepted_by','DATA_AI_SYSTEM_MANAGER_V2',
  'master_authority','GOOGLE_SHEETS_DRIVE','master_effect_required',true)
),updated_at=now()
where raw_input_id in (
 'MYC-RAW-001450','MYC-RAW-001453','MYC-RAW-001533','MYC-RAW-001534','MYC-RAW-001546',
 'MYC-RAW-001549','MYC-RAW-001578','MYC-RAW-001579','MYC-RAW-001678','MYC-RAW-001680',
 'MYC-RAW-001684','MYC-RAW-001730','MYC-RAW-001790','MYC-RAW-001791','MYC-RAW-001792',
 'MYC-RAW-001825','MYC-RAW-001858','MYC-RAW-001866','MYC-RAW-001867','MYC-RAW-001937',
 'MYC-RAW-001939','MYC-RAW-001970','MYC-RAW-002015','MYC-RAW-002016','MYC-RAW-002018')
and metadata#>>'{candidate_reconciliation,decision}' is null;

update ops.raw_inputs
set metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
 'candidate_reconciliation',jsonb_build_object(
  'decision','NEEDS_DQ',
  'reason',case raw_input_id when 'MYC-RAW-001594' then 'DOB_03_05_69_CONFLICTS_WITH_STATED_AGE_35' when 'MYC-RAW-001907' then 'PARSED_NAME_CONTAINS_DOB_TOKEN_REQUIRES_NAME_NORMALIZATION' end,
  'evidence_ref','GOOGLE_DATA_HUB:01_Candidate:2026-09-19T04:00Z:30_ROWS',
  'accepted_at',now(),'accepted_by','DATA_AI_SYSTEM_MANAGER_V2',
  'master_authority','GOOGLE_SHEETS_DRIVE','master_effect_required',false)
),updated_at=now()
where raw_input_id in ('MYC-RAW-001594','MYC-RAW-001907')
and metadata#>>'{candidate_reconciliation,decision}' is null;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at)
values('consent_datahub_readback_v1',
 jsonb_build_object('readback_verified',true,'row_count',0,'observed_at',now(),'spreadsheet_id','1o52Vpri7toZDviODQ12tpOoLgCs7Z5cYMmUZMc0Jeoc','sheet','14_Consent_PDPA'),
 'Authoritative Google Data Hub consent readback evidence. Empty authoritative sheet is a successful read, not consent permission.',
 'MEYOU_CONNECT_MVP_DATA_HUB_V1/14_Consent_PDPA',now())
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;

create or replace view ops.consent_readiness_v with(security_invoker=true) as
with rb as(select setting_value,updated_at from config.system_settings where setting_key='consent_datahub_readback_v1'),
tech as(select count(*)::bigint n,max(created_at) latest_at from privacy.consents)
select 'CONSENT_PDPA'::text canonical_id,'GOOGLE_SHEETS_DRIVE'::text source_authority,
 'MEYOU_CONNECT_MVP_DATA_HUB_V1/14_Consent_PDPA'::text source_ref,
 tech.n supabase_registry_rows,
 coalesce((rb.setting_value->>'readback_verified')::boolean,false) datahub_readback_verified,
 false auto_submit_allowed,
 case when coalesce((rb.setting_value->>'readback_verified')::boolean,false) then 'READY' else 'NOT_READY' end::text readiness,
 case when coalesce((rb.setting_value->>'readback_verified')::boolean,false) and coalesce((rb.setting_value->>'row_count')::bigint,0)=0 then 'AUTHORITATIVE_SOURCE_READ_VERIFIED_EMPTY'
      when coalesce((rb.setting_value->>'readback_verified')::boolean,false) then 'AUTHORITATIVE_SOURCE_READ_VERIFIED_CONSENT_REVIEW_REQUIRED'
      else 'DATA_HUB_CONSENT_READBACK_REQUIRED' end::text reason_code,
 tech.latest_at supabase_latest_consent_at,rb.updated_at datahub_readback_verified_at,
 coalesce((rb.setting_value->>'row_count')::bigint,0) authoritative_row_count
from tech left join rb on true;

revoke all on ops.consent_readiness_v from public,anon,authenticated;
grant select on ops.consent_readiness_v to service_role;

do $$ declare v jsonb; begin select ops.enqueue_candidate_reconciliation_v1(500) into v; end $$;
