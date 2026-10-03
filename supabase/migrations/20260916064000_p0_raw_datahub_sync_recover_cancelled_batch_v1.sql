-- Operational recovery after an interrupted acceptance batch; no business Master writes.
update ops.raw_datahub_sync_ledger
set sync_status='RETRY',next_retry_at=now(),in_flight_at=null,last_error_class='HTTP_CLIENT_CANCELLED',last_error_message='Recovered interrupted Raw→Data Hub acceptance batch',updated_at=now()
where sync_status='IN_FLIGHT';
