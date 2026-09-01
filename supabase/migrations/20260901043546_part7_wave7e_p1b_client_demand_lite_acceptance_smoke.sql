do $smoke$
declare
  u_client uuid:=gen_random_uuid();
  org_a uuid; org_b uuid;
  req_a uuid:=gen_random_uuid();
  req_cross uuid:=gen_random_uuid();
  v_res jsonb; v_dup jsonb; v_tmp jsonb;
  ev_a uuid; raw_a text;
  run_a uuid; lease_a uuid; cmd_a uuid;
  v_failed boolean; v_count integer; v_text text;
  old_external jsonb; old_client jsonb;
begin
  if exists(select 1 from ops.events where event_type='portal.client.job_demand.submitted') then raise exception 'P7E_PREEXISTING_PILOT_EVENTS_PRESENT'; end if;
  select setting_value into old_external from config.system_settings where setting_key='portal_external_access_enabled';
  select setting_value into old_client from config.system_settings where setting_key='portal_client_enabled';
  update config.system_settings set setting_value='true'::jsonb,updated_at=now() where setting_key in ('portal_external_access_enabled','portal_client_enabled');

  insert into core.clients(client_id,client_type,company_name,province,crm_status,verification_status) values
    ('MYC-B2B-9961','TEST','Part7E Client A','TEST','ACTIVE','VERIFIED'),
    ('MYC-B2B-9962','TEST','Part7E Client B','TEST','ACTIVE','VERIFIED');
  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9961','ACTIVE') returning org_id into org_a;
  insert into authz.organizations(org_type,business_party_id,status) values('CLIENT','MYC-B2B-9962','ACTIVE') returning org_id into org_b;
  insert into auth.users(id) values(u_client);
  insert into authz.organization_members(org_id,auth_user_id,portal_role,membership_status,active_from,created_by)
  values(org_a,u_client,'client_recruiter','ACTIVE',now()-interval '1 minute','PART7E_SMOKE');

  perform set_config('request.jwt.claim.sub',u_client::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_client::text,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  v_failed:=false;
  begin
    perform api.portal_client_submit_job_demand(req_a,org_a,'Factory A','สระบุรี','หนองแค','Production',12,'357 บาท/วัน','กะ','2026-09-15','ม.3 ขึ้นไป','บัตรประชาชน','smoke');
  exception when others then
    if position('PORTAL_FEATURE_DISABLED:client_demand_submit' in sqlerrm)>0 then v_failed:=true; else raise; end if;
  end;
  if not v_failed then raise exception 'P7E-001_FEATURE_OFF_NOT_DENIED'; end if;
  execute 'reset role';

  insert into ops.portal_feature_flags(feature_key,rollout_wave,environment,org_id,enabled,enabled_by,enabled_at,config)
  values
    ('client_demand_submit','P1B','TEST',org_a,true,'PART7E_SMOKE',now(),jsonb_build_object('pilot_cohort','P1B_SMOKE')),
    ('client_demand_submit','P1B','TEST',org_b,true,'PART7E_SMOKE',now(),jsonb_build_object('pilot_cohort','P1B_SMOKE'));

  perform set_config('request.jwt.claim.sub',u_client::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_client::text,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  select api.portal_client_submit_job_demand(req_a,org_a,'Factory A','สระบุรี','หนองแค','Production',12,'357 บาท/วัน','Day/Night','2026-09-15','ม.3 ขึ้นไป','บัตรประชาชน','smoke demand') into v_res;
  if v_res->>'request_status'<>'REVIEW_REQUIRED' or coalesce((v_res->>'master_job_changed')::boolean,true) then raise exception 'P7E-002_004_INGRESS_CONTRACT_FAILED:%',v_res; end if;
  select api.portal_client_submit_job_demand(req_a,org_a,'Factory A','สระบุรี','หนองแค','Production',12,'357 บาท/วัน','Day/Night','2026-09-15','ม.3 ขึ้นไป','บัตรประชาชน','smoke demand') into v_dup;
  if coalesce((v_dup->>'duplicate_request')::boolean,false)<>true then raise exception 'P7E-006_IDEMPOTENCY_FAILED'; end if;
  v_failed:=false;
  begin
    perform api.portal_client_submit_job_demand(req_cross,org_b,'Factory B','อยุธยา','บางปะอิน','Operator',5,null,null,null,null,null,null);
  exception when others then
    if position('ACTIVE_ORG_MEMBERSHIP_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if;
  end;
  if not v_failed then raise exception 'P7E-003_CROSS_CLIENT_NOT_DENIED'; end if;

  v_failed:=false;
  begin perform 1 from api.portal_client_candidate_submissions(org_a) limit 1;
  exception when others then if position('PORTAL_FEATURE_DISABLED:client_candidate_status' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7E-008_CANDIDATE_STATUS_FLAG_NOT_ENFORCED'; end if;
  execute 'reset role';

  ev_a:=(v_res->>'event_pk')::uuid; raw_a:=v_res->>'raw_input_id';
  if exists(select 1 from core.jobs where client_id in ('MYC-B2B-9961','MYC-B2B-9962')) then raise exception 'P7E-004_JOB_MASTER_CHANGED_AT_INGRESS'; end if;
  if not exists(select 1 from ops.events where event_pk=ev_a and event_type='portal.client.job_demand.submitted' and raw_input_id=raw_a) then raise exception 'P7E-004_EVENT_MISSING'; end if;
  if not exists(select 1 from ops.portal_action_requests where request_id=req_a and org_id=org_a and request_status='REVIEW_REQUIRED') then raise exception 'P7E-004_PORTAL_REQUEST_MISSING'; end if;

  select c.worker_run_pk,c.lease_token into run_a,lease_a from ops.claim_events('portal_client_demand_review_worker','PART7E_SMOKE',1,300,now()) c where c.event_pk=ev_a;
  if run_a is null then raise exception 'P7E-005_WORKER_CLAIM_FAILED'; end if;
  select ops.prepare_domain_command(ev_a,'portal_client_demand_review_worker',lease_a,jsonb_build_object('request_id',req_a,'review_only',true),'ClientDemandReview',req_a::text) into v_tmp;
  if v_tmp->>'validation_status'<>'VALID' or v_tmp->>'apply_status'<>'READY' then raise exception 'P7E-005_COMMAND_INVALID:%',v_tmp; end if;
  cmd_a:=(v_tmp->>'command_pk')::uuid;
  select ops.apply_portal_client_demand_review_command(cmd_a,lease_a,'PART7E_SMOKE') into v_tmp;
  if v_tmp->>'apply_status'<>'APPLIED' or v_tmp->>'review_status'<>'PENDING_REVIEW' or coalesce((v_tmp->>'job_master_changed')::boolean,true) then raise exception 'P7E-005_REVIEW_APPLY_FAILED:%',v_tmp; end if;
  if not exists(select 1 from ops.client_demand_review_queue where request_id=req_a and org_id=org_a and client_id='MYC-B2B-9961' and review_status='PENDING_REVIEW') then raise exception 'P7E-005_REVIEW_QUEUE_MISSING'; end if;
  if exists(select 1 from core.jobs where client_id in ('MYC-B2B-9961','MYC-B2B-9962')) then raise exception 'P7E-005_JOB_MASTER_CHANGED_AT_WORKER'; end if;

  perform set_config('request.jwt.claim.sub',u_client::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',u_client::text,'role','authenticated','aal','aal1')::text,true);
  execute 'set local role authenticated';
  select count(*),min(request_id::text) into v_count,v_text from api.portal_client_demand_requests(org_a);
  if v_count<>1 or v_text<>req_a::text then raise exception 'P7E-007_OWN_ORG_PROJECTION_FAILED'; end if;
  v_failed:=false;
  begin perform 1 from api.portal_client_demand_requests(org_b) limit 1;
  exception when others then if position('ACTIVE_ORG_MEMBERSHIP_REQUIRED' in sqlerrm)>0 then v_failed:=true; else raise; end if; end;
  if not v_failed then raise exception 'P7E-007_CROSS_ORG_PROJECTION_NOT_DENIED'; end if;
  execute 'reset role';

  update ops.part7e_acceptance_catalog set status='PASS',evidence_ref='part7_wave7e_p1b_client_demand_lite_acceptance_smoke',last_tested_at=now(),updated_at=now();

  delete from ops.client_demand_review_queue where request_id=req_a;
  delete from ops.domain_command_apply_audit where command_pk=cmd_a;
  delete from ops.domain_commands where command_pk=cmd_a;
  delete from ops.event_effects where event_pk=ev_a;
  delete from ops.worker_runs where worker_run_pk=run_a;
  delete from ops.portal_action_requests where request_id=req_a;
  delete from ops.events where event_pk=ev_a;
  delete from ops.raw_inputs where raw_input_id=raw_a;
  delete from config.id_allocation_audit where allocated_id=raw_a;
  delete from authz.organization_members where org_id=org_a and auth_user_id=u_client;
  delete from ops.portal_feature_flags where environment='TEST' and org_id in (org_a,org_b) and feature_key='client_demand_submit' and enabled_by='PART7E_SMOKE';
  delete from authz.organizations where org_id in (org_a,org_b);
  delete from core.clients where client_id in ('MYC-B2B-9961','MYC-B2B-9962');
  delete from auth.users where id=u_client;

  update config.system_settings set setting_value=coalesce(old_external,'false'::jsonb),updated_at=now() where setting_key='portal_external_access_enabled';
  update config.system_settings set setting_value=coalesce(old_client,'false'::jsonb),updated_at=now() where setting_key='portal_client_enabled';
end
$smoke$;