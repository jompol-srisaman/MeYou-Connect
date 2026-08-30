begin;

insert into auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous) values
('50000000-0000-0000-0000-000000000001','authenticated','authenticated','tst5a-founder@example.invalid',now(),now(),false,false),
('50000000-0000-0000-0000-000000000002','authenticated','authenticated','tst5a-audit@example.invalid',now(),now(),false,false),
('50000000-0000-0000-0000-000000000003','authenticated','authenticated','tst5a-content@example.invalid',now(),now(),false,false);

select authz.assign_role('50000000-0000-0000-0000-000000000001','founder','part5a-smoke','synthetic founder',null);
select authz.assign_role('50000000-0000-0000-0000-000000000002','data_audit','part5a-smoke','synthetic data audit',null);
select authz.assign_role('50000000-0000-0000-0000-000000000003','content_studio','part5a-smoke','synthetic content',null);

select ops.record_security_evidence('rls_allow_tests','TEST','AUTOMATED_TEST','PASS','MIGRATION','part5a-smoke','Synthetic critical RLS allow test evidence','part5a-smoke',null,'PG-001','{}'::jsonb,now(),null);
select ops.record_security_evidence('rls_deny_tests','TEST','AUTOMATED_TEST','PASS','MIGRATION','part5a-smoke','Synthetic critical RLS deny test evidence','part5a-smoke',null,'PG-002','{}'::jsonb,now(),null);
select ops.record_security_evidence('api_inventory_review','TEST','DB_INTROSPECTION','PASS','MIGRATION','part5a-smoke','Synthetic API inventory review evidence','part5a-smoke',null,'PG-003','{}'::jsonb,now(),null);

select ops.evaluate_security_gates('TEST','part5a-smoke');

do $$
declare v jsonb; v_status text; v_count int; begin
  v:=ops.part5a_foundation_status();
  if coalesce((v->>'foundation_ready')::boolean,false) is not true then raise exception 'Part5A foundation not ready: %',v; end if;
  select status into v_status from ops.security_gate_runs where environment='TEST' order by started_at desc,run_pk desc limit 1;
  if v_status<>'NOT_READY' then raise exception 'TEST production gate should remain NOT_READY, got %',v_status; end if;
  select count(*) into v_count from ops.security_gate_results r join ops.security_gate_runs g on g.run_pk=r.run_pk where g.environment='TEST' and g.started_at=(select max(started_at) from ops.security_gate_runs where environment='TEST') and r.gate_id in ('PG-007','PG-008','PG-011','PG-014') and r.status='PASS';
  if v_count<>4 then raise exception 'Expected automatic safety gates PG-007/008/011/014 PASS, got %',v_count; end if;
  select count(*) into v_count from ops.security_gate_results r join ops.security_gate_runs g on g.run_pk=r.run_pk where g.environment='TEST' and g.started_at=(select max(started_at) from ops.security_gate_runs where environment='TEST') and r.gate_id in ('PG-004','PG-005','PG-006','PG-009','PG-010','PG-013','PG-015') and r.status='NOT_READY';
  if v_count<>7 then raise exception 'Expected unresolved Production evidence gates to remain NOT_READY, got %',v_count; end if;
  if exists(select 1 from ops.storage_security_v where expected_class='PRIVATE_REQUIRED' and security_status='VIOLATION') then raise exception 'Private storage exposure violation detected'; end if;
  if (select count(*) from ops.security_control_catalog)<>16 then raise exception 'Security control catalog count mismatch'; end if;
  if (select count(*) from ops.security_gate_catalog)<>15 then raise exception 'Security gate catalog count mismatch'; end if;
  if not exists(select 1 from ops.api_surface_inventory_v) then raise exception 'API inventory empty'; end if;
  if not exists(select 1 from ops.security_definer_inventory_v) then raise exception 'Security definer inventory empty'; end if;
  begin
    insert into ops.secret_inventory(secret_ref,system_name,environment,purpose,scope_summary,stored_in,owner_role,rotate_trigger,status)
    values('BAD-SECRET-TEST','Bad','TEST','test','test','GOOGLE_DRIVE','test','test','ACTIVE');
    raise exception 'Invalid secret storage location unexpectedly accepted';
  exception when check_violation then null; end;
  begin
    perform ops.record_security_evidence('bad-secret-payload','TEST','TEST','INFO','TEST','test','must reject secret-like detail key','part5a-smoke',null,null,jsonb_build_object('secret_value','redacted'),now(),null);
    raise exception 'Secret-like evidence details unexpectedly accepted';
  exception when check_violation then null; end;
end $$;

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$
declare v jsonb; v_count int; begin
  v:=api.security_foundation_status();
  if coalesce((v->>'foundation_ready')::boolean,false) is not true then raise exception 'Founder security foundation API failed'; end if;
  select count(*) into v_count from api.security_control_summary(); if v_count<>16 then raise exception 'Founder security controls API failed'; end if;
  select count(*) into v_count from api.security_api_surface_inventory(); if v_count<1 then raise exception 'Founder security audit inventory failed'; end if;
  select count(*) into v_count from api.security_rls_inventory(); if v_count<1 then raise exception 'Founder RLS inventory failed'; end if;
  begin perform 1 from ops.security_control_catalog limit 1; raise exception 'Direct security table read unexpectedly allowed'; exception when insufficient_privilege then null; end;
  begin insert into ops.privileged_identity_registry(environment,identity_label,identity_type) values('TEST','bad-client','HUMAN'); raise exception 'Direct privileged identity write unexpectedly allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000002',true);
do $$ declare v_count int; begin
  select count(*) into v_count from api.security_gate_status('TEST'); if v_count<>15 then raise exception 'Data Audit security gate read failed'; end if;
end $$;

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000003',true);
do $$ begin
  begin perform api.security_foundation_status(); raise exception 'Content Studio security API unexpectedly allowed'; exception when others then if position('ACCESS_DENIED' in sqlerrm)=0 then raise; end if; end;
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
  begin perform api.security_foundation_status(); raise exception 'Anon security API unexpectedly allowed'; exception when insufficient_privilege then null; end;
end $$;

reset role;
rollback;