create index if not exists approvals_event_pk_idx on ops.approvals(event_pk);
create index if not exists data_quality_issues_raw_input_id_idx on ops.data_quality_issues(raw_input_id);
create index if not exists event_effects_event_pk_idx on ops.event_effects(event_pk);
create index if not exists events_raw_input_id_idx on ops.events(raw_input_id);
