
revoke all on function ops.raw_datahub_sync_mark_success_batch(jsonb,timestamptz) from public,anon,authenticated;
grant execute on function ops.raw_datahub_sync_mark_success_batch(jsonb,timestamptz) to service_role;
