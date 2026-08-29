begin;

do $$
declare
  v_file1 text; v_file2 text; v_ev text; v_c1 text; v_c2 text; v_decision text;
  v_count integer; v_blocked boolean:=false; v_rls boolean;
begin
  select count(*) into v_count from storage.buckets where id in ('raw-inbox-private','evidence-private','business-private','content-public') and public=false;
  if v_count<>4 then raise exception '4B AT-001 FAIL: expected 4 private Supabase buckets, got %',v_count; end if;

  insert into ops.raw_inputs(raw_input_id,channel,sender_type,content_type,original_ref,raw_summary,source_system,processing_status)
  values('WC-RAW-TEST4B','TEST','Founder','text','part4b:test','Part4B synthetic source','test','RAW_STORED');
  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status) values('WC-B2B-9999','TEST','Synthetic Client','TEST','TEST','TEST');
  insert into core.partners(partner_id,partner_name,partner_type,status) values('WC-P-9999','Synthetic Partner','TEST','TEST');
  insert into core.candidates(candidate_id,nickname,origin_province,status) values('WC-C-999999','Synthetic Candidate','TEST','TEST');

  insert into private.candidate_contacts(candidate_id,full_name,phone,line_id,email,national_id,current_address,source_raw_input_id)
  values('WC-C-999999','Synthetic Candidate Full Name','0800000000','test-line','test@example.invalid','0000000000000','TEST ADDRESS','WC-RAW-TEST4B');
  insert into private.client_contacts(client_id,contact_name,phone,email,source_raw_input_id) values('WC-B2B-9999','Synthetic Client Contact','0800000001','client@example.invalid','WC-RAW-TEST4B');
  insert into private.partner_contacts(partner_id,contact_name,phone,line_id,source_raw_input_id) values('WC-P-9999','Synthetic Partner Contact','0800000002','partner-test','WC-RAW-TEST4B');

  if not exists(select 1 from private.candidate_contacts where candidate_id='WC-C-999999' and phone='0800000000') then raise exception '4B AT-002 FAIL: candidate PII split missing'; end if;
  if exists(select 1 from information_schema.columns where table_schema='core' and table_name='candidates' and column_name in ('phone','line_id','email','national_id','current_address')) then raise exception '4B AT-003 FAIL: candidate PII leaked into core schema'; end if;

  update config.system_settings set setting_value='true'::jsonb where setting_key in ('postgres_docs_write_enabled','postgres_consent_write_enabled');

  v_file1:=docs.register_file_metadata('WC-RAW-TEST4B','GOOGLE_DRIVE','evidence-private',null,null,'drive-provider-test','drive-test-file-id','https://drive.google.com/file/d/test/view','candidate_photo.jpg','WC-C-999999_20260829_ProfilePhoto_v01.jpg','image/jpeg',12345,null,'SOURCE_NOT_MIRRORED','PII',array['candidate','profile_photo'],'Synthetic candidate profile photo source','part4b-smoke');
  if v_file1 !~ '^WC-FILE-[0-9]{6}$' then raise exception '4B AT-004 FAIL: invalid File Registry ID %',v_file1; end if;
  if not exists(select 1 from docs.files where file_id=v_file1 and storage_status='SOURCE_NOT_MIRRORED' and source_url is not null) then raise exception '4B AT-005 FAIL: SOURCE_NOT_MIRRORED provenance not preserved'; end if;

  v_ev:=docs.register_evidence_record(v_file1,'PROFILE_PHOTO','OPERATIONAL_EVIDENCE',now(),'Founder/File Source','Synthetic profile-photo evidence','part4b-smoke');
  perform docs.link_evidence(v_ev,'Candidate','WC-C-999999','PROFILE_PHOTO','part4b-smoke');
  if not exists(select 1 from docs.evidence_links where evidence_id=v_ev and entity_type='Candidate' and entity_id='WC-C-999999' and link_role='PROFILE_PHOTO') then raise exception '4B AT-006 FAIL: candidate photo evidence link missing'; end if;

  v_file2:=docs.register_file_metadata('WC-RAW-TEST4B','SUPABASE_STORAGE','evidence-private','evidence-private','Candidate/WC-C-999999/test-object.jpg',null,null,null,'test-object.jpg','WC-C-999999_20260829_TestObject_v01.jpg','image/jpeg',10,repeat('a',64),'STORED','PII',array['test'],'Synthetic stored object','part4b-smoke');
  begin
    update docs.files set object_key='Candidate/WC-C-999999/overwritten.jpg' where file_id=v_file2;
  exception when others then
    if position('immutable' in sqlerrm)>0 then v_blocked:=true; else raise; end if;
  end;
  if not v_blocked then raise exception '4B AT-007 FAIL: stored object identity was mutable'; end if;

  v_c1:=privacy.record_consent('WC-C-999999','candidate_profile_processing','GRANTED',now(),v_ev,'WC-RAW-TEST4B',null,'Synthetic grant','part4b-smoke');
  v_c2:=privacy.record_consent('WC-C-999999','candidate_profile_processing','WITHDRAWN',now()+interval '1 second',v_ev,'WC-RAW-TEST4B',v_c1,'Synthetic withdrawal','part4b-smoke');
  select decision into v_decision from privacy.current_consents_v where candidate_id='WC-C-999999' and purpose_code='candidate_profile_processing';
  if v_decision<>'WITHDRAWN' then raise exception '4B AT-008 FAIL: current consent expected WITHDRAWN, got %',v_decision; end if;
  select count(*) into v_count from privacy.consents where candidate_id='WC-C-999999' and purpose_code='candidate_profile_processing';
  if v_count<>2 then raise exception '4B AT-009 FAIL: consent history expected 2 rows, got %',v_count; end if;
  if exists(select 1 from privacy.consents where candidate_id='WC-C-999999' and evidence_id is null) then raise exception '4B AT-010 FAIL: consent without evidence found'; end if;

  if has_table_privilege('anon','docs.files','select') or has_table_privilege('authenticated','docs.files','select') or has_table_privilege('anon','private.candidate_contacts','select') or has_table_privilege('authenticated','privacy.consents','select') then raise exception '4B AT-011 FAIL: anon/authenticated direct privilege detected'; end if;

  select c.relrowsecurity into v_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='private' and c.relname='candidate_contacts';
  if not coalesce(v_rls,false) then raise exception '4B AT-012 FAIL: candidate_contacts RLS not enabled'; end if;
  select c.relrowsecurity into v_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='privacy' and c.relname='consents';
  if not coalesce(v_rls,false) then raise exception '4B AT-013 FAIL: consents RLS not enabled'; end if;
  select c.relrowsecurity into v_rls from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='docs' and c.relname='files';
  if not coalesce(v_rls,false) then raise exception '4B AT-014 FAIL: files RLS not enabled'; end if;

  raise notice 'PASS Part4B: PII split, provenance, profile photo evidence, immutable object identity, consent history, default-deny RLS';
end $$;

rollback;
