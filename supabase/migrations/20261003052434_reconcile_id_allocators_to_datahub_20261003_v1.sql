-- Reconcile Supabase shadow ID allocators upward to authoritative Google Data Hub 98_System_Config.
with src(entity_key,next_number,digits,last_allocated_id) as (
 values
 ('Candidate',53::bigint,6,'MYC-C-000052'),('Job',18,6,'MYC-J-000017'),
 ('Client',4,4,'MYC-B2B-0003'),('Partner',10,4,'MYC-P-0009'),
 ('Placement',1,6,null),('Transport',48,4,'MYC-TR-0047'),
 ('Evidence',37,6,'MYC-EV-000036'),('Consent',1,6,null),
 ('Content',3,6,'MYC-CT-000002'),('Activity',32,6,'MYC-ACT-000031'),
 ('AI Run',3,6,'MYC-AI-000002'),('Risk',37,3,'MYC-RSK-036'),
 ('Raw Input',4121,6,'MYC-RAW-004120'),('File Registry',57,6,'MYC-FILE-000056'),
 ('DQ Issue',31,6,'MYC-DQ-000030'),('Bank Txn',18,6,'MYC-BANK-000017')
)
update config.id_allocators a
set next_number=greatest(a.next_number,s.next_number),
    digits=s.digits,
    last_allocated_id=case when a.next_number<s.next_number then s.last_allocated_id else a.last_allocated_id end,
    last_allocation_owner=case when a.next_number<s.next_number then 'DATAHUB_RECONCILIATION_20261003' else a.last_allocation_owner end,
    source_ref='MEYOU_CONNECT_MVP_DATA_HUB_V1/98_System_Config live reconciliation 2026-10-03',
    source_snapshot_at=now(),updated_at=now(),conflict_status='NONE'
from src s
where a.entity_key=s.entity_key and a.next_number<=s.next_number;
