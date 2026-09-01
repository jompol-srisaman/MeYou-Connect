do $smoke$
declare
  u_client_finance uuid:=gen_random_uuid();
  u_partner_admin uuid:=gen_random_uuid();
  u_invited_ok uuid:=gen_random_uuid();
  u_invited_blocked uuid:=gen_random_uuid();
  u_support uuid:=gen_random_uuid();
  u_unauthorized uuid:=gen_random_uuid();
  org_client_a uuid; org_client_b uuid; org_partner_a uuid; org_partner_b uuid;
  req_pay uuid:=gen_random_uuid(); req_pay_cross uuid:=gen_random_uuid();
  req_invite uuid:=gen_random_uuid(); req_invite_aal1 uuid:=gen_random_uuid(); req_invite_cross uuid:=gen_random_uuid(); req_invite_blocked uuid:=gen_random_uuid();
  req_support uuid:=gen_random_uuid(); req_support_aal1 uuid:=gen_random_uuid(); req_support_unauth uuid:=gen_random_uuid();
  v_pay jsonb; v_inv jsonb; v_sup jsonb; v_tmp jsonb;
  ev_inv uuid; ev_inv_blocked uuid; ev_sup uuid;
  raw_pay text; raw_inv text; raw_inv_blocked text; raw_sup text;
  run_inv uuid; lease_inv uuid; cmd_inv uuid;
  run_inv_blocked uuid; lease_inv_blocked uuid; cmd_inv_blocked uuid;
  run_sup uuid; lease_sup uuid; cmd_sup uuid;
  security_pk uuid;
  v_count integer; v_text text; v_num numeric; v_failed boolean;
  old_external jsonb; old_client jsonb; old_partner jsonb;
  old_pay_enabled boolean; old_pay_by text; old_pay_at timestamptz;
  old_member_enabled boolean; old_member_by text; old_member_at timestamptz;
begin
  if exists(select 1 from ops.events where event_type in ('portal.organization.member_invite.requested','portal.internal.support_access.recorded')) then
    raise exception 'P7D_PREEXISTING_PROTECTED_EVENTS_PRESENT';
  end if;

  select setting_value into old_external from config.system_settings where setting_key='portal_external_access_enabled';
  select setting_value into old_client from config.system_settings where setting_key='portal_client_enabled';
  select setting_value into old_partner from config.system_settings where setting_key='portal_partner_enabled';
  select enabled,enabled_by,enabled_at into old_pay_enabled,old_pay_by,old_pay_at
    from ops.portal_feature_flags where feature_key='client_payment_evidence_upload' and environment='TEST' and org_id is null and service_area_id is null limit 1;
  select enabled,enabled_by,enabled_at into old_member_enabled,old_member_by,old_member_at
    from ops.portal_feature_flags where feature_key='partner_member_manage' and environment='TEST' and org_id is null and service_area_id is null limit 1;

  update config.system_settings set setting_value='true'::jsonb,updated_at=now()
   where setting_key in ('portal_external_access_enabled','portal_client_enabled','portal_partner_enabled');
  update ops.portal_feature_flags set enabled=true,enabled_by='PART7D_SMOKE',enabled_at=now(),updated_at=now()
   where feature_key in ('client_payment_evidence_upload','partner_member_manage') and environment='TEST' and org_id is null and service_area_id is null;

  delete from finance.accounts_receivable where ar_id in ('MYC-AR-999921','MYC-AR-999922');
  delete from finance.revenue where revenue_id in ('P7D-REV-A','P7D-REV-B');
  delete from authz.organization_members where org_id in (select org_id from authz.organizations where business_party_id in ('MYC-B2B-9971','MYC-B2B-9972','MYC-P-9971','MYC-P-9972'));
  delete from authz.organizations where business_party_id in ('MYC-B2B-9971','MYC-B2B-9972','MYC-P-9971','MYC-P-9972');
  delete from core.clients where client_id in ('MYC-B2B-9971','MYC-B2B-9972');
  delete from core.partners where partner_id in ('MYC-P-9971','MYC-P-9972');

  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status) values
    ('MYC-B2B-9971','TEST','Part7D Client A','TEST','ACTIVE','VERIFIED'),
    ('MYC-B2B-9972','TEST','Part7D Client B','TEST','ACTIVE','VERIFIED');
  insert into core.partners(partner_id,partner_name,partner_type,province,status) values
    ('MYC-P-9971','Part7D Partner A','TEST','TEST','ACTIVE'),
    ('MYC-P-9972','Part7D Partner B','TEST','TEST','ACTIVE');
  insert into finance.revenue(revenue_id,transaction_date,client_id,revenue_type,gross,wht,status,invoice_no,invoice_date,due_date,created_by) values
    ('P7D-REV-A',current_date,'MYC-B2B-9971','PLACEMENT',1000,0,'INVOICED','P7D-INV-A',current_date,current_date+7,'PART7D_SMOKE'),
    ('P7D-REV-B',current_date,'MYC-B2B-9972','PLACEMENT',1200,0,'INVOICED','P7D-INV-B',current_date,current_date+7,'PART7D_SMOKE');
  insert into finance.accounts_receivable(ar_id,client_id,revenue_id,invoice_no,invoice_date,due_date,gross_amount,deduction,collected,next_action) values
    ('MYC-AR-999921','MYC-B2B-9971','P7D-REV-A','P7D-INV-A',current_date,current_date+7,1000,0,0,'WAIT_PAYMENT'),
    ('MYC-AR-999922','MYC-B2B-9972','P7D-REV-B','P7D-INV-B',current_date,current_date+7,1200,0,0,'WAIT_PAYMENT');

  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9971','ACTIVE') returning org_id into org_client_a;
  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9972','ACTIVE') returning org_id into org_client_b;
  insert into authz.organizations(org_type,business_party_id,status) values('PARTNER','MYC-P-9971','ACTIVE') returning org_id into org_partner_a;
  insert into authz.organizations(org_type,business_party_id,status) values('PARTNER','MYC-P-9972','ACTIVE') returning org_id into org_partner_b;

  insert into auth.users(id) values(u_client_finance),(u_partner_admin),(u_invited_ok),(u_invited_blocked),(u_support),(u_unauthorized);
  insert into authz.user_profiles(auth_user_id,display_name,status) values
    (u_support,'Part7D Support','ACTIVE'),(u_unauthorized,'Part7D Unauthorized','ACTIVE')
  on conflict(auth_user_id) do update set status='ACTIVE',updated_at=now();
  insert into authz.user_roles(auth_user_id,role_key,active,assigned_by,reason) values
    (u_support,'secretary',true,'PART7D_SMOKE','PT-014 support acceptance');
  insert into authz.organization_members(org_id,auth_user_id,portal_role,membership_status,active_from,created_by) values
    (org_client_a,u_client_finance,'client_finance','ACTIVE',now()-interval '1 minute','PART7D_SMOKE'),
    (org_partner_a,u_partner_admin,'partner_admin','ACTIVE',now()-interval '1 minute','PART7D_SMOKE');

  perform set_config('request.jwt.claim.sub',u_client_finance::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_client_finance::text,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  select api.portal_client_submit_payment_evidence(req_pay,org_client_a,'MYC-AR-999921','provider://p7d/payment-a','payment-a.pdf','application/pdf',1234,repeat('a',64)) into v_pay;
  if v_pay->>'request_status'<>'REVIEW_REQUIRED' or coalesce((v_pay->>'finance_state_changed')::boolean,true) then raise exception 'P7D-005_PAYMENT_EVIDENCE_CONTRACT_FAILED'; end if;
  v_failed:=false;
  begin perform api.portal_client_submit_payment_evidence(req_pay_cross,org_client_a,'MYC-AR-999922','provider://p7d/payment-b','payment-b.pdf','application/pdf',100,repeat('b',64));
  exception when others then if position('AR_NOT_OWNED_BY_CLIENT_ORG' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7D-006_CROSS_CLIENT_AR_NOT_DENIED'; end if;
  v_failed:=false;
  begin execute 'update finance.accounts_receivable set collected=1000 where ar_id=''MYC-AR-999921'''; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'P7D-006_DIRECT_AR_COLLECTED_UPDATE_NOT_DENIED'; end if;
  v_failed:=false;
  begin execute 'update finance.revenue set status=''COLLECTED'',collection_date=current_date,net_received=1000 where revenue_id=''P7D-REV-A'''; exception when others then v_failed:=true; end;
  if not v_failed then raise exception 'P7D-006_DIRECT_REVENUE_COLLECTED_UPDATE_NOT_DENIED'; end if;
  execute 'reset role';
  raw_pay:=v_pay->>'raw_input_id';
  if (select collected from finance.accounts_receivable where ar_id='MYC-AR-999921')<>0 then raise exception 'P7D-005_AR_COLLECTED_CHANGED'; end if;
  if (select status from finance.revenue where revenue_id='P7D-REV-A')<>'INVOICED' then raise exception 'P7D-005_REVENUE_STATE_CHANGED'; end if;
  if not exists(select 1 from ops.file_intake f where f.raw_input_id=raw_pay and f.provider_file_ref='provider://p7d/payment-a' and f.sensitive=true and f.metadata->>'storage_profile'='evidence-private') then raise exception 'P7D-005_FILE_INTAKE_MISSING'; end if;
  if not exists(select 1 from ops.events e where e.event_pk=(v_pay->>'event_pk')::uuid and e.event_type='finance.payment_evidence.received' and e.raw_input_id=raw_pay) then raise exception 'P7D-005_PAYMENT_EVENT_MISSING'; end if;
  if not exists(select 1 from ops.portal_action_requests r where r.request_id=req_pay and r.org_id=org_client_a and r.target_entity_id='MYC-AR-999921' and r.request_status='REVIEW_REQUIRED') then raise exception 'P7D-005_PAYMENT_ACTION_MISSING'; end if;

  perform set_config('request.jwt.claim.sub',u_partner_admin::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_partner_admin::text,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  v_failed:=false;
  begin perform api.portal_partner_invite_member(req_invite_aal1,org_partner_a,u_invited_ok);
  exception when others then if position('STEP_UP_AAL2_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7D-001_AAL1_PARTNER_NOT_DENIED'; end if;
  execute 'reset role';
  if exists(select 1 from ops.portal_action_requests where request_id=req_invite_aal1) then raise exception 'P7D-001_AAL1_REQUEST_PERSISTED'; end if;

  perform set_config('request.jwt.claim.sub',u_partner_admin::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_partner_admin::text,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  select api.portal_partner_invite_member(req_invite,org_partner_a,u_invited_ok) into v_inv;
  if v_inv->>'request_status'<>'ACCEPTED' or v_inv->>'portal_role'<>'partner_member' then raise exception 'P7D-002_INVITE_INGRESS_FAILED'; end if;
  v_failed:=false;
  begin perform api.portal_partner_invite_member(req_invite_cross,org_partner_b,u_invited_blocked);
  exception when others then if position('PARTNER_ADMIN_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7D-003_CROSS_ORG_INVITE_NOT_DENIED'; end if;
  execute 'reset role';
  ev_inv:=(v_inv->>'event_pk')::uuid; raw_inv:=v_inv->>'raw_input_id';

  select c.worker_run_pk,c.lease_token into run_inv,lease_inv
    from ops.claim_events('portal_org_membership_worker','PART7D_SMOKE',1,300,now()) c where c.event_pk=ev_inv;
  if run_inv is null then raise exception 'P7D-004_INVITE_WORKER_CLAIM_FAILED'; end if;
  select ops.prepare_domain_command(ev_inv,'portal_org_membership_worker',lease_inv,jsonb_build_object('invited_auth_user_id',u_invited_ok,'portal_role','partner_member'),'OrganizationMember',u_invited_ok::text) into v_tmp;
  if v_tmp->>'validation_status'<>'VALID' or v_tmp->>'apply_status'<>'READY' then raise exception 'P7D-004_INVITE_COMMAND_INVALID:%',v_tmp; end if;
  cmd_inv:=(v_tmp->>'command_pk')::uuid;
  select ops.apply_portal_org_member_invite_command(cmd_inv,lease_inv,'PART7D_SMOKE') into v_tmp;
  if v_tmp->>'apply_status'<>'APPLIED' or v_tmp->>'membership_status'<>'INVITED' then raise exception 'P7D-004_INVITE_APPLY_FAILED:%',v_tmp; end if;
  if not exists(select 1 from authz.organization_members where org_id=org_partner_a and auth_user_id=u_invited_ok and portal_role='partner_member' and membership_status='INVITED' and invited_at is not null and active_from is null) then raise exception 'P7D-004_INVITED_MEMBERSHIP_NOT_CREATED'; end if;

  perform set_config('request.jwt.claim.sub',u_partner_admin::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_partner_admin::text,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  select api.portal_partner_invite_member(req_invite_blocked,org_partner_a,u_invited_blocked) into v_inv;
  execute 'reset role';
  ev_inv_blocked:=(v_inv->>'event_pk')::uuid; raw_inv_blocked:=v_inv->>'raw_input_id';
  update authz.organization_members set membership_status='REMOVED',removed_at=now(),updated_by='PART7D_SMOKE',updated_at=now() where org_id=org_partner_a and auth_user_id=u_partner_admin;
  select c.worker_run_pk,c.lease_token into run_inv_blocked,lease_inv_blocked
    from ops.claim_events('portal_org_membership_worker','PART7D_SMOKE',1,300,now()) c where c.event_pk=ev_inv_blocked;
  if run_inv_blocked is null then raise exception 'P7D-004_REVOKED_WORKER_CLAIM_FAILED'; end if;
  select ops.prepare_domain_command(ev_inv_blocked,'portal_org_membership_worker',lease_inv_blocked,jsonb_build_object('invited_auth_user_id',u_invited_blocked,'portal_role','partner_member'),'OrganizationMember',u_invited_blocked::text) into v_tmp;
  cmd_inv_blocked:=(v_tmp->>'command_pk')::uuid;
  select ops.apply_portal_org_member_invite_command(cmd_inv_blocked,lease_inv_blocked,'PART7D_SMOKE') into v_tmp;
  if v_tmp->>'apply_status'<>'BLOCKED' or v_tmp->>'reason'<>'PARTNER_ADMIN_MEMBERSHIP_NOT_ACTIVE' then raise exception 'P7D-004_REVOKED_ADMIN_NOT_BLOCKED:%',v_tmp; end if;
  if exists(select 1 from authz.organization_members where org_id=org_partner_a and auth_user_id=u_invited_blocked) then raise exception 'P7D-004_BLOCKED_INVITE_CREATED_MEMBERSHIP'; end if;
  update authz.organization_members set membership_status='ACTIVE',removed_at=null,active_from=now()-interval '1 minute',updated_by='PART7D_SMOKE',updated_at=now() where org_id=org_partner_a and auth_user_id=u_partner_admin;

  perform set_config('request.jwt.claim.sub',u_support::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_support::text,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  v_failed:=false;
  begin perform api.request_portal_support_access(req_support_aal1,req_pay,'AAL1 should fail');
  exception when others then if position('STEP_UP_AAL2_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7D-008_SUPPORT_AAL1_NOT_DENIED'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',u_unauthorized::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_unauthorized::text,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  v_failed:=false;
  begin perform api.request_portal_support_access(req_support_unauth,req_pay,'Unauthorized should fail');
  exception when others then if position('ACCESS_DENIED:portal_support_access' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7D-008_UNAUTHORIZED_SUPPORT_NOT_DENIED'; end if;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',u_support::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_support::text,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  select api.request_portal_support_access(req_support,req_pay,'Investigate payment evidence support case') into v_sup;
  if v_sup->>'request_status'<>'ACCEPTED' or coalesce((v_sup->>'access_granted')::boolean,true) then raise exception 'P7D-007_SUPPORT_REQUEST_CONTRACT_FAILED'; end if;
  v_failed:=false;
  begin perform 1 from api.portal_support_action_request(req_pay) limit 1;
  exception when others then if position('ACTIVE_SUPPORT_ACCESS_GRANT_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7D-007_SUPPORT_READ_ALLOWED_BEFORE_GRANT'; end if;
  execute 'reset role';
  ev_sup:=(v_sup->>'event_pk')::uuid; raw_sup:=v_sup->>'raw_input_id';

  select c.worker_run_pk,c.lease_token into run_sup,lease_sup
    from ops.claim_events('portal_support_audit_worker','PART7D_SMOKE',1,300,now()) c where c.event_pk=ev_sup;
  if run_sup is null then raise exception 'P7D-007_SUPPORT_WORKER_CLAIM_FAILED'; end if;
  select ops.prepare_domain_command(ev_sup,'portal_support_audit_worker',lease_sup,jsonb_build_object('target_portal_request_id',req_pay,'reason','Investigate payment evidence support case'),'PortalSupportAccess',req_pay::text) into v_tmp;
  if v_tmp->>'validation_status'<>'VALID' or v_tmp->>'apply_status'<>'READY' then raise exception 'P7D-007_SUPPORT_COMMAND_INVALID:%',v_tmp; end if;
  cmd_sup:=(v_tmp->>'command_pk')::uuid;
  select ops.apply_portal_support_access_command(cmd_sup,lease_sup,'PART7D_SMOKE') into v_tmp;
  if v_tmp->>'apply_status'<>'APPLIED' then raise exception 'P7D-007_SUPPORT_APPLY_FAILED:%',v_tmp; end if;
  security_pk:=(v_tmp->>'security_event_pk')::uuid;
  if not exists(select 1 from ops.portal_support_access_audit a where a.request_id=req_support and a.auth_user_id=u_support and a.target_portal_request_id=req_pay and a.aal='aal2' and a.access_status='GRANTED' and a.valid_until>a.granted_at) then raise exception 'P7D-007_SUPPORT_AUDIT_GRANT_MISSING'; end if;
  if not exists(select 1 from ops.security_events s where s.security_event_pk=security_pk and s.event_type='PORTAL_SUPPORT_ACCESS_GRANTED' and s.result='GRANTED' and s.status='CLOSED') then raise exception 'P7D-007_SECURITY_EVENT_MISSING'; end if;

  perform set_config('request.jwt.claim.sub',u_support::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_support::text,'role','authenticated','aal','aal2')::text,true);
  execute 'set local role authenticated';
  select count(*),min(request_id::text) into v_count,v_text from api.portal_support_action_request(req_pay);
  if v_count<>1 or v_text<>req_pay::text then raise exception 'P7D-007_SCOPED_SUPPORT_READ_FAILED'; end if;
  execute 'reset role';

  update ops.part7d_acceptance_catalog set status='PASS',evidence_ref='part7_wave7d_protected_controls_acceptance_smoke',last_tested_at=now(),updated_at=now();
  update ops.portal_acceptance_catalog set status='PASS',evidence_ref='part7_wave7d_protected_controls_acceptance_smoke',last_tested_at=now(),updated_at=now()
   where test_id in ('PT-006','PT-009','PT-014');

  delete from ops.portal_support_access_audit where request_id=req_support;
  delete from ops.security_events where security_event_pk=security_pk;
  delete from ops.domain_command_apply_audit where command_pk in (cmd_inv,cmd_inv_blocked,cmd_sup);
  delete from ops.domain_commands where command_pk in (cmd_inv,cmd_inv_blocked,cmd_sup);
  delete from ops.event_effects where event_pk in (ev_inv,ev_inv_blocked,ev_sup);
  delete from ops.worker_runs where worker_run_pk in (run_inv,run_inv_blocked,run_sup);
  delete from authz.organization_members where (org_id=org_partner_a and auth_user_id in (u_invited_ok,u_invited_blocked,u_partner_admin)) or (org_id=org_client_a and auth_user_id=u_client_finance);
  delete from ops.portal_action_requests where request_id in (req_pay,req_invite,req_invite_blocked,req_support);
  delete from ops.file_intake where raw_input_id=raw_pay;
  delete from ops.events where event_pk in ((v_pay->>'event_pk')::uuid,ev_inv,ev_inv_blocked,ev_sup);
  delete from ops.raw_inputs where raw_input_id in (raw_pay,raw_inv,raw_inv_blocked,raw_sup);
  delete from config.id_allocation_audit where allocated_id in (raw_pay,raw_inv,raw_inv_blocked,raw_sup);
  delete from finance.accounts_receivable where ar_id in ('MYC-AR-999921','MYC-AR-999922');
  delete from finance.revenue where revenue_id in ('P7D-REV-A','P7D-REV-B');
  delete from authz.organizations where org_id in (org_client_a,org_client_b,org_partner_a,org_partner_b);
  delete from core.clients where client_id in ('MYC-B2B-9971','MYC-B2B-9972');
  delete from core.partners where partner_id in ('MYC-P-9971','MYC-P-9972');
  delete from authz.user_roles where auth_user_id=u_support and role_key='secretary';
  delete from auth.users where id in (u_client_finance,u_partner_admin,u_invited_ok,u_invited_blocked,u_support,u_unauthorized);

  update config.system_settings set setting_value=coalesce(old_external,'false'::jsonb),updated_at=now() where setting_key='portal_external_access_enabled';
  update config.system_settings set setting_value=coalesce(old_client,'false'::jsonb),updated_at=now() where setting_key='portal_client_enabled';
  update config.system_settings set setting_value=coalesce(old_partner,'false'::jsonb),updated_at=now() where setting_key='portal_partner_enabled';
  update ops.portal_feature_flags set enabled=coalesce(old_pay_enabled,false),enabled_by=old_pay_by,enabled_at=old_pay_at,updated_at=now()
    where feature_key='client_payment_evidence_upload' and environment='TEST' and org_id is null and service_area_id is null;
  update ops.portal_feature_flags set enabled=coalesce(old_member_enabled,false),enabled_by=old_member_by,enabled_at=old_member_at,updated_at=now()
    where feature_key='partner_member_manage' and environment='TEST' and org_id is null and service_area_id is null;
end
$smoke$;