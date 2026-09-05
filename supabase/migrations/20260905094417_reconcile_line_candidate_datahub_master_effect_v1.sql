-- MYC-DQ-000011: reconcile successful Google Sheets/Drive operational Master Effects back to Supabase control/audit state.
-- Important: does NOT enable Postgres business-master apply and leaves candidate domain commands READY.

update config.id_allocators
set next_number=17,digits=6,last_allocated_id='MYC-C-000016',last_allocated_at=now(),last_allocation_owner='DATAHUB_MASTER_EFFECT_MYC_DQ_000011',source_ref='Live DataHub 98_System_Config read-back 2026-09-05',source_snapshot_at=now(),updated_at=now()
where entity_key='Candidate' and prefix='MYC-C-';

update config.id_allocators
set next_number=13,digits=6,last_allocated_id='MYC-EV-000012',last_allocated_at=now(),last_allocation_owner='DATAHUB_MASTER_EFFECT_MYC_DQ_000011',source_ref='Live DataHub 98_System_Config read-back 2026-09-05',source_snapshot_at=now(),updated_at=now()
where entity_key='Evidence' and prefix='MYC-EV-';

update config.id_allocators
set next_number=2,digits=6,last_allocated_id='MYC-AI-000001',last_allocated_at=now(),last_allocation_owner='DATAHUB_MASTER_EFFECT_MYC_DQ_000011',source_ref='Live DataHub 98_System_Config read-back 2026-09-05',source_snapshot_at=now(),updated_at=now()
where entity_key='AI Run' and prefix='MYC-AI-';

update config.id_allocators
set next_number=18,digits=6,last_allocated_id='MYC-FILE-000017',last_allocated_at=now(),last_allocation_owner='DATAHUB_MASTER_EFFECT_MYC_DQ_000011',source_ref='Live DataHub 98_System_Config read-back 2026-09-05',source_snapshot_at=now(),updated_at=now()
where entity_key='File Registry' and prefix='MYC-FILE-';

update config.id_allocators
set next_number=13,digits=6,last_allocated_id='MYC-DQ-000012',last_allocated_at=now(),last_allocation_owner='DATAHUB_MASTER_EFFECT_MYC_DQ_000011',source_ref='Live DataHub 98_System_Config read-back 2026-09-05',source_snapshot_at=now(),updated_at=now()
where entity_key='DQ Issue' and prefix='MYC-DQ-';

with m(raw_input_id,candidate_id) as (
  values ('MYC-RAW-000018','MYC-C-000014'),('MYC-RAW-000019','MYC-C-000015'),('MYC-RAW-000020','MYC-C-000016')
)
update ops.raw_inputs r
set entity_type='Candidate',entity_id=m.candidate_id,
    metadata=coalesce(r.metadata,'{}'::jsonb)||jsonb_build_object('operational_master_effect',jsonb_build_object('provider','GOOGLE_SHEETS_DRIVE','sheet','01_Candidate','candidate_id',m.candidate_id,'verified_at',now(),'source_dq','MYC-DQ-000011')),
    updated_at=now()
from m where r.raw_input_id=m.raw_input_id;

with m(raw_input_id,candidate_id) as (
  values ('MYC-RAW-000018','MYC-C-000014'),('MYC-RAW-000019','MYC-C-000015'),('MYC-RAW-000020','MYC-C-000016')
)
update ops.domain_commands dc
set target_entity_type='Candidate',target_entity_id=m.candidate_id,
    payload=dc.payload||jsonb_build_object('operational_master_effect',jsonb_build_object('provider','GOOGLE_SHEETS_DRIVE','sheet','01_Candidate','candidate_id',m.candidate_id,'verified_at',now(),'source_dq','MYC-DQ-000011')),
    updated_at=now()
from m where dc.source_raw_input_id=m.raw_input_id and dc.worker_key='candidate_intake';

select ops.register_effect(e.event_pk,'datahub_candidate_master_effect','datahub_candidate_master_effect|MYC-RAW-000018','Candidate','MYC-C-000014','DataHub:01_Candidate:MYC-C-000014')
from ops.events e where e.raw_input_id='MYC-RAW-000018' and e.event_type='candidate.lead.received';

select ops.register_effect(e.event_pk,'datahub_candidate_master_effect','datahub_candidate_master_effect|MYC-RAW-000019','Candidate','MYC-C-000015','DataHub:01_Candidate:MYC-C-000015')
from ops.events e where e.raw_input_id='MYC-RAW-000019' and e.event_type='candidate.lead.received';

select ops.register_effect(e.event_pk,'datahub_candidate_master_effect','datahub_candidate_master_effect|MYC-RAW-000020','Candidate','MYC-C-000016','DataHub:01_Candidate:MYC-C-000016')
from ops.events e where e.raw_input_id='MYC-RAW-000020' and e.event_type='candidate.lead.received';

-- Idempotency/E2E exercise through the patched raw completion hook and existing scheduler.
select ops.complete_raw_capture_event(e.event_pk)
from ops.events e where e.raw_input_id='MYC-RAW-000018' and e.event_type='channel.raw.received';

select ops.scheduler_tick(now(),100,'MYC_DQ_000011_E2E');
