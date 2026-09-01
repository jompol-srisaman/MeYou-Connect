do $smoke$
declare
  u1 uuid:='71111111-1111-4111-8111-111111111111'::uuid;
  u2 uuid:='72222222-2222-4222-8222-222222222222'::uuid;
  org_c1 uuid;org_c2 uuid;org_p1 uuid;a1 uuid;a2 uuid;
  v_bool boolean;v_count integer;v_failed boolean;v_json jsonb;v_old_activation jsonb;
begin
  select setting_value into v_old_activation from config.system_settings where setting_key='province_scale_activation_enabled';

  delete from authz.organization_members where auth_user_id in (u1,u2);
  delete from authz.candidate_user_links where auth_user_id in (u1,u2) or candidate_id in ('MYC-C-999903','MYC-C-999904');
  delete from authz.organizations where business_party_id in ('MYC-B2B-9997','MYC-B2B-9996','MYC-B2B-9995','MYC-P-9998');
  delete from core.partner_service_areas where partner_id='MYC-P-9998';
  delete from ops.province_scale_gate_results where province_code='T7A01';
  delete from ops.province_scale_state where province_code='T7A01';
  delete from geo.service_areas where province_code='T7A01';
  delete from core.candidates where candidate_id in ('MYC-C-999903','MYC-C-999904');
  delete from core.partners where partner_id='MYC-P-9998';
  delete from core.clients where client_id in ('MYC-B2B-9997','MYC-B2B-9996');
  delete from geo.provinces where province_code='T7A01';
  delete from auth.users where id in (u1,u2);

  insert into geo.provinces(province_code,name_th,name_en,source_ref) values('T7A01','จังหวัดทดสอบ Part 7A','Part7A Test Province','PART7A_SMOKE');
  insert into geo.service_areas(area_type,name,province_code,config) values('PROVINCE','Part7A Province Area','T7A01','{}'::jsonb) returning service_area_id into a1;
  insert into geo.service_areas(area_type,name,province_code,config) values('INDUSTRIAL_ZONE','Part7A Industrial Area','T7A01','{}'::jsonb) returning service_area_id into a2;

  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status) values
    ('MYC-B2B-9997','TEST','Part7A Client One','Test','ACTIVE','VERIFIED'),
    ('MYC-B2B-9996','TEST','Part7A Client Two','Test','ACTIVE','VERIFIED');
  insert into core.partners(partner_id,partner_name,partner_type,province,status) values('MYC-P-9998','Part7A Partner','TEST','Test','ACTIVE');
  insert into core.candidates(candidate_id,nickname,source_type,status) values
    ('MYC-C-999903','Part7A Candidate A','TEST','LEAD'),
    ('MYC-C-999904','Part7A Candidate B','TEST','LEAD');

  insert into core.partner_service_areas(partner_id,service_area_id,status) values('MYC-P-9998',a1,'ACTIVE'),('MYC-P-9998',a2,'ACTIVE');
  select count(*) into v_count from core.partner_service_areas where partner_id='MYC-P-9998';
  if v_count<>2 or (select count(*) from core.partners where partner_id='MYC-P-9998')<>1 then raise exception 'P7A-001_FAILED'; end if;

  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9997','ACTIVE') returning org_id into org_c1;
  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9996','ACTIVE') returning org_id into org_c2;
  insert into authz.organizations(org_type,business_party_id,status) values('PARTNER','MYC-P-9998','ACTIVE') returning org_id into org_p1;
  v_failed:=false;
  begin
    insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9995','ACTIVE');
  exception when others then
    if position('CLIENT_BUSINESS_PARTY_NOT_FOUND' in sqlerrm)>0 then v_failed:=true; else raise; end if;
  end;
  if not v_failed then raise exception 'P7A-002_FAILED'; end if;

  insert into auth.users(id) values(u1),(u2);
  insert into authz.organization_members(org_id,auth_user_id,portal_role,membership_status,active_from,created_by) values
    (org_c1,u1,'client_admin','ACTIVE',now()-interval '1 minute','PART7A_SMOKE'),
    (org_p1,u1,'partner_admin','ACTIVE',now()-interval '1 minute','PART7A_SMOKE');

  perform set_config('request.jwt.claim.sub',u1::text,true); execute 'set local role authenticated';
  select authz.is_active_org_member(org_c1) into v_bool;
  if not v_bool then raise exception 'P7A-003_FAILED'; end if;
  select (authz.is_active_org_member(org_c1) and authz.is_active_org_member(org_p1) and not authz.is_active_org_member(org_c2)) into v_bool;
  if not v_bool then raise exception 'P7A-005_FAILED'; end if;
  execute 'reset role';

  update authz.organization_members set membership_status='REMOVED',removed_at=now(),updated_at=now(),updated_by='PART7A_SMOKE' where org_id=org_c1 and auth_user_id=u1;
  perform set_config('request.jwt.claim.sub',u1::text,true); execute 'set local role authenticated';
  select authz.is_active_org_member(org_c1) into v_bool;
  if v_bool then raise exception 'P7A-004_FAILED'; end if;
  execute 'reset role';
  update authz.organization_members set membership_status='ACTIVE',removed_at=null,active_from=now()-interval '1 minute',updated_at=now(),updated_by='PART7A_SMOKE' where org_id=org_c1 and auth_user_id=u1;

  insert into authz.candidate_user_links(auth_user_id,candidate_id,verification_status,verified_by,verified_at) values(u1,'MYC-C-999903','VERIFIED','PART7A_SMOKE',now());
  perform set_config('request.jwt.claim.sub',u1::text,true); execute 'set local role authenticated';
  select (authz.is_verified_candidate_user('MYC-C-999903') and not authz.is_verified_candidate_user('MYC-C-999904') and authz.current_candidate_id()='MYC-C-999903') into v_bool;
  if not v_bool then raise exception 'P7A-006_FAILED_SCOPE'; end if;
  execute 'reset role';
  v_failed:=false;
  begin
    insert into authz.candidate_user_links(auth_user_id,candidate_id,verification_status,verified_by,verified_at) values(u2,'MYC-C-999903','VERIFIED','PART7A_SMOKE',now());
  exception when unique_violation then v_failed:=true;
  end;
  if not v_failed then raise exception 'P7A-006_FAILED_UNIQUE'; end if;

  select count(*) into v_count from ops.portal_feature_flags where environment='TEST' and enabled=true;
  if v_count<>0 then raise exception 'P7A-007_FAILED_FEATURE_FLAG'; end if;
  select count(*) into v_count from config.system_settings where setting_key in ('portal_external_access_enabled','portal_candidate_enabled','portal_partner_enabled','portal_client_enabled','province_scale_activation_enabled','marketplace_enabled') and coalesce((setting_value #>> '{}')::boolean,false)=true;
  if v_count<>0 then raise exception 'P7A-007_FAILED_MASTER_SWITCH'; end if;

  insert into ops.province_scale_state(province_code,lifecycle_state,founder_approved,approved_by,approved_at,status_reason)
    values('T7A01','RESEARCH',true,'PART7A_FOUNDER_SMOKE',now(),'Synthetic acceptance');
  insert into ops.province_scale_gate_results(province_code,gate_key,readiness_status,evidence_ref,evaluated_by,evaluated_at)
    select 'T7A01',gate_key,'READY','PART7A_SMOKE_EVIDENCE','PART7A_SMOKE',now() from ops.scale_gate_catalog where active;
  perform ops.set_province_lifecycle('T7A01','DEMAND_VALIDATION','PART7A_SMOKE','Synthetic demand validation');
  perform ops.set_province_lifecycle('T7A01','PILOT','PART7A_SMOKE','Synthetic pilot');
  v_failed:=false;
  begin
    perform ops.set_province_lifecycle('T7A01','ACTIVE','PART7A_SMOKE','Must be blocked while master switch is off');
  exception when others then
    if position('ACTIVE_SCALE_GATES_NOT_READY' in sqlerrm)>0 then v_failed:=true; else raise; end if;
  end;
  if not v_failed then raise exception 'P7A-008_FAILED_MASTER_GATE'; end if;
  update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key='province_scale_activation_enabled';
  v_json:=ops.set_province_lifecycle('T7A01','ACTIVE','PART7A_SMOKE','Synthetic all-gates-ready acceptance');
  if coalesce(v_json->>'to_state','')<>'ACTIVE' then raise exception 'P7A-008_FAILED_READY_PATH'; end if;
  update config.system_settings set setting_value=coalesce(v_old_activation,'false'::jsonb),updated_at=now() where setting_key='province_scale_activation_enabled';

  perform set_config('request.jwt.claim.sub','',true);
  delete from authz.organization_members where auth_user_id in (u1,u2);
  delete from authz.candidate_user_links where auth_user_id in (u1,u2) or candidate_id in ('MYC-C-999903','MYC-C-999904');
  delete from authz.organizations where business_party_id in ('MYC-B2B-9997','MYC-B2B-9996','MYC-P-9998');
  delete from core.partner_service_areas where partner_id='MYC-P-9998';
  delete from ops.province_scale_gate_results where province_code='T7A01';
  delete from ops.province_scale_state where province_code='T7A01';
  delete from geo.service_areas where province_code='T7A01';
  delete from core.candidates where candidate_id in ('MYC-C-999903','MYC-C-999904');
  delete from core.partners where partner_id='MYC-P-9998';
  delete from core.clients where client_id in ('MYC-B2B-9997','MYC-B2B-9996');
  delete from geo.provinces where province_code='T7A01';
  delete from auth.users where id in (u1,u2);

  update ops.part7a_acceptance_catalog set status='PASS',evidence_ref='part7_wave7a_foundation_acceptance_smoke',last_tested_at=now(),updated_at=now() where test_id like 'P7A-%';
  if (select count(*) from ops.portal_acceptance_catalog where status<>'NOT_RUN')<>0 then raise exception 'CANONICAL_PORTAL_TESTS_MUST_REMAIN_NOT_RUN_IN_7A'; end if;
end
$smoke$;