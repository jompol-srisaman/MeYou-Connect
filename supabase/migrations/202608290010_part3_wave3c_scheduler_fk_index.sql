begin;
create index if not exists scheduled_signals_event_type_idx on ops.scheduled_signals(event_type);
commit;