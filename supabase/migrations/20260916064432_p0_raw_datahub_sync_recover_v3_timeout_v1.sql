-- Recover only runtime leases left open by the timed-out v3 acceptance run.
update ops.raw_datahub_sync_ledger
set sync_status='RETRY',next_retry_at=now(),in_flight_at=null,last_error_class=coalesce(last_error_class,'HTTP_CLIENT_CANCELLED'),last_error_message=coalesce(last_error_message,'Recovered v3 timeout'),updated_at=now()
where sync_status='IN_FLIGHT';
