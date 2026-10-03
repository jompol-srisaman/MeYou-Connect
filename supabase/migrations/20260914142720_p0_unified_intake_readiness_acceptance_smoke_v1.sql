-- P0 Unified Intake Readiness acceptance smoke. Read/assert only.
do $$
declare
  v_count bigint;
begin
  if ops.file_intelligence_route_v1('image/jpeg','x.jpg')->>'route_key' <> 'IMAGE' then raise exception 'FILE_ROUTE_IMAGE_FAIL'; end if;
  if ops.file_intelligence_route_v1('application/pdf','x.pdf')->>'route_key' <> 'PDF' then raise exception 'FILE_ROUTE_PDF_FAIL'; end if;
  if ops.file_intelligence_route_v1('application/vnd.openxmlformats-officedocument.wordprocessingml.document','x.docx')->>'route_key' <> 'DOCX' then raise exception 'FILE_ROUTE_DOCX_FAIL'; end if;
  if ops.file_intelligence_route_v1('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','x.xlsx')->>'route_key' <> 'XLSX' then raise exception 'FILE_ROUTE_XLSX_FAIL'; end if;
  if ops.file_intelligence_route_v1('text/csv','x.csv')->>'route_key' <> 'CSV' then raise exception 'FILE_ROUTE_CSV_FAIL'; end if;
  if ops.file_intelligence_route_v1('text/plain','x.txt')->>'route_key' <> 'TXT' then raise exception 'FILE_ROUTE_TXT_FAIL'; end if;
  if ops.file_intelligence_route_v1('audio/mpeg','x.mp3')->>'route_key' <> 'AUDIO' then raise exception 'FILE_ROUTE_AUDIO_FAIL'; end if;
  if ops.file_intelligence_route_v1('video/mp4','x.mp4')->>'route_key' <> 'VIDEO' then raise exception 'FILE_ROUTE_VIDEO_FAIL'; end if;

  select count(*) into v_count from ops.file_intelligence_compatibility_v;
  if v_count <> 8 then raise exception 'FILE_COMPATIBILITY_ROW_COUNT_FAIL:%',v_count; end if;

  select count(*) into v_count
  from ops.line_context_resolution_v c
  join ops.raw_inputs a on a.raw_input_id=c.anchor_raw_input_id
  where a.thread_id is distinct from c.thread_id
     or a.source_account_ref is distinct from c.source_account_ref;
  if v_count <> 0 then raise exception 'CONTEXT_THREAD_ISOLATION_FAIL:%',v_count; end if;

  select count(*) into v_count from ops.b2b_response_event_map_v;
  if v_count <> 7 then raise exception 'B2B_RESPONSE_MAP_FAIL:%',v_count; end if;

  if not exists (
    select 1 from ops.channel_identities
    where source_system='LINE'
      and source_account_ref='LINE_OA:MYC_DATA_BOT'
      and identity_ref='U1738e96a0eff5456a4656a2435712447'
      and link_status='VERIFIED'
      and linked_entity_type='Partner'
      and linked_entity_id='MYC-P-0001'
  ) then raise exception 'VERIFIED_PARTNER_IDENTITY_FAIL'; end if;

  if exists (select 1 from ops.consent_readiness_v where auto_submit_allowed=true) then
    raise exception 'CONSENT_FAIL_CLOSED_FAIL';
  end if;

  if exists (select 1 from ops.unified_worker_readiness_v where readiness not in ('READY','PARTIAL','NOT_STARTED','BLOCKED')) then
    raise exception 'WORKER_READINESS_ENUM_FAIL';
  end if;

  if has_table_privilege('anon','ops.candidate_reconciliation_workbench_v','select')
     or has_table_privilege('authenticated','ops.candidate_reconciliation_workbench_v','select')
     or has_table_privilege('anon','ops.line_context_resolution_v','select')
     or has_table_privilege('authenticated','ops.line_context_resolution_v','select') then
    raise exception 'CLIENT_READ_GRANT_EXPOSURE_FAIL';
  end if;
end $$;
