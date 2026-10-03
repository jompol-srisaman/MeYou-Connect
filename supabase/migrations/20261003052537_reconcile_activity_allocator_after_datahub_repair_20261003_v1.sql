update config.id_allocators
set next_number=greatest(next_number,33),
    digits=6,
    last_allocated_id=case when next_number<33 then 'MYC-ACT-000032' else last_allocated_id end,
    last_allocation_owner=case when next_number<33 then 'DATAHUB_REPAIR_AUDIT_20261003' else last_allocation_owner end,
    source_ref='MEYOU_CONNECT_MVP_DATA_HUB_V1/16_Activity_Log + 98_System_Config live reconciliation 2026-10-03',
    source_snapshot_at=now(),updated_at=now(),conflict_status='NONE'
where entity_key='Activity';
