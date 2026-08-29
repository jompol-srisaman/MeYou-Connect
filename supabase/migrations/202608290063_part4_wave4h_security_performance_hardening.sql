create index if not exists part4_closeout_results_check_key_idx on ops.part4_closeout_results(check_key);

drop policy if exists part4_output_catalog_deny_client on ops.part4_output_catalog;
create policy part4_output_catalog_deny_client on ops.part4_output_catalog for all to anon,authenticated using (false) with check (false);

drop policy if exists part4_evidence_records_deny_client on ops.part4_evidence_records;
create policy part4_evidence_records_deny_client on ops.part4_evidence_records for all to anon,authenticated using (false) with check (false);

drop policy if exists part4_closeout_check_catalog_deny_client on ops.part4_closeout_check_catalog;
create policy part4_closeout_check_catalog_deny_client on ops.part4_closeout_check_catalog for all to anon,authenticated using (false) with check (false);

drop policy if exists part4_closeout_runs_deny_client on ops.part4_closeout_runs;
create policy part4_closeout_runs_deny_client on ops.part4_closeout_runs for all to anon,authenticated using (false) with check (false);

drop policy if exists part4_closeout_results_deny_client on ops.part4_closeout_results;
create policy part4_closeout_results_deny_client on ops.part4_closeout_results for all to anon,authenticated using (false) with check (false);
