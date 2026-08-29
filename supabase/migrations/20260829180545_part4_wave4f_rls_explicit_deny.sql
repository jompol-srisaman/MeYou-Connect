begin;

drop policy if exists migration_entity_map_deny_clients on ops.migration_entity_map;
create policy migration_entity_map_deny_clients on ops.migration_entity_map for all to anon,authenticated using(false) with check(false);

drop policy if exists shadow_import_sessions_deny_clients on ops.shadow_import_sessions;
create policy shadow_import_sessions_deny_clients on ops.shadow_import_sessions for all to anon,authenticated using(false) with check(false);

drop policy if exists shadow_import_rows_deny_clients on ops.shadow_import_rows;
create policy shadow_import_rows_deny_clients on ops.shadow_import_rows for all to anon,authenticated using(false) with check(false);

drop policy if exists reconciliation_runs_deny_clients on ops.reconciliation_runs;
create policy reconciliation_runs_deny_clients on ops.reconciliation_runs for all to anon,authenticated using(false) with check(false);

drop policy if exists reconciliation_results_deny_clients on ops.reconciliation_results;
create policy reconciliation_results_deny_clients on ops.reconciliation_results for all to anon,authenticated using(false) with check(false);

commit;