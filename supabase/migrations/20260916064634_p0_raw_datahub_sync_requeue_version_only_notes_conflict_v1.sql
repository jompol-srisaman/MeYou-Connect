-- Requeue rows whose only conflict was the runtime sync_contract version label in Notes.
update ops.raw_datahub_sync_ledger
set sync_status='RETRY',next_retry_at=now(),in_flight_at=null,last_error_class=null,last_error_message=null,updated_at=now()
where sync_status='DQ'
  and coalesce(last_error_message,'') ilike '%TARGET_CONFLICT%notes%';
