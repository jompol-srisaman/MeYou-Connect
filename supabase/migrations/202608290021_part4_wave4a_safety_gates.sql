begin;
create table if not exists config.system_settings (
  setting_key text primary key,
  setting_value jsonb not null,
  description text,
  source_ref text,
  updated_at timestamptz not null default now()
);
insert into config.system_settings(setting_key,setting_value,description,source_ref)
values
 ('business_master_apply_enabled','false'::jsonb,'Domain Commands must not mutate PostgreSQL business master until controlled Part 4 apply layer acceptance passes.','Part3F/Part4 handoff'),
 ('production_cutover_approved','false'::jsonb,'Supabase TEST is not the approved Production Source of Truth.','Part4 handoff'),
 ('external_channel_webhooks_enabled','false'::jsonb,'External live channel webhooks remain disabled during TEST implementation.','Part3/Part4 handoff'),
 ('current_operational_source','"GOOGLE_SHEETS_DRIVE"'::jsonb,'Current operational Source of Truth remains Google Sheets + Google Drive until approved cutover.','Control Index V3.6')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();
revoke all on config.system_settings from anon,authenticated;
grant select,insert,update,delete on config.system_settings to service_role;
commit;
