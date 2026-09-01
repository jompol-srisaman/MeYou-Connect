do $smoke$
declare
  v_candidate uuid:='33333333-3333-4333-8333-333333339903'::uuid;
  v_sales uuid:='44444444-4444-4444-8444-444444449903'::uuid;
  v_finance uuid:='55555555-5555-4555-8555-555555559903'::uuid;
  v_content uuid:='66666666-6666-4666-8666-666666669903'::uuid;
  v_founder uuid:='77777777-7777-4777-8777-777777779903'::uuid;
  v_payload jsonb;
  v_decision text;
  v_count integer;
  v_hash_before text;
  v_hash_after text;
begin
  delete from analytics.query_benchmark_samples where surface_key='AN011_POLICY_SLOW';
  delete from analytics.materialization_decisions where surface_key='AN011_POLICY_SLOW';
  delete from authz.user_roles where auth_user_id in (v_candidate,v_sales,v_finance,v_content,v_founder);
  delete from auth.users where id in (v_candidate,v_sales,v_finance,v_content,v_founder);

  if exists(select 1 from analytics.materialization_decisions where surface_key in ('FOUNDER_DAILY','FOUNDER_WEEKLY','FOUNDER_MONTHLY') and decision<>'KEEP_NORMAL_VIEW') then
    raise exception 'AN011_ACTUAL_BENCHMARK_DECISION_FAILED';
  end if;
  if exists(select 1 from analytics.materialization_decisions where surface_key in ('FOUNDER_DAILY','FOUNDER_WEEKLY','FOUNDER_MONTHLY') and (p95_ms is null or p95_ms>threshold_ms)) then
    raise exception 'AN011_ACTUAL_P95_THRESHOLD_FAILED';
  end if;
  if to_regclass('analytics.founder_weekly_mv') is not null or to_regclass('analytics.monthly_review_mv') is not null then
    raise exception 'AN011_PREMATURE_MATERIALIZATION_FOUND';
  end if;

  v_hash_before:=analytics.surface_definition_hash('FOUNDER_WEEKLY');
  insert into analytics.query_benchmark_samples(surface_key,query_key,duration_ms,row_count,test_mode,source_state,measured_by,notes) values
  ('AN011_POLICY_SLOW','POLICY_BRANCH',6100,1,true,'AN011_POLICY_TEST','PART6C_SMOKE','Synthetic policy branch only; not an actual performance measurement.'),
  ('AN011_POLICY_SLOW','POLICY_BRANCH',6200,1,true,'AN011_POLICY_TEST','PART6C_SMOKE','Synthetic policy branch only; not an actual performance measurement.'),
  ('AN011_POLICY_SLOW','POLICY_BRANCH',6300,1,true,'AN011_POLICY_TEST','PART6C_SMOKE','Synthetic policy branch only; not an actual performance measurement.'),
  ('AN011_POLICY_SLOW','POLICY_BRANCH',6400,1,true,'AN011_POLICY_TEST','PART6C_SMOKE','Synthetic policy branch only; not an actual performance measurement.'),
  ('AN011_POLICY_SLOW','POLICY_BRANCH',6500,1,true,'AN011_POLICY_TEST','PART6C_SMOKE','Synthetic policy branch only; not an actual performance measurement.');
  select x->>'decision' into v_decision from (select analytics.evaluate_materialization_need('AN011_POLICY_SLOW',5000,'AN011_POLICY_TEST','PART6C_SMOKE') x) s;
  if v_decision<>'RECOMMEND_MATERIALIZATION' then raise exception 'AN011_SLOW_POLICY_BRANCH_FAILED:%',v_decision; end if;
  if exists(select 1 from analytics.materialization_decisions where surface_key='AN011_POLICY_SLOW' and materialized_object is not null) then
    raise exception 'AN011_POLICY_MUST_NOT_AUTO_MATERIALIZE';
  end if;
  v_hash_after:=analytics.surface_definition_hash('FOUNDER_WEEKLY');
  if v_hash_before<>v_hash_after then raise exception 'AN011_SEMANTIC_DEFINITION_CHANGED'; end if;

  insert into auth.users(id) values(v_candidate),(v_sales),(v_finance),(v_content),(v_founder);
  update authz.user_profiles set display_name='Part6C Candidate Ops Smoke',status='ACTIVE' where auth_user_id=v_candidate;
  update authz.user_profiles set display_name='Part6C Sales Smoke',status='ACTIVE' where auth_user_id=v_sales;
  update authz.user_profiles set display_name='Part6C Finance Smoke',status='ACTIVE' where auth_user_id=v_finance;
  update authz.user_profiles set display_name='Part6C Content Smoke',status='ACTIVE' where auth_user_id=v_content;
  update authz.user_profiles set display_name='Part6C Founder Smoke',status='ACTIVE' where auth_user_id=v_founder;
  insert into authz.user_roles(auth_user_id,role_key,assigned_by,reason) values
  (v_candidate,'candidate_ops','PART6C_SMOKE','Dashboard acceptance'),
  (v_sales,'client_sales','PART6C_SMOKE','Dashboard acceptance'),
  (v_finance,'finance_control','PART6C_SMOKE','Dashboard acceptance'),
  (v_content,'content_studio','PART6C_SMOKE','Dashboard acceptance'),
  (v_founder,'founder','PART6C_SMOKE','Dashboard acceptance');

  perform set_config('request.jwt.claim.sub',v_candidate::text,true); execute 'set local role authenticated';
  select api.analytics_dashboard('CANDIDATE_OPS') into v_payload;
  if v_payload->>'status'<>'NOT_READY' or jsonb_typeof(v_payload->'data')<>'null' then raise exception 'CANDIDATE_OPS_SHADOW_GATE_FAILED'; end if;
  begin perform api.analytics_dashboard('FINANCE'); raise exception 'CANDIDATE_CROSS_ROLE_FAILED'; exception when others then if position('ACCESS_DENIED:finance_dashboard_read' in sqlerrm)=0 then raise; end if; end;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',v_sales::text,true); execute 'set local role authenticated';
  select api.analytics_dashboard('CLIENT_SALES') into v_payload;
  if v_payload->>'status'<>'NOT_READY' then raise exception 'SALES_DASHBOARD_FAILED'; end if;
  begin perform api.analytics_dashboard('CANDIDATE_OPS'); raise exception 'SALES_CROSS_ROLE_FAILED'; exception when others then if position('ACCESS_DENIED:candidate_ops_dashboard_read' in sqlerrm)=0 then raise; end if; end;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',v_finance::text,true); execute 'set local role authenticated';
  select api.analytics_dashboard('FINANCE') into v_payload;
  if v_payload->>'status'<>'NOT_READY' then raise exception 'FINANCE_DASHBOARD_FAILED'; end if;
  begin perform api.analytics_dashboard('PARTNER_REVIEW'); raise exception 'FINANCE_CROSS_ROLE_FAILED'; exception when others then if position('ACCESS_DENIED:partner_dashboard_read' in sqlerrm)=0 then raise; end if; end;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',v_content::text,true); execute 'set local role authenticated';
  begin perform api.analytics_dashboard('DATA_QUALITY'); raise exception 'CONTENT_DASHBOARD_ACCESS_FAILED'; exception when others then if position('ACCESS_DENIED:dq_dashboard_read' in sqlerrm)=0 then raise; end if; end;
  begin execute 'select count(*) from analytics.dashboard_pages'; raise exception 'DIRECT_ANALYTICS_TABLE_ACCESS_FAILED'; exception when insufficient_privilege then null; end;
  execute 'reset role';

  perform set_config('request.jwt.claim.sub',v_founder::text,true); execute 'set local role authenticated';
  select api.analytics_dashboard('FOUNDER_DAILY') into v_payload;
  if v_payload->>'status'<>'NOT_READY' or v_payload->>'blocked_reason'<>'POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE' then raise exception 'FOUNDER_SHADOW_GATE_FAILED'; end if;
  select count(*) into v_count from jsonb_array_elements((api.analytics_dashboard_contract('FOUNDER_DAILY'))->'kpis');
  if v_count<5 then raise exception 'FOUNDER_DASHBOARD_CONTRACT_INCOMPLETE'; end if;
  execute 'reset role'; perform set_config('request.jwt.claim.sub','',true);

  delete from authz.user_roles where auth_user_id in (v_candidate,v_sales,v_finance,v_content,v_founder);
  delete from auth.users where id in (v_candidate,v_sales,v_finance,v_content,v_founder);
  delete from analytics.query_benchmark_samples where surface_key='AN011_POLICY_SLOW';
  delete from analytics.materialization_decisions where surface_key='AN011_POLICY_SLOW';

  update analytics.acceptance_catalog set status='PASS',evidence_ref='part6_wave6c_dashboard_and_materialization_acceptance_smoke',last_tested_at=now(),updated_at=now() where test_id='AN-011';
end
$smoke$;