-- Final set-based success RPC used by Raw→Data Hub v4.

revoke all on function ops.raw_datahub_sync_mark_success_batch(jsonb,timestamptz) from public,anon,authenticated;
grant execute on function ops.raw_datahub_sync_mark_success_batch(jsonb,timestamptz) to service_role;
