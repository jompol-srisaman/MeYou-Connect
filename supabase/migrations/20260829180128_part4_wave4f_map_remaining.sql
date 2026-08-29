begin;
insert into ops.migration_entity_map(entity_key,source_sheet,target_schema,target_table,source_pk_header,target_pk_column,source_of_truth,migration_priority,sensitivity,id_regex,compare_fields,target_ready,notes)
values
('Dorm','06_หอ_Dorm','core','dorms','Dorm ID','dorm_id','Data Hub',null,'PUBLIC',null,array[]::text[],true,'Target exists; detailed compare mapping deferred until real rows exist.'),
('FollowUp','07_FollowUp','core','followups','FollowUp ID','followup_id','Data Hub',null,'INTERNAL',null,array[]::text[],true,'Target exists; detailed compare mapping deferred until real rows exist.'),
('Transport','12_Transport','core','transport_providers','Transport ID','transport_id','Data Hub',null,'PUBLIC','^WC-TR-[0-9]{4}$',array[]::text[],true,'Target exists; detailed compare mapping deferred until real rows exist.'),
('Content','15_Content_Tracker','core','content_items','Content ID','content_id','Data Hub',null,'PUBLIC',null,array[]::text[],false,'Target table not implemented yet.'),
('Activity','16_Activity_Log','ops','activities','Activity ID','activity_id','Data Hub',null,'INTERNAL',null,array[]::text[],false,'Target table not implemented yet.'),
('AI_Automation','17_AI_Automation_Log','ops','ai_runs','Run ID','run_id','Data Hub',null,'INTERNAL',null,array[]::text[],false,'Target table not implemented yet.'),
('Risk','18_Risk_Register','core','risks','Risk ID','risk_id','Data Hub',null,'INTERNAL','^WC-RSK-[0-9]{3}$',array[]::text[],false,'Target table not implemented yet.')
on conflict(entity_key) do update set source_sheet=excluded.source_sheet,target_schema=excluded.target_schema,target_table=excluded.target_table,source_pk_header=excluded.source_pk_header,target_pk_column=excluded.target_pk_column,source_of_truth=excluded.source_of_truth,migration_priority=excluded.migration_priority,sensitivity=excluded.sensitivity,id_regex=excluded.id_regex,compare_fields=excluded.compare_fields,target_ready=excluded.target_ready,notes=excluded.notes,updated_at=now();
commit;