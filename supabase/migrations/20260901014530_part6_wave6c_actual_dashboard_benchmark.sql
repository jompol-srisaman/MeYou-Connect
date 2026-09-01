delete from analytics.query_benchmark_samples where source_state='ACTUAL_TEST_BENCHMARK' and measured_by='PART6C_ACTUAL';

do $bench$
declare v_threshold integer;
begin
  perform analytics.benchmark_dashboard_surface('FOUNDER_DAILY',20,'PART6C_ACTUAL');
  perform analytics.benchmark_dashboard_surface('FOUNDER_WEEKLY',20,'PART6C_ACTUAL');
  perform analytics.benchmark_dashboard_surface('FOUNDER_MONTHLY',20,'PART6C_ACTUAL');
  perform analytics.benchmark_dashboard_surface('CANDIDATE_OPS',10,'PART6C_ACTUAL');
  perform analytics.benchmark_dashboard_surface('CLIENT_SALES',10,'PART6C_ACTUAL');
  perform analytics.benchmark_dashboard_surface('FINANCE',10,'PART6C_ACTUAL');
  perform analytics.benchmark_dashboard_surface('PARTNER_REVIEW',10,'PART6C_ACTUAL');
  perform analytics.benchmark_dashboard_surface('DATA_QUALITY',10,'PART6C_ACTUAL');

  select performance_target_ms into v_threshold from analytics.dashboard_pages where page_key='FOUNDER_DAILY';
  perform analytics.evaluate_materialization_need('FOUNDER_DAILY',v_threshold,'ACTUAL_TEST_BENCHMARK','PART6C_ACTUAL');
  select performance_target_ms into v_threshold from analytics.dashboard_pages where page_key='FOUNDER_WEEKLY';
  perform analytics.evaluate_materialization_need('FOUNDER_WEEKLY',v_threshold,'ACTUAL_TEST_BENCHMARK','PART6C_ACTUAL');
  select performance_target_ms into v_threshold from analytics.dashboard_pages where page_key='FOUNDER_MONTHLY';
  perform analytics.evaluate_materialization_need('FOUNDER_MONTHLY',v_threshold,'ACTUAL_TEST_BENCHMARK','PART6C_ACTUAL');
end
$bench$;