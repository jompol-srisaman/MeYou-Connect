begin;

revoke all on ops.scheduled_signals, ops.scheduler_runs from public, anon, authenticated;
revoke execute on function ops.schedule_signal(text,text,timestamptz,text,text,jsonb,text,text,text,text,text,integer) from public, anon, authenticated;
revoke execute on function ops.cancel_schedule(text,text,text) from public, anon, authenticated;
revoke execute on function ops.schedule_followup_due(text,timestamptz,text,text,jsonb,text) from public, anon, authenticated;
revoke execute on function ops.schedule_invoice_due(text,timestamptz,text,jsonb,text) from public, anon, authenticated;
revoke execute on function ops.schedule_notification(text,timestamptz,text,text,jsonb,text) from public, anon, authenticated;
revoke execute on function ops.sync_retry_schedules(timestamptz,integer) from public, anon, authenticated;
revoke execute on function ops.run_due_schedules(timestamptz,integer,text) from public, anon, authenticated;
revoke execute on function ops.scheduler_tick(timestamptz,integer,text) from public, anon, authenticated;
revoke execute on function ops.get_scheduled_event_context(uuid) from public, anon, authenticated;

grant usage on schema ops to service_role;
grant select, insert, update, delete on ops.scheduled_signals, ops.scheduler_runs to service_role;
grant execute on function ops.schedule_signal(text,text,timestamptz,text,text,jsonb,text,text,text,text,text,integer) to service_role;
grant execute on function ops.cancel_schedule(text,text,text) to service_role;
grant execute on function ops.schedule_followup_due(text,timestamptz,text,text,jsonb,text) to service_role;
grant execute on function ops.schedule_invoice_due(text,timestamptz,text,jsonb,text) to service_role;
grant execute on function ops.schedule_notification(text,timestamptz,text,text,jsonb,text) to service_role;
grant execute on function ops.sync_retry_schedules(timestamptz,integer) to service_role;
grant execute on function ops.run_due_schedules(timestamptz,integer,text) to service_role;
grant execute on function ops.scheduler_tick(timestamptz,integer,text) to service_role;
grant execute on function ops.get_scheduled_event_context(uuid) to service_role;

commit;