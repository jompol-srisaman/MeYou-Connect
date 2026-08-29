do $$
declare
  v1 jsonb;
  v2 jsonb;
  vpeek jsonb;
  v_blocked boolean := false;
  v_bad_id_blocked boolean := false;
  v_count integer;
begin
  if not exists(select 1 from information_schema.schemata where schema_name='core') then raise exception '4A FAIL: core schema missing'; end if;
  if not exists(select 1 from information_schema.schemata where schema_name='config') then raise exception '4A FAIL: config schema missing'; end if;

  insert into config.id_allocators(entity_key,prefix,next_number,digits,active,allocation_enabled,conflict_status,source_ref,rule_notes)
  values('TEST_ATOMIC','WC-TST-',1,4,true,true,'NONE','smoke','Part 4A atomic allocator smoke');

  v1:=config.allocate_business_id('TEST_ATOMIC','part4a-smoke',jsonb_build_object('test',true));
  v2:=config.allocate_business_id('TEST_ATOMIC','part4a-smoke',jsonb_build_object('test',true));

  if v1->>'allocated_id' <> 'WC-TST-0001' then raise exception '4A FAIL: first atomic ID %',v1; end if;
  if v2->>'allocated_id' <> 'WC-TST-0002' then raise exception '4A FAIL: second atomic ID %',v2; end if;
  select count(*) into v_count from config.id_allocation_audit where entity_key='TEST_ATOMIC';
  if v_count<>2 then raise exception '4A FAIL: expected 2 allocation audit rows, got %',v_count; end if;
  if (select next_number from config.id_allocators where entity_key='TEST_ATOMIC')<>3 then raise exception '4A FAIL: allocator did not advance to 3'; end if;

  vpeek:=config.peek_business_id('Partner');
  if vpeek->>'next_id' <> 'WC-P-0003' then raise exception '4A FAIL: Partner allocator not initialized from Data Hub: %',vpeek; end if;

  begin
    perform config.allocate_business_id('Candidate','part4a-smoke','{}'::jsonb);
  exception when others then
    if position('allocator blocked' in sqlerrm)>0 then v_blocked:=true; else raise; end if;
  end;
  if not v_blocked then raise exception '4A FAIL: Candidate allocator should be blocked by source conflict'; end if;

  begin
    insert into core.clients(client_id,company_name) values('BAD-CLIENT-ID','bad');
  exception when check_violation then v_bad_id_blocked:=true;
  end;
  if not v_bad_id_blocked then raise exception '4A FAIL: invalid client ID was accepted'; end if;

  insert into core.clients(client_id,company_name,province) values('WC-B2B-9999','Synthetic Client','สระบุรี');
  insert into core.partners(partner_id,partner_name,status) values('WC-P-9999','Synthetic Partner','TEST');
  insert into core.jobs(job_id,client_id,position_name,status) values('WC-J-999999','WC-B2B-9999','Synthetic Job','TEST');
  insert into core.candidates(candidate_id,nickname,partner_id,status) values('WC-C-999999','Synthetic','WC-P-9999','TEST');
  insert into core.placements(placement_id,candidate_id,job_id,status) values('WC-PL-999999','WC-C-999999','WC-J-999999','TEST');
  insert into core.followups(followup_id,placement_id,milestone,result) values('TEST-FU-999999','WC-PL-999999','D1','TEST');
  insert into core.dorms(dorm_id,dorm_name,status) values('TEST-DORM-9999','Synthetic Dorm','TEST');
  insert into core.transport_providers(transport_id,provider_name,status) values('WC-TR-9999','Synthetic Transport','TEST');

  if (select count(*) from core.placements where placement_id='WC-PL-999999')<>1 then raise exception '4A FAIL: core FK chain not created'; end if;

  delete from core.followups where followup_id='TEST-FU-999999';
  delete from core.placements where placement_id='WC-PL-999999';
  delete from core.candidates where candidate_id='WC-C-999999';
  delete from core.jobs where job_id='WC-J-999999';
  delete from core.partners where partner_id='WC-P-9999';
  delete from core.clients where client_id='WC-B2B-9999';
  delete from core.dorms where dorm_id='TEST-DORM-9999';
  delete from core.transport_providers where transport_id='WC-TR-9999';
  delete from config.id_allocation_audit where entity_key='TEST_ATOMIC';
  delete from config.id_allocators where entity_key='TEST_ATOMIC';
end $$;
