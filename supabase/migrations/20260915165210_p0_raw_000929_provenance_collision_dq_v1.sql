-- P0 provenance DQ: preserve evidence for MYC-RAW-000929 collision without rewriting Raw/Event history.
-- Root cause: migration 20260914065128 hardcoded MYC-RAW-000929 for CHATGPT before LINE_CAPTURE later allocated the same canonical Raw ID.
do $$
declare
  v_alloc jsonb;
  v_dq_id text;
begin
  if not exists (
    select 1
    from ops.data_quality_issues
    where entity_type='RawInput'
      and entity_id='MYC-RAW-000929'
      and issue_type='RAW_ID_PROVENANCE_COLLISION'
      and status in ('OPEN','IN_REVIEW')
  ) then
    v_alloc := config.allocate_business_id(
      'DQ Issue',
      'P0_READ_GATE_RECONCILIATION',
      jsonb_build_object(
        'entity_type','RawInput',
        'entity_id','MYC-RAW-000929',
        'issue_type','RAW_ID_PROVENANCE_COLLISION',
        'evidence','migration:20260914065128 + config.id_allocation_audit + ops.channel_event_raw_map'
      )
    );
    v_dq_id := v_alloc->>'allocated_id';

    insert into ops.data_quality_issues(
      dq_issue_id,entity_type,entity_id,field_name,issue_type,current_value,incoming_value,
      raw_input_id,severity,status,resolution,created_at,updated_at
    ) values (
      v_dq_id,
      'RawInput',
      'MYC-RAW-000929',
      'source_system/provenance',
      'RAW_ID_PROVENANCE_COLLISION',
      'CHATGPT / CANONICAL_ROUTE_MASTER / migration 20260914065128 hardcoded raw_input_id MYC-RAW-000929',
      'LINE / channel.raw.received / provider_event_id LINE:DATA_BOT:01M2FBDR2ZW6QSBJTPD9FM7DF9 / LINE_CAPTURE allocator audit allocated MYC-RAW-000929 at 2026-09-14T06:59:41.348394Z',
      'MYC-RAW-000929',
      'HIGH',
      'OPEN',
      'Root cause proven: a manual migration inserted canonical Raw ID 929 without reserving/advancing config.allocate_business_id. LINE capture later legitimately allocated 929, contaminating Raw/Event provenance. Do not silently rewrite either side; require explicit provenance repair/re-key plan preserving both evidence chains.',
      now(),now()
    );
  end if;
end $$;
