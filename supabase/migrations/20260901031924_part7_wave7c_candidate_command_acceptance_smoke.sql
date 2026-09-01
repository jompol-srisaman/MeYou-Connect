do $smoke$
declare
  u_candidate_a uuid:=gen_random_uuid();
  u_candidate_b uuid:=gen_random_uuid();
  u_partner uuid:=gen_random_uuid();
  org_partner uuid;
  req_contact uuid:=gen_random_uuid();
  req_contact_bad uuid:=gen_random_uuid();
  req_contact_revoked uuid:=gen_random_uuid();
  req_outcome uuid:=gen_random_uuid();
  req_outcome_b uuid:=gen_random_uuid();
  v_json jsonb;
  v_json2 jsonb;
  v_event_contact uuid;
  v_event_outcome uuid;
  v_raw_contact text;
  v_raw_outcome text;
  v_run uuid;
  v_lease uuid;
  v_cmd uuid;
  v_count integer;
  v_text text;
  v_failed boolean;
  old_external jsonb;
  old_candidate jsonb;
  old_business jsonb;
  old_profile_enabled boolean; old_profile_by text; old_profile_at timestamptz;
  old_follow_enabled boolean; old_follow_by text; old_follow_at timestamptz;
begin
  select setting_value into old_external from config.system_settings where setting_key='portal_external_access_enabled';
  select setting_value into old_candidate from config.system_settings where setting_key='portal_candidate_enabled';
  select setting_value into old_business from config.system_settings where setting_key='business_master_apply_enabled';
  select enabled,enabled_by,enabled_at into old_profile_enabled,old_profile_by,old_profile_at from ops.portal_feature_flags where feature_key='candidate_profile_edit' and environment='TEST' and org_id is null and service_area_id is null limit 1;
  select enabled,enabled_by,enabled_at into old_follow_enabled,old_follow_by,old_follow_at from ops.portal_feature_flags where feature_key='candidate_followup' and environment='TEST' and org_id is null and service_area_id is null limit 1;

  update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key in ('portal_external_access_enabled','portal_candidate_enabled','business_master_apply_enabled');
  update ops.portal_feature_flags set enabled=true,enabled_by='PART7C_SMOKE',enabled_at=now(),updated_at=now()
   where feature_key in ('candidate_profile_edit','candidate_followup') and environment='TEST' and org_id is null and service_area_id is null;

  delete from private.candidate_contacts where candidate_id in ('MYC-C-999911','MYC-C-999912');
  delete from core.placements where placement_id in ('MYC-PL-999911','MYC-PL-999912');
  delete from core.jobs where job_id='MYC-J-999911';
  delete from authz.candidate_user_links where candidate_id in ('MYC-C-999911','MYC-C-999912');
  delete from core.candidates where candidate_id in ('MYC-C-999911','MYC-C-999912');
  delete from authz.organization_members where org_id in (select org_id from authz.organizations where business_party_id='MYC-P-9981');
  delete from authz.organizations where business_party_id='MYC-P-9981';
  delete from core.partners where partner_id='MYC-P-9981';
  delete from core.clients where client_id='MYC-B2B-9981';

  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status)
  values('MYC-B2B-9981','TEST','Part7C Client','TEST','ACTIVE','VERIFIED');
  insert into core.partners(partner_id,partner_name,partner_type,province,status)
  values('MYC-P-9981','Part7C Partner','TEST','TEST','ACTIVE');
  insert into core.candidates(candidate_id,nickname,education,primary_experience,preferred_job,relocation_ready,documents_ready,medical_ready,source_type,status) values
  ('MYC-C-999911','Candidate A','M6','Warehouse','Warehouse',true,true,true,'DIRECT','QUALIFIED'),
  ('MYC-C-999912','Candidate B','M6','Production','Production',true,true,true,'DIRECT','QUALIFIED');
  insert into core.jobs(job_id,client_id,workplace_name,province,position_name,headcount,wage,shift,status,milestone_deal)
  values('MYC-J-999911','MYC-B2B-9981','Part7C Factory','TEST','Warehouse',2,400,'DAY','ACTIVE','LOCKED_TEST_DEAL');
  insert into core.placements(placement_id,candidate_id,job_id,status,submitted_at,start_date) values
  ('MYC-PL-999911','MYC-C-999911','MYC-J-999911','STARTED',now(),current_date),
  ('MYC-PL-999912','MYC-C-999912','MYC-J-999911','STARTED',now(),current_date);
  insert into private.candidate_contacts(candidate_id,full_name,phone,line_id,email,national_id,current_address,notes)
  values('MYC-C-999911','KEEP FULL NAME','0800000000','keep-line','keep@example.test','KEEP-NATIONAL-ID','KEEP ADDRESS','KEEP NOTES');

  insert into auth.users(id) values(u_candidate_a),(u_candidate_b),(u_partner);
  insert into authz.candidate_user_links(auth_user_id,candidate_id,verification_status,verified_by,verified_at) values
  (u_candidate_a,'MYC-C-999911','VERIFIED','PART7C_SMOKE',now()),
  (u_candidate_b,'MYC-C-999912','VERIFIED','PART7C_SMOKE',now());
  insert into authz.organizations(org_type,business_party_id,status) values('PARTNER','MYC-P-9981','ACTIVE') returning org_id into org_partner;
  insert into authz.organization_members(org_id,auth_user_id,portal_role,membership_status,active_from,created_by)
  values(org_partner,u_partner,'partner_admin','ACTIVE',now()-interval '1 minute','PART7C_SMOKE');

  perform set_config('request.jwt.claim.sub',u_candidate_a::text,true); execute 'set local role authenticated';
  select api.portal_candidate_propose_contact_update(req_contact,'{"phone":"0911111111","email":"candidate-a@example.test"}'::jsonb) into v_json;
  if v_json->>'candidate_id'<>'MYC-C-999911' or v_json->>'request_status'<>'ACCEPTED' or coalesce((v_json->>'duplicate_request')::boolean,false) then raise exception 'P7C-001_INGRESS_FAILED'; end if;
  execute 'reset role';
  v_event_contact:=(v_json->>'event_pk')::uuid;
  v_raw_contact:=v_json->>'raw_input_id';
  if not exists(
    select 1 from ops.portal_action_requests r join ops.events e on e.event_pk=r.event_pk join ops.raw_inputs ri on ri.raw_input_id=r.raw_input_id
    where r.request_id=req_contact and r.auth_user_id=u_candidate_a and r.candidate_id='MYC-C-999911'
      and r.event_pk=v_event_contact and r.raw_input_id=v_raw_contact and r.trace_id=e.trace_id
      and e.raw_input_id=r.raw_input_id and e.event_type='portal.candidate.contact_change.requested'
      and ri.metadata->>'actor_auth_user_id'=u_candidate_a::text and ri.metadata->>'candidate_id'='MYC-C-999911'
  ) then raise exception 'P7C-008_PROVENANCE_FAILED'; end if;

  perform set_config('request.jwt.claim.sub',u_candidate_a::text,true); execute 'set local role authenticated';
  v_failed:=false;
  begin
    perform api.portal_candidate_propose_contact_update(req_contact_bad,'{"national_id":"SHOULD-NOT-WRITE"}'::jsonb);
  exception when others then
    if position('CONTACT_FIELD_NOT_ALLOWED' in sqlerrm)>0 then v_failed:=true; else raise; end if;
  end;
  if not v_failed then raise exception 'P7C-003_HIGH_RISK_FIELD_NOT_DENIED'; end if;
  execute 'reset role';
  if exists(select 1 from ops.portal_action_requests where request_id=req_contact_bad) then raise exception 'P7C-003_BAD_REQUEST_PERSISTED'; end if;

  perform set_config('request.jwt.claim.sub',u_candidate_a::text,true); execute 'set local role authenticated';
  v_failed:=false;
  begin perform api.portal_candidate_report_placement_outcome(req_outcome_b,'MYC-PL-999912','CLOSED','cross candidate attempt');
  exception when others then if position('PLACEMENT_NOT_OWNED_BY_CANDIDATE' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7C-002_CROSS_CANDIDATE_PLACEMENT_NOT_DENIED'; end if;
  v_failed:=false;
  begin perform 1 from api.get_candidate_contact('MYC-C-999912') limit 1; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'PT003_CROSS_CANDIDATE_CONTACT_READ_NOT_DENIED'; end if;
  v_failed:=false;
  begin perform 1 from api.get_consent_status('MYC-C-999912') limit 1; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'PT003_CROSS_CANDIDATE_CONSENT_READ_NOT_DENIED'; end if;
  v_failed:=false;
  begin execute 'select count(*) from docs.files' into v_count; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'PT003_PRIVATE_FILE_DIRECT_READ_NOT_DENIED'; end if;
  v_failed:=false;
  begin execute 'update core.candidates set nickname=''HACK'' where candidate_id=''MYC-C-999912'''; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'PT003_DIRECT_CANDIDATE_MASTER_UPDATE_NOT_DENIED'; end if;
  execute 'reset role';

  select c.worker_run_pk,c.lease_token into v_run,v_lease
  from ops.claim_events('portal_candidate_contact_worker','PART7C_SMOKE',20,300,now()) c
  where c.event_pk=v_event_contact;
  if v_run is null then raise exception 'P7C-001_WORKER_CLAIM_FAILED'; end if;
  select ops.prepare_domain_command(v_event_contact,'portal_candidate_contact_worker',v_lease,
    jsonb_build_object('fields','{"phone":"0911111111","email":"candidate-a@example.test"}'::jsonb),
    'CandidateContact','MYC-C-999911') into v_json2;
  if v_json2->>'validation_status'<>'VALID' or v_json2->>'apply_status'<>'READY' then raise exception 'P7C-001_COMMAND_VALIDATION_FAILED:%',v_json2; end if;
  v_cmd:=(v_json2->>'command_pk')::uuid;
  select ops.apply_portal_candidate_contact_command(v_cmd,v_lease,'PART7C_SMOKE') into v_json2;
  if v_json2->>'apply_status'<>'APPLIED' then raise exception 'P7C-001_APPLY_FAILED:%',v_json2; end if;
  select phone into v_text from private.candidate_contacts where candidate_id='MYC-C-999911';
  if v_text<>'0911111111' then raise exception 'P7C-001_CONTACT_EFFECT_FAILED'; end if;
  if exists(select 1 from private.candidate_contacts where candidate_id='MYC-C-999911' and (full_name<>'KEEP FULL NAME' or national_id<>'KEEP-NATIONAL-ID' or current_address<>'KEEP ADDRESS' or notes<>'KEEP NOTES')) then
    raise exception 'P7C-003_NON_WHITELISTED_PII_CHANGED';
  end if;
  if not exists(select 1 from ops.domain_command_apply_audit where command_pk=v_cmd and status='APPLIED')
     or not exists(select 1 from ops.event_effects where event_pk=v_event_contact and effect_type='portal_candidate_contact')
     or not exists(select 1 from ops.portal_action_requests where request_id=req_contact and request_status='APPLIED' and effect_ref='private.candidate_contacts:MYC-C-999911') then
    raise exception 'P7C-008_APPLY_AUDIT_CHAIN_FAILED';
  end if;

  perform set_config('request.jwt.claim.sub',u_candidate_a::text,true); execute 'set local role authenticated';
  select api.portal_candidate_propose_contact_update(req_contact,'{"phone":"0999999999"}'::jsonb) into v_json2;
  if coalesce((v_json2->>'duplicate_request')::boolean,false) is not true then raise exception 'P7C-006_DUPLICATE_NOT_RECOGNIZED'; end if;
  execute 'reset role';
  select count(*) into v_count from ops.portal_action_requests where request_id=req_contact;
  if v_count<>1 then raise exception 'P7C-006_DUPLICATE_ACTION_CREATED'; end if;
  select count(*) into v_count from ops.events where event_pk=v_event_contact;
  if v_count<>1 then raise exception 'P7C-006_DUPLICATE_EVENT_CREATED'; end if;
  if (select phone from private.candidate_contacts where candidate_id='MYC-C-999911')<>'0911111111' then raise exception 'P7C-006_DUPLICATE_MUTATED_EFFECT'; end if;

  update authz.candidate_user_links set disabled_at=now(),disable_reason='PART7C_SMOKE_REVOKE',updated_at=now() where auth_user_id=u_candidate_a and candidate_id='MYC-C-999911';
  perform set_config('request.jwt.claim.sub',u_candidate_a::text,true); execute 'set local role authenticated';
  v_failed:=false;
  begin perform api.portal_candidate_propose_contact_update(req_contact_revoked,'{"phone":"0922222222"}'::jsonb);
  exception when others then if position('VERIFIED_CANDIDATE_LINK_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7C-007_REVOKED_LINK_NOT_DENIED'; end if;
  execute 'reset role';
  update authz.candidate_user_links set disabled_at=null,disable_reason=null,updated_at=now() where auth_user_id=u_candidate_a and candidate_id='MYC-C-999911';

  perform set_config('request.jwt.claim.sub',u_candidate_a::text,true); execute 'set local role authenticated';
  select api.portal_candidate_report_placement_outcome(req_outcome,'MYC-PL-999911','CLOSED','candidate says work ended') into v_json;
  if v_json->>'request_status'<>'REVIEW_REQUIRED' or coalesce((v_json->>'official_placement_state_changed')::boolean,true) then raise exception 'P7C-005_OUTCOME_CONTRACT_FAILED'; end if;
  v_failed:=false;
  begin execute 'update core.placements set status=''CLOSED'' where placement_id=''MYC-PL-999911'''; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'PT011_DIRECT_PLACEMENT_MUTATION_NOT_DENIED'; end if;
  execute 'reset role';
  v_event_outcome:=(v_json->>'event_pk')::uuid;
  v_raw_outcome:=v_json->>'raw_input_id';
  if (select status from core.placements where placement_id='MYC-PL-999911')<>'STARTED' then raise exception 'P7C-005_OFFICIAL_PLACEMENT_STATE_CHANGED'; end if;
  if not exists(select 1 from ops.events where event_pk=v_event_outcome and event_type='portal.candidate.placement_outcome.reported' and raw_input_id=v_raw_outcome)
     or not exists(select 1 from ops.portal_action_requests where request_id=req_outcome and request_status='REVIEW_REQUIRED') then
    raise exception 'P7C-005_OUTCOME_EVENT_MISSING';
  end if;

  if (select count(*) from ops.portal_action_catalog where action_key in ('partner.candidate_consent.set','partner.b2b_rate.set') and action_class='DENY')<>2 then raise exception 'P7C-004_DENY_CATALOG_MISSING'; end if;
  perform set_config('request.jwt.claim.sub',u_partner::text,true); execute 'set local role authenticated';
  v_failed:=false;
  begin perform privacy.record_consent('MYC-C-999911','RECRUITMENT','GRANTED',now(),null,null,null,'should fail','PARTNER');
  exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'PT005_PARTNER_CONSENT_WRITE_NOT_DENIED'; end if;
  v_failed:=false;
  begin execute 'update core.jobs set milestone_deal=''PARTNER-HACK'' where job_id=''MYC-J-999911'''; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'PT005_PARTNER_B2B_RATE_WRITE_NOT_DENIED'; end if;
  execute 'reset role';
  if (select milestone_deal from core.jobs where job_id='MYC-J-999911')<>'LOCKED_TEST_DEAL' then raise exception 'PT005_PROTECTED_B2B_VALUE_CHANGED'; end if;

  update ops.part7c_acceptance_catalog set status='PASS',evidence_ref='part7_wave7c_candidate_command_acceptance_smoke',last_tested_at=now(),updated_at=now();
  update ops.portal_acceptance_catalog set status='PASS',evidence_ref='part7_wave7c_candidate_command_acceptance_smoke',last_tested_at=now(),updated_at=now()
    where test_id in ('PT-003','PT-005','PT-010','PT-011');

  delete from private.candidate_contacts where candidate_id in ('MYC-C-999911','MYC-C-999912');
  delete from ops.domain_command_apply_audit where command_pk=v_cmd;
  delete from ops.domain_commands where event_pk in (v_event_contact,v_event_outcome);
  delete from ops.portal_action_requests where request_id in (req_contact,req_outcome);
  delete from ops.event_effects where event_pk in (v_event_contact,v_event_outcome);
  delete from ops.worker_runs where event_pk in (v_event_contact,v_event_outcome);
  delete from ops.events where event_pk in (v_event_contact,v_event_outcome);
  delete from ops.raw_inputs where raw_input_id in (v_raw_contact,v_raw_outcome);
  delete from config.id_allocation_audit where allocated_id in (v_raw_contact,v_raw_outcome);
  delete from authz.candidate_user_links where candidate_id in ('MYC-C-999911','MYC-C-999912');
  delete from core.placements where placement_id in ('MYC-PL-999911','MYC-PL-999912');
  delete from core.jobs where job_id='MYC-J-999911';
  delete from core.candidates where candidate_id in ('MYC-C-999911','MYC-C-999912');
  delete from authz.organization_members where org_id=org_partner;
  delete from authz.organizations where org_id=org_partner;
  delete from core.partners where partner_id='MYC-P-9981';
  delete from core.clients where client_id='MYC-B2B-9981';
  delete from auth.users where id in (u_candidate_a,u_candidate_b,u_partner);

  update config.system_settings set setting_value=coalesce(old_external,'false'::jsonb),updated_at=now() where setting_key='portal_external_access_enabled';
  update config.system_settings set setting_value=coalesce(old_candidate,'false'::jsonb),updated_at=now() where setting_key='portal_candidate_enabled';
  update config.system_settings set setting_value=coalesce(old_business,'false'::jsonb),updated_at=now() where setting_key='business_master_apply_enabled';
  update ops.portal_feature_flags set enabled=coalesce(old_profile_enabled,false),enabled_by=old_profile_by,enabled_at=old_profile_at,updated_at=now()
    where feature_key='candidate_profile_edit' and environment='TEST' and org_id is null and service_area_id is null;
  update ops.portal_feature_flags set enabled=coalesce(old_follow_enabled,false),enabled_by=old_follow_by,enabled_at=old_follow_at,updated_at=now()
    where feature_key='candidate_followup' and environment='TEST' and org_id is null and service_area_id is null;
end
$smoke$;