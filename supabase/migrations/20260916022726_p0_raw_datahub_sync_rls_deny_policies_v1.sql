drop policy if exists raw_datahub_sync_ledger_deny_anon on ops.raw_datahub_sync_ledger;
create policy raw_datahub_sync_ledger_deny_anon on ops.raw_datahub_sync_ledger for all to anon using(false) with check(false);
drop policy if exists raw_datahub_sync_ledger_deny_authenticated on ops.raw_datahub_sync_ledger;
create policy raw_datahub_sync_ledger_deny_authenticated on ops.raw_datahub_sync_ledger for all to authenticated using(false) with check(false);
drop policy if exists raw_datahub_sync_watermarks_deny_anon on ops.raw_datahub_sync_watermarks;
create policy raw_datahub_sync_watermarks_deny_anon on ops.raw_datahub_sync_watermarks for all to anon using(false) with check(false);
drop policy if exists raw_datahub_sync_watermarks_deny_authenticated on ops.raw_datahub_sync_watermarks;
create policy raw_datahub_sync_watermarks_deny_authenticated on ops.raw_datahub_sync_watermarks for all to authenticated using(false) with check(false);
