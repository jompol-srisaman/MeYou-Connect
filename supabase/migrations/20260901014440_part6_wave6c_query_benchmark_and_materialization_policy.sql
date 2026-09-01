create or replace function analytics.surface_definition_hash(p_surface_key text)
returns text
language plpgsql
stable
security definer
set search_path=''
as $fn$
declare v_reg regclass;
begin
  v_reg:=case upper(trim(p_surface_key))
    when 'FOUNDER_DAILY' then to_regclass('analytics.founder_daily_v')
    when 'FOUNDER_WEEKLY' then to_regclass('analytics.founder_weekly_v')
    when 'FOUNDER_MONTHLY' then to_regclass('analytics.founder_monthly_v')
    when 'CANDIDATE_OPS' then to_regclass('analytics.candidate_ops_dashboard_v')
    when 'CLIENT_SALES' then to_regclass('analytics.client_sales_dashboard_v')
    when 'FINANCE' then to_regclass('analytics.finance_dashboard_v')
    when 'PARTNER_REVIEW' then to_regclass('analytics.partner_performance_v')
    when 'DATA_QUALITY' then to_regclass('analytics.data_quality_dashboard_v')
    else null end;
  if v_reg is null then raise exception 'UNKNOWN_BENCHMARK_SURFACE'; end if;
  return md5(pg_get_viewdef(v_reg,true));
end
$fn$;

create or replace function analytics.benchmark_dashboard_surface(
  p_surface_key text,
  p_iterations integer default 10,
  p_measured_by text default 'PART6C_BENCHMARK'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  i integer;
  v_start timestamptz;
  v_end timestamptz;
  v_ms numeric;
  v_rows bigint;
  v_sink bigint;
  v_key text:=upper(trim(p_surface_key));
begin
  if p_iterations<1 or p_iterations>100 then raise exception 'INVALID_BENCHMARK_ITERATIONS'; end if;
  for i in 1..p_iterations loop
    v_start:=clock_timestamp();
    case v_key
      when 'FOUNDER_DAILY' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.founder_daily_v v;
      when 'FOUNDER_WEEKLY' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.founder_weekly_v v;
      when 'FOUNDER_MONTHLY' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.founder_monthly_v v;
      when 'CANDIDATE_OPS' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.candidate_ops_dashboard_v v;
      when 'CLIENT_SALES' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.client_sales_dashboard_v v;
      when 'FINANCE' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.finance_dashboard_v v;
      when 'PARTNER_REVIEW' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.partner_performance_v v;
      when 'DATA_QUALITY' then select coalesce(sum(length(to_jsonb(v)::text)),0),count(*) into v_sink,v_rows from analytics.data_quality_dashboard_v v;
      else raise exception 'UNKNOWN_BENCHMARK_SURFACE';
    end case;
    v_end:=clock_timestamp();
    v_ms:=extract(epoch from (v_end-v_start))*1000;
    insert into analytics.query_benchmark_samples(surface_key,query_key,duration_ms,row_count,test_mode,source_state,measured_by,notes)
    values(v_key,'FULL_SURFACE_RENDER',v_ms,v_rows,true,'ACTUAL_TEST_BENCHMARK',p_measured_by,'Forces full row JSON serialization; TEST/shadow benchmark only.');
  end loop;
  return jsonb_build_object(
    'surface_key',v_key,
    'iterations',p_iterations,
    'p95_ms',(select percentile_cont(0.95) within group(order by duration_ms) from analytics.query_benchmark_samples where surface_key=v_key and source_state='ACTUAL_TEST_BENCHMARK'),
    'max_ms',(select max(duration_ms) from analytics.query_benchmark_samples where surface_key=v_key and source_state='ACTUAL_TEST_BENCHMARK'),
    'definition_hash',analytics.surface_definition_hash(v_key)
  );
end
$fn$;

create or replace function analytics.evaluate_materialization_need(
  p_surface_key text,
  p_threshold_ms integer,
  p_source_state text default 'ACTUAL_TEST_BENCHMARK',
  p_evaluated_by text default 'PART6C_POLICY'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_samples integer;
  v_p95 numeric;
  v_decision text;
  v_rationale text;
  v_hash text;
begin
  if p_threshold_ms<=0 then raise exception 'INVALID_THRESHOLD'; end if;
  select count(*)::integer,
         percentile_cont(0.95) within group(order by duration_ms)::numeric
  into v_samples,v_p95
  from analytics.query_benchmark_samples
  where surface_key=upper(trim(p_surface_key)) and source_state=p_source_state;

  if v_samples<5 then
    v_decision:='NOT_ENOUGH_DATA';
    v_rationale:='At least 5 measured samples are required before materialization can be recommended.';
  elsif v_p95>p_threshold_ms then
    v_decision:='RECOMMEND_MATERIALIZATION';
    v_rationale:='Measured p95 exceeds the accepted threshold; materialization may be evaluated but is not auto-created.';
  else
    v_decision:='KEEP_NORMAL_VIEW';
    v_rationale:='Measured p95 is within threshold; architecture requires normal SQL views to remain the default.';
  end if;

  begin v_hash:=analytics.surface_definition_hash(p_surface_key); exception when others then v_hash:=null; end;

  insert into analytics.materialization_decisions(surface_key,decision,p95_ms,threshold_ms,sample_count,rationale,semantic_hash_before,semantic_hash_after,materialized_object,evaluated_at,evaluated_by,source_ref)
  values(upper(trim(p_surface_key)),v_decision,v_p95,p_threshold_ms,v_samples,v_rationale,v_hash,v_hash,null,now(),p_evaluated_by,'Part6C measured-need policy')
  on conflict (surface_key) do update set decision=excluded.decision,p95_ms=excluded.p95_ms,threshold_ms=excluded.threshold_ms,sample_count=excluded.sample_count,rationale=excluded.rationale,semantic_hash_before=excluded.semantic_hash_before,semantic_hash_after=excluded.semantic_hash_after,materialized_object=null,evaluated_at=excluded.evaluated_at,evaluated_by=excluded.evaluated_by,source_ref=excluded.source_ref;

  return jsonb_build_object('surface_key',upper(trim(p_surface_key)),'decision',v_decision,'p95_ms',v_p95,'threshold_ms',p_threshold_ms,'sample_count',v_samples,'rationale',v_rationale,'semantic_hash',v_hash);
end
$fn$;

revoke all on function analytics.surface_definition_hash(text),analytics.benchmark_dashboard_surface(text,integer,text),analytics.evaluate_materialization_need(text,integer,text,text) from public,anon,authenticated;
grant execute on function analytics.surface_definition_hash(text),analytics.benchmark_dashboard_surface(text,integer,text),analytics.evaluate_materialization_need(text,integer,text,text) to service_role;