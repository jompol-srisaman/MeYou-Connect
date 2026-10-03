
revoke all on function ops.raw_datahub_sync_release_inflight(text,timestamptz) from public,anon,authenticated;
grant execute on function ops.raw_datahub_sync_release_inflight(text,timestamptz) to service_role;
