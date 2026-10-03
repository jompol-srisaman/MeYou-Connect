-- Incremental existing-Master linkage pass 2.
with m(raw_input_id,candidate_id) as (values
 ('MYC-RAW-002066','MYC-C-000028'),('MYC-RAW-002067','MYC-C-000029'),
 ('MYC-RAW-002088','MYC-C-000017'),('MYC-RAW-002089','MYC-C-000018'),
 ('MYC-RAW-002100','MYC-C-000019'),('MYC-RAW-002165','MYC-C-000021'),
 ('MYC-RAW-002167','MYC-C-000022'),('MYC-RAW-002202','MYC-C-000023'),
 ('MYC-RAW-002203','MYC-C-000024'),('MYC-RAW-002267','MYC-C-000026'),
 ('MYC-RAW-002269','MYC-C-000027')
)
update ops.raw_inputs r set metadata=coalesce(r.metadata,'{}'::jsonb)||jsonb_build_object(
 'candidate_reconciliation',jsonb_build_object('decision','ALREADY_IN_MASTER_LINK_MISSING','reason','LIVE_DATAHUB_01_CANDIDATE_EXACT_NAME_PHONE_MATCH_INCREMENTAL_DUPLICATE_REPRESENTATIVE','candidate_master_ref',m.candidate_id,'evidence_ref','GOOGLE_DATA_HUB:01_Candidate:2026-09-19T04:00Z:30_ROWS','accepted_at',now(),'accepted_by','DATA_AI_SYSTEM_MANAGER_V2','master_authority','GOOGLE_SHEETS_DRIVE','master_effect_required',false),
 'operational_master_effect',jsonb_build_object('sheet','01_Candidate','provider','GOOGLE_SHEETS_DRIVE','candidate_id',m.candidate_id,'verified_at',now(),'source_evidence','GOOGLE_DATA_HUB:01_Candidate:2026-09-19T04:00Z:30_ROWS')
),updated_at=now() from m where r.raw_input_id=m.raw_input_id and r.metadata#>>'{operational_master_effect,candidate_id}' is null;
