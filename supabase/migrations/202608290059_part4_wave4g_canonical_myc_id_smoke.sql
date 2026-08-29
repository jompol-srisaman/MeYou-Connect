do $$
declare
  v_session uuid;
  v_valid_status text;
  v_invalid_status text;
  v_cnt int;
  v_failed boolean:=false;
begin
  if exists(select 1 from config.id_allocators where entity_key in ('Candidate','Job','Client','Partner','Placement','Transport','Evidence','Consent','Content','Activity','AI Run','Risk','Raw Input','File Registry','DQ Issue','Journal Batch','AR','AP','Bank Txn','Tax Doc') and prefix not like 'MYC-%') then
    raise exception 'one or more canonical allocators still use non-MYC namespace';
  end if;
  if (select prefix from config.id_allocators where entity_key='Candidate')<>'MYC-C-' then raise exception 'Candidate allocator mismatch'; end if;
  if (select prefix from config.id_allocators where entity_key='Partner')<>'MYC-P-' then raise exception 'Partner allocator mismatch'; end if;
  if (select next_number from config.id_allocators where entity_key='Partner')<>3 then raise exception 'Partner next number changed unexpectedly'; end if;
  if (select last_allocated_id from config.id_allocators where entity_key='Partner')<>'MYC-P-0002' then raise exception 'Partner last allocated ID mismatch'; end if;
  if (select prefix from config.id_allocators where entity_key='File Registry')<>'MYC-FILE-' then raise exception 'File allocator mismatch'; end if;
  if (select next_number from config.id_allocators where entity_key='File Registry')<>3 then raise exception 'File next number changed unexpectedly'; end if;
  if exists(select 1 from ops.migration_entity_map where id_regex like '^WC-%') then raise exception 'stale WC regex remains in migration map'; end if;
  if (select id_regex from ops.migration_entity_map where entity_key='Partner')<>'^MYC-P-[0-9]{4}$' then raise exception 'Partner migration regex mismatch'; end if;

  begin
    insert into core.partners(partner_id,partner_name,status) values('WC-P-9999','STALE_NAMESPACE_SHOULD_FAIL','ACTIVE');
  exception when check_violation then
    v_failed:=true;
  end;
  if not v_failed then raise exception 'stale WC Partner ID unexpectedly passed DB constraint'; end if;

  insert into core.partners(partner_id,partner_name,status) values('MYC-P-9999','CANONICAL_NAMESPACE_SMOKE','ACTIVE');
  delete from core.partners where partner_id='MYC-P-9999';

  update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key='migration_shadow_write_enabled';
  insert into ops.shadow_import_sessions(source_system,source_file_id,source_file_name,source_revision,snapshot_at,status,source_of_truth,expected_entities,metadata,created_by)
  values('GOOGLE_SHEETS_DRIVE','MYC-ID-SMOKE','MYC_ID_NAMESPACE_SMOKE','MYC-ID-1',now(),'OPEN',true,array['Partner'],'{"smoke":true}'::jsonb,'PART4G_MYC_SMOKE')
  returning session_id into v_session;

  perform ops.stage_shadow_row(v_session,'Partner',2,'MYC-P-9998','{"partner_id":"MYC-P-9998","partner_name":"Valid MYC"}'::jsonb,'{"partner_id":"MYC-P-9998","partner_name":"Valid MYC"}'::jsonb);
  perform ops.stage_shadow_row(v_session,'Partner',3,'WC-P-9998','{"partner_id":"WC-P-9998","partner_name":"Stale WC"}'::jsonb,'{"partner_id":"WC-P-9998","partner_name":"Stale WC"}'::jsonb);
  perform ops.validate_shadow_session(v_session);

  select validation_status into v_valid_status from ops.shadow_import_rows where session_id=v_session and source_row_number=2;
  select validation_status into v_invalid_status from ops.shadow_import_rows where session_id=v_session and source_row_number=3;
  if v_valid_status<>'VALID' then raise exception 'canonical MYC Partner staging should validate, got %',v_valid_status; end if;
  if v_invalid_status<>'INVALID' then raise exception 'stale WC Partner staging should be invalid, got %',v_invalid_status; end if;
  if not exists(
    select 1 from ops.shadow_import_rows
    where session_id=v_session and source_row_number=3
      and validation_issues @> '[{"code":"ID_PATTERN_MISMATCH"}]'::jsonb
  ) then raise exception 'stale WC row missing ID_PATTERN_MISMATCH'; end if;

  delete from ops.shadow_import_rows where session_id=v_session;
  delete from ops.shadow_import_sessions where session_id=v_session;
  update config.system_settings set setting_value='false'::jsonb,updated_at=now() where setting_key='migration_shadow_write_enabled';

  select count(*) into v_cnt from core.partners where partner_id in ('MYC-P-9999','WC-P-9999');
  if v_cnt<>0 then raise exception 'namespace smoke left Partner residue'; end if;
  if (select next_number from config.id_allocators where entity_key='Partner')<>3 then raise exception 'namespace smoke consumed Partner allocator'; end if;
  if (select next_number from config.id_allocators where entity_key='File Registry')<>3 then raise exception 'namespace smoke consumed File allocator'; end if;
end $$;
