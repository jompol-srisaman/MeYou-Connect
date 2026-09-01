do $smoke$
declare
  u_portal uuid:=gen_random_uuid();
  u_candidate_a uuid:=gen_random_uuid();
  u_candidate_b uuid:=gen_random_uuid();
  org_client_a uuid; org_client_b uuid; org_partner_a uuid; org_partner_b uuid;
  v_count integer; v_text text; v_failed boolean; v_result text;
  old_external jsonb; old_candidate jsonb; old_partner jsonb; old_client jsonb;
begin
  select setting_value into old_external from config.system_settings where setting_key='portal_external_access_enabled';
  select setting_value into old_candidate from config.system_settings where setting_key='portal_candidate_enabled';
  select setting_value into old_partner from config.system_settings where setting_key='portal_partner_enabled';
  select setting_value into old_client from config.system_settings where setting_key='portal_client_enabled';

  update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key in ('portal_external_access_enabled','portal_candidate_enabled','portal_partner_enabled','portal_client_enabled');

  delete from finance.accounts_receivable where ar_id in ('MYC-AR-999901','MYC-AR-999902');
  delete from finance.commissions where commission_id in ('P7B-COM-A','P7B-COM-B');
  delete from authz.client_candidate_purpose_access where placement_id in ('MYC-PL-999901','MYC-PL-999902');
  delete from finance.revenue where revenue_id in ('P7B-REV-A','P7B-REV-B');
  delete from core.placements where placement_id in ('MYC-PL-999901','MYC-PL-999902');
  delete from core.jobs where job_id in ('MYC-J-999901','MYC-J-999902');
  delete from authz.candidate_user_links where candidate_id in ('MYC-C-999901','MYC-C-999902');
  delete from core.candidates where candidate_id in ('MYC-C-999901','MYC-C-999902');
  delete from authz.organization_members where org_id in (select org_id from authz.organizations where business_party_id in ('MYC-B2B-9993','MYC-B2B-9992','MYC-P-9996','MYC-P-9995'));
  delete from authz.organizations where business_party_id in ('MYC-B2B-9993','MYC-B2B-9992','MYC-P-9996','MYC-P-9995');
  delete from core.partners where partner_id in ('MYC-P-9996','MYC-P-9995');
  delete from core.clients where client_id in ('MYC-B2B-9993','MYC-B2B-9992');

  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status) values
    ('MYC-B2B-9993','TEST','Part7B Client A','TEST','ACTIVE','VERIFIED'),
    ('MYC-B2B-9992','TEST','Part7B Client B','TEST','ACTIVE','VERIFIED');
  insert into core.partners(partner_id,partner_name,partner_type,province,status) values
    ('MYC-P-9996','Part7B Partner A','TEST','TEST','ACTIVE'),
    ('MYC-P-9995','Part7B Partner B','TEST','TEST','ACTIVE');
  insert into core.candidates(candidate_id,nickname,education,primary_experience,preferred_job,relocation_ready,documents_ready,medical_ready,source_type,partner_id,status) values
    ('MYC-C-999901','Candidate A','M6','Warehouse','Warehouse',true,true,true,'SOURCING_PARTNER','MYC-P-9996','QUALIFIED'),
    ('MYC-C-999902','Candidate B','M6','Production','Production',true,true,true,'SOURCING_PARTNER','MYC-P-9995','QUALIFIED');
  insert into core.jobs(job_id,client_id,workplace_name,province,position_name,headcount,wage,shift,status) values
    ('MYC-J-999901','MYC-B2B-9993','Client A Factory','TEST','Warehouse',2,400,'DAY','ACTIVE'),
    ('MYC-J-999902','MYC-B2B-9992','Client B Factory','TEST','Production',2,390,'DAY','ACTIVE');
  insert into core.placements(placement_id,candidate_id,job_id,status,submitted_at) values
    ('MYC-PL-999901','MYC-C-999901','MYC-J-999901','SUBMITTED',now()),
    ('MYC-PL-999902','MYC-C-999902','MYC-J-999902','SUBMITTED',now());

  insert into finance.revenue(revenue_id,transaction_date,client_id,placement_id,revenue_type,gross,wht,status,invoice_no,invoice_date,due_date,created_by) values
    ('P7B-REV-A',current_date,'MYC-B2B-9993','MYC-PL-999901','PLACEMENT',1000,0,'INVOICED','P7B-INV-A',current_date,current_date+7,'PART7B_SMOKE'),
    ('P7B-REV-B',current_date,'MYC-B2B-9992','MYC-PL-999902','PLACEMENT',1100,0,'INVOICED','P7B-INV-B',current_date,current_date+7,'PART7B_SMOKE');
  insert into finance.accounts_receivable(ar_id,client_id,placement_id,revenue_id,invoice_no,invoice_date,due_date,gross_amount,deduction,collected,next_action) values
    ('MYC-AR-999901','MYC-B2B-9993','MYC-PL-999901','P7B-REV-A','P7B-INV-A',current_date,current_date+7,1000,0,0,'TEST'),
    ('MYC-AR-999902','MYC-B2B-9992','MYC-PL-999902','P7B-REV-B','P7B-INV-B',current_date,current_date+7,1100,0,0,'TEST');
  insert into finance.commissions(commission_id,partner_id,placement_id,revenue_id,milestone,commission_amount,state,created_by) values
    ('P7B-COM-A','MYC-P-9996','MYC-PL-999901','P7B-REV-A','STARTED',250,'PENDING','PART7B_SMOKE'),
    ('P7B-COM-B','MYC-P-9995','MYC-PL-999902','P7B-REV-B','STARTED',250,'PENDING','PART7B_SMOKE');

  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9993','ACTIVE') returning org_id into org_client_a;
  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9992','ACTIVE') returning org_id into org_client_b;
  insert into authz.organizations(org_type,business_party_id,status) values('PARTNER','MYC-P-9996','ACTIVE') returning org_id into org_partner_a;
  insert into authz.organizations(org_type,business_party_id,status) values('PARTNER','MYC-P-9995','ACTIVE') returning org_id into org_partner_b;

  insert into auth.users(id) values(u_portal),(u_candidate_a),(u_candidate_b);
  insert into authz.organization_members(org_id,auth_user_id,portal_role,membership_status,active_from,created_by) values
    (org_client_a,u_portal,'client_admin','ACTIVE',now()-interval '1 minute','PART7B_SMOKE'),
    (org_partner_a,u_portal,'partner_admin','ACTIVE',now()-interval '1 minute','PART7B_SMOKE');
  insert into authz.candidate_user_links(auth_user_id,candidate_id,verification_status,verified_by,verified_at) values
    (u_candidate_a,'MYC-C-999901','VERIFIED','PART7B_SMOKE',now()),
    (u_candidate_b,'MYC-C-999902','VERIFIED','PART7B_SMOKE',now());

  insert into authz.client_candidate_purpose_access(org_id,placement_id,candidate_id,purpose,access_status,valid_from,valid_until,granted_by,evidence_ref) values
    (org_client_a,'MYC-PL-999901','MYC-C-999901','RECRUITMENT_SUBMISSION','ACTIVE',now()-interval '1 minute',now()+interval '7 days','PART7B_SMOKE','P7B-A'),
    (org_client_b,'MYC-PL-999902','MYC-C-999902','RECRUITMENT_SUBMISSION','ACTIVE',now()-interval '1 minute',now()+interval '7 days','PART7B_SMOKE','P7B-B');

  perform set_config('request.jwt.claim.sub',u_candidate_a::text,true); execute 'set local role authenticated';
  select count(*),min(candidate_id) into v_count,v_text from api.portal_candidate_self_profile();
  if v_count<>1 or v_text<>'MYC-C-999901' then raise exception 'P7B-001_FAILED'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',u_portal::text,true); execute 'set local role authenticated';
  select count(*) into v_count from api.portal_partner_referral_status(org_partner_a) where candidate_id='MYC-C-999901';
  if v_count<>1 then raise exception 'P7B-002_FAILED_OWN'; end if;
  if exists(select 1 from api.portal_partner_referral_status(org_partner_a) where candidate_id='MYC-C-999902') then raise exception 'P7B-002_FAILED_LEAK'; end if;
  select count(*),min(commission_id) into v_count,v_text from api.portal_partner_commission_status(org_partner_a);
  if v_count<>1 or v_text<>'P7B-COM-A' then raise exception 'P7B-003_FAILED'; end if;
  v_failed:=false;
  begin perform 1 from api.portal_partner_referral_status(org_partner_b) limit 1; exception when others then if position('ORG_MEMBERSHIP_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7B-002_FAILED_CROSS_ORG'; end if;

  select count(*),min(job_id) into v_count,v_text from api.portal_client_jobs(org_client_a);
  if v_count<>1 or v_text<>'MYC-J-999901' then raise exception 'P7B-004_FAILED'; end if;
  select count(*),min(candidate_id) into v_count,v_text from api.portal_client_candidate_submissions(org_client_a);
  if v_count<>1 or v_text<>'MYC-C-999901' then raise exception 'P7B-005_FAILED_ACTIVE'; end if;
  select count(*),min(ar_id) into v_count,v_text from api.portal_client_invoices(org_client_a);
  if v_count<>1 or v_text<>'MYC-AR-999901' then raise exception 'P7B-006_FAILED'; end if;
  v_failed:=false;
  begin perform 1 from api.portal_client_jobs(org_client_b) limit 1; exception when others then if position('ORG_MEMBERSHIP_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7B-008_FAILED_CLIENT_ORG_SPOOF'; end if;
  execute 'reset role';

  update authz.client_candidate_purpose_access set access_status='REVOKED',revoked_at=now(),revoked_by='PART7B_SMOKE',updated_at=now() where org_id=org_client_a and placement_id='MYC-PL-999901';
  perform set_config('request.jwt.claim.sub',u_portal::text,true); execute 'set local role authenticated';
  select count(*) into v_count from api.portal_client_candidate_submissions(org_client_a);
  if v_count<>0 then raise exception 'P7B-005_FAILED_REVOKED_PURPOSE'; end if;
  execute 'reset role';
  update authz.client_candidate_purpose_access set access_status='ACTIVE',revoked_at=null,revoked_by=null,updated_at=now() where org_id=org_client_a and placement_id='MYC-PL-999901';

  update authz.organization_members set membership_status='REMOVED',removed_at=now(),updated_by='PART7B_SMOKE',updated_at=now() where org_id=org_client_a and auth_user_id=u_portal;
  perform set_config('request.jwt.claim.sub',u_portal::text,true); execute 'set local role authenticated';
  v_failed:=false;
  begin perform 1 from api.portal_client_jobs(org_client_a) limit 1; exception when others then if position('ORG_MEMBERSHIP_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7B-007_FAILED_STALE_MEMBER'; end if;
  execute 'reset role';
  update authz.organization_members set membership_status='ACTIVE',removed_at=null,active_from=now()-interval '1 minute',updated_by='PART7B_SMOKE',updated_at=now() where org_id=org_client_a and auth_user_id=u_portal;

  select pg_get_function_result(p.oid) into v_result from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='api' and p.proname='portal_client_candidate_submissions';
  if position('partner_id' in lower(v_result))>0 or position('source_type' in lower(v_result))>0 or position('notes' in lower(v_result))>0 or position('dropout_reason' in lower(v_result))>0 then
    raise exception 'P7B-010_FAILED_MINIMUM_PROJECTION';
  end if;

  perform set_config('request.jwt.claim.sub','',true); execute 'set local role anon';
  v_failed:=false;
  begin perform 1 from api.portal_client_jobs(org_client_a) limit 1; exception when insufficient_privilege then v_failed:=true; when others then if position('permission denied' in lower(sqlerrm))>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7B-009_FAILED_ANON_EXECUTE'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',u_portal::text,true); execute 'set local role authenticated';
  v_failed:=false;
  begin execute 'select count(*) from core.candidates' into v_count; exception when insufficient_privilege then v_failed:=true; when others then if position('permission denied' in lower(sqlerrm))>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7B-010_FAILED_FULL_MASTER_DIRECT_ACCESS'; end if;
  execute 'reset role';

  update ops.part7b_acceptance_catalog set status='PASS',evidence_ref='part7_wave7b_cross_scope_projection_acceptance_smoke',last_tested_at=now(),updated_at=now();
  update ops.portal_acceptance_catalog set status='PASS',evidence_ref='part7_wave7b_cross_scope_projection_acceptance_smoke',last_tested_at=now(),updated_at=now()
   where test_id in ('PT-001','PT-002','PT-004','PT-007','PT-008','PT-012','PT-013');

  delete from finance.accounts_receivable where ar_id in ('MYC-AR-999901','MYC-AR-999902');
  delete from finance.commissions where commission_id in ('P7B-COM-A','P7B-COM-B');
  delete from authz.client_candidate_purpose_access where placement_id in ('MYC-PL-999901','MYC-PL-999902');
  delete from finance.revenue where revenue_id in ('P7B-REV-A','P7B-REV-B');
  delete from core.placements where placement_id in ('MYC-PL-999901','MYC-PL-999902');
  delete from core.jobs where job_id in ('MYC-J-999901','MYC-J-999902');
  delete from authz.candidate_user_links where candidate_id in ('MYC-C-999901','MYC-C-999902');
  delete from core.candidates where candidate_id in ('MYC-C-999901','MYC-C-999902');
  delete from authz.organization_members where auth_user_id=u_portal;
  delete from authz.organizations where org_id in (org_client_a,org_client_b,org_partner_a,org_partner_b);
  delete from core.partners where partner_id in ('MYC-P-9996','MYC-P-9995');
  delete from core.clients where client_id in ('MYC-B2B-9993','MYC-B2B-9992');
  delete from auth.users where id in (u_portal,u_candidate_a,u_candidate_b);

  update config.system_settings set setting_value=coalesce(old_external,'false'::jsonb),updated_at=now() where setting_key='portal_external_access_enabled';
  update config.system_settings set setting_value=coalesce(old_candidate,'false'::jsonb),updated_at=now() where setting_key='portal_candidate_enabled';
  update config.system_settings set setting_value=coalesce(old_partner,'false'::jsonb),updated_at=now() where setting_key='portal_partner_enabled';
  update config.system_settings set setting_value=coalesce(old_client,'false'::jsonb),updated_at=now() where setting_key='portal_client_enabled';
end
$smoke$;