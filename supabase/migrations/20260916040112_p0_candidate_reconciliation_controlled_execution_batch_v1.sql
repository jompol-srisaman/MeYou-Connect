-- Execute the accepted Candidate reconciliation backlog through the existing Event Kernel + candidate_intake command path.
-- Explicitly prove that no Supabase business Master effect occurs while Google remains the operational SoT.

do $$
declare
  v_before_core integer;
  v_after_core integer;
  v_enq jsonb;
  v_run1 jsonb;
  v_run2 jsonb;
  v_valid integer;
  v_distinct_raw integer;
begin
  if config.setting_is_true('business_master_apply_enabled') then
    raise exception 'business_master_apply_enabled must remain FALSE for Data Hub SoT reconciliation';
  end if;

  select count(*) into v_before_core from core.candidates;

  v_enq:=ops.enqueue_candidate_reconciliation_v1(100);
  if coalesce((v_enq->>'errors')::integer,0) <> 0 then raise exception 'reconciliation enqueue errors: %',v_enq; end if;
  if coalesce((v_enq->>'enqueued')::integer,0) <> 58 then raise exception 'expected 58 newly enqueued reconciliation events, got %',v_enq; end if;

  v_run1:=ops.run_line_candidate_ingestion_tick(now(),100,'P0_RECONCILIATION_CONTROLLED_EXECUTION');
  if coalesce((v_run1->>'errors')::integer,0) <> 0 then raise exception 'candidate reconciliation execution errors: %',v_run1; end if;
  if coalesce((v_run1->>'reconciled_commands_prepared')::integer,0) <> 58 then raise exception 'expected 58 reconciled commands prepared, got %',v_run1; end if;

  -- Immediate rerun is the idempotency proof: no new reconciliation command may be prepared.
  v_run2:=ops.run_line_candidate_ingestion_tick(now(),100,'P0_RECONCILIATION_IDEMPOTENCY_RERUN');
  if coalesce((v_run2->>'reconciled_commands_prepared')::integer,0) <> 0 then raise exception 'idempotency failure: rerun prepared reconciliation commands: %',v_run2; end if;

  select count(*),count(distinct source_raw_input_id)
    into v_valid,v_distinct_raw
  from ops.domain_commands
  where worker_key='candidate_intake'
    and command_type='candidate.upsert_proposal'
    and payload->>'reconciliation_evidence_ref'='github:issue#16:comment:5691426260'
    and validation_status='VALID';

  if v_valid<>58 or v_distinct_raw<>58 then raise exception 'controlled proposal count mismatch valid=% distinct_raw=%',v_valid,v_distinct_raw; end if;

  select count(*) into v_after_core from core.candidates;
  if v_after_core<>v_before_core then raise exception 'protected Master changed unexpectedly before=% after=%',v_before_core,v_after_core; end if;
end $$;
