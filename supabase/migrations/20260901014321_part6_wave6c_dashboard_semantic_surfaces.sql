create or replace function analytics.evaluate_kpi_v3(
  p_kpi_id text,
  p_as_of timestamptz default now(),
  p_allow_test_shadow boolean default false
)
returns table(
  kpi_id text,status text,as_of timestamptz,numerator numeric,denominator numeric,metric_value numeric,
  result_type text,blocked_reason text,source_object text
)
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_type text;
  v_num numeric;
  v_missing numeric;
  v_rows numeric;
  v_publish boolean;
begin
  select k.result_type into v_type from analytics.kpi_catalog k where k.kpi_id=p_kpi_id and k.active;
  if v_type is null then raise exception 'UNKNOWN_KPI_ID'; end if;

  select coalesce((s.setting_value #>> '{}')::boolean,false) into v_publish
  from config.system_settings s where s.setting_key='analytics_postgres_publish_enabled';
  if not p_allow_test_shadow and not coalesce(v_publish,false) then
    return query select * from analytics.evaluate_kpi_v2(p_kpi_id,p_as_of,false);
    return;
  end if;

  case p_kpi_id
    when 'KPI-CLI-002' then
      select count(*)::numeric into v_num from core.jobs j where upper(coalesce(j.status,'')) in ('ACTIVE','OPEN');
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'core.jobs'::text;
    when 'KPI-CLI-003' then
      select count(*) filter(where not j.data_ready)::numeric,
             coalesce(sum(j.open_headcount) filter(where j.data_ready),0)::numeric
      into v_missing,v_num
      from analytics.job_demand_v j where upper(coalesce(j.job_status,'')) in ('ACTIVE','OPEN');
      if coalesce(v_missing,0)>0 then
        return query select p_kpi_id,'PARTIAL',p_as_of,v_num,null::numeric,v_num,v_type,'ACTIVE_JOB_HEADCOUNT_MISSING'::text,'analytics.job_demand_v'::text;
      else
        return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'analytics.job_demand_v'::text;
      end if;
    when 'KPI-FIN-001' then
      select coalesce(sum(r.gross),0)::numeric into v_num from finance.revenue r where r.status='EXPECTED';
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'finance.revenue'::text;
    when 'KPI-FIN-002' then
      select coalesce(sum(r.gross),0)::numeric into v_num from finance.revenue r where r.status in ('EARNED','INVOICED','COLLECTED');
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'finance.revenue'::text;
    when 'KPI-FIN-003' then
      select coalesce(sum(r.gross),0)::numeric into v_num from finance.revenue r where r.status in ('INVOICED','COLLECTED');
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'finance.revenue'::text;
    when 'KPI-FIN-005' then
      select count(*)::numeric,coalesce(sum(ar.outstanding),0)::numeric into v_rows,v_num from finance.accounts_receivable_v ar;
      if coalesce(v_rows,0)=0 then
        return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_type,'AR_NOT_INITIALIZED'::text,'finance.accounts_receivable_v'::text;
      else
        return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'finance.accounts_receivable_v'::text;
      end if;
    when 'KPI-FIN-006' then
      select coalesce(sum(c.commission_amount),0)::numeric into v_num from finance.commissions c where c.state='PAYABLE';
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'finance.commissions'::text;
    when 'KPI-FIN-008' then
      select count(*)::numeric,
             coalesce(sum(case when b.direction='IN' then b.amount else -b.amount end),0)::numeric
      into v_rows,v_num from finance.bank_transactions b where b.reconciled=true and b.txn_at<=p_as_of;
      if coalesce(v_rows,0)=0 then
        return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_type,'RECONCILED_CASH_LEDGER_NOT_INITIALIZED'::text,'finance.bank_transactions'::text;
      else
        return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_type,null::text,'finance.bank_transactions'::text;
      end if;
    else
      return query select * from analytics.evaluate_kpi_v2(p_kpi_id,p_as_of,p_allow_test_shadow);
  end case;
end
$fn$;
revoke all on function analytics.evaluate_kpi_v3(text,timestamptz,boolean) from public,anon,authenticated;
grant execute on function analytics.evaluate_kpi_v3(text,timestamptz,boolean) to service_role;

create or replace view analytics.founder_daily_v as
with x as (
 select now() as as_of,(now() at time zone 'Asia/Bangkok')::date as business_date
), dq as (
 select
   max(metric_value) filter(where metric_key='OPEN_CRITICAL_DQ') as critical_dq,
   max(metric_value) filter(where metric_key='UNPROCESSED_RAW_INPUT') as raw_backlog,
   max(metric_value) filter(where metric_key='AUTOMATION_DEAD_LETTER') as dead_letter
 from analytics.data_quality_v
)
select x.as_of,x.business_date,
  (select coalesce(sum(case when direction='IN' then amount else -amount end),0) from finance.bank_transactions where reconciled=true) as cash_balance,
  (select coalesce(sum(net_received),0) from analytics.finance_collected_official_v where collection_date=x.business_date) as collected_today,
  (select coalesce(sum(outstanding),0) from finance.accounts_receivable_v) as ar_outstanding,
  (select coalesce(sum(commission_amount),0) from finance.commissions where state='PAYABLE') as commission_payable,
  (select count(*) from core.jobs where upper(coalesce(status,'')) in ('ACTIVE','OPEN')) as active_job_demand,
  (select coalesce(sum(open_headcount),0) from analytics.job_demand_v where upper(coalesce(job_status,'')) in ('ACTIVE','OPEN') and data_ready) as open_headcount_known,
  (select count(*) from core.placements where start_date=x.business_date) as starts_today,
  (select count(*) from core.followups where next_followup_at is not null and next_followup_at<=x.as_of) as followups_due,
  coalesce(dq.critical_dq,0)::bigint as critical_dq,
  coalesce(dq.raw_backlog,0)::bigint as raw_backlog,
  coalesce(dq.dead_letter,0)::bigint as dead_letter,
  coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as official_publish_enabled
from x cross join dq;

create or replace view analytics.founder_weekly_v as
with x as (
 select now() as as_of,(now() at time zone 'Asia/Bangkok')::date as end_date,((now() at time zone 'Asia/Bangkok')::date-6) as start_date
), ap as (
 select count(*)::numeric as occurred,
        count(*) filter(where outcome='SHOW')::numeric as showed,
        count(*) filter(where outcome='NO_SHOW')::numeric as no_show,
        count(*) filter(where outcome in ('UNKNOWN','NEEDS_REVIEW'))::numeric as ambiguous
 from analytics.appointment_outcome_current_v a,x
 where (a.appointment_at at time zone 'Asia/Bangkok')::date between x.start_date and x.end_date
), d7 as (
 select count(*)::numeric as eligible,
        count(*) filter(where d7_outcome in ('ACTIVE','PASS'))::numeric as positive,
        count(*) filter(where d7_outcome is null or d7_outcome in ('UNKNOWN','NOT_REACHED','CONTACT_FAILED','NEEDS_REVIEW'))::numeric as unresolved
 from analytics.placement_cohort_v
 where eligible_d7
)
select x.as_of,x.start_date,x.end_date,
 (select count(distinct candidate_id) from analytics.candidate_stage_events_v where upper(to_stage)='QUALIFIED' and (occurred_at at time zone 'Asia/Bangkok')::date between x.start_date and x.end_date) as qualified_7d,
 ap.occurred as appointments_occurred_7d,
 case when ap.occurred=0 or ap.ambiguous>0 then null else round((ap.showed/ap.occurred)*100,4) end as show_rate_pct,
 case when ap.occurred=0 or ap.ambiguous>0 then null else round((ap.no_show/ap.occurred)*100,4) end as no_show_rate_pct,
 (select count(*) from core.placements where start_date between x.start_date and x.end_date) as starts_7d,
 d7.eligible as d7_eligible,d7.positive as d7_positive,
 case when d7.eligible=0 or d7.unresolved>0 then null else round((d7.positive/d7.eligible)*100,4) end as d7_retention_pct,
 (select coalesce(sum(net_received),0) from analytics.finance_collected_official_v where collection_date between x.start_date and x.end_date) as collected_7d,
 (select count(*) from analytics.partner_attribution_current_v p where p.data_ready=true and p.approved_partner_id is not null and (p.latest_approved_at at time zone 'Asia/Bangkok')::date between x.start_date and x.end_date) as approved_partner_leads_7d,
 coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as official_publish_enabled
from x cross join ap cross join d7;

create or replace view analytics.founder_monthly_v as
with x as (
 select now() as as_of,date_trunc('month',now() at time zone 'Asia/Bangkok')::date as month_start,(now() at time zone 'Asia/Bangkok')::date as end_date
), d30 as (
 select count(*)::numeric as eligible,
        count(*) filter(where d30_outcome in ('ACTIVE','PASS'))::numeric as positive,
        count(*) filter(where d30_outcome is null or d30_outcome in ('UNKNOWN','NOT_REACHED','CONTACT_FAILED','NEEDS_REVIEW'))::numeric as unresolved
 from analytics.placement_cohort_v where eligible_d30
)
select x.as_of,x.month_start,x.end_date,
 (select coalesce(sum(net_received),0) from analytics.finance_collected_official_v where collection_date between x.month_start and x.end_date) as collected_month,
 coalesce(f.revenue_amount,0) as posted_revenue_month,
 coalesce(f.expense_amount,0) as posted_expense_month,
 coalesce(f.net_result,0) as posted_net_result_month,
 coalesce(f.accounting_close_status,'PROVISIONAL') as accounting_close_status,
 coalesce(f.journal_balance_status,'BALANCED') as journal_balance_status,
 (select coalesce(sum(case when direction='IN' then amount else -amount end),0) from finance.bank_transactions where reconciled=true) as cash_balance,
 (select coalesce(sum(outstanding),0) from finance.accounts_receivable_v) as ar_outstanding,
 (select count(*) from core.placements where start_date between x.month_start and x.end_date) as starts_month,
 d30.eligible as d30_eligible,d30.positive as d30_positive,
 case when d30.eligible=0 or d30.unresolved>0 then null else round((d30.positive/d30.eligible)*100,4) end as d30_retention_pct,
 coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as official_publish_enabled
from x left join analytics.finance_monthly_v f on f.month_start=x.month_start cross join d30;

create or replace view analytics.candidate_ops_dashboard_v as
with x as (select now() as as_of,(now() at time zone 'Asia/Bangkok')::date as today,((now() at time zone 'Asia/Bangkok')::date-6) as start_date)
select x.as_of,
 (select count(*) from core.followups where next_followup_at is not null and next_followup_at<=x.as_of) as due_followups,
 (select count(*) from analytics.appointment_outcome_current_v where (appointment_at at time zone 'Asia/Bangkok')::date=x.today) as appointments_today,
 (select count(*) from analytics.appointment_outcome_current_v where outcome='NO_SHOW' and (appointment_at at time zone 'Asia/Bangkok')::date between x.start_date and x.today) as no_show_7d,
 (select count(*) from core.placements where start_date between x.start_date and x.today) as starts_7d,
 (select count(*) from analytics.placement_cohort_v where eligible_d7 and (d7_outcome is null or d7_outcome not in ('ACTIVE','PASS'))) as d7_exceptions,
 coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as official_publish_enabled
from x;

create or replace view analytics.client_sales_dashboard_v as
with x as (select (now() at time zone 'Asia/Bangkok')::date as today,((now() at time zone 'Asia/Bangkok')::date-6) as start_date)
select now() as as_of,
 (select count(*) from core.clients where upper(coalesce(crm_status,''))='ACTIVE') as active_clients,
 (select count(*) from core.jobs where upper(coalesce(status,'')) in ('ACTIVE','OPEN')) as active_jobs,
 (select coalesce(sum(open_headcount),0) from analytics.job_demand_v where upper(coalesce(job_status,'')) in ('ACTIVE','OPEN') and data_ready) as open_headcount_known,
 (select count(*) from core.placements where start_date between x.start_date and x.today) as starts_7d,
 (select coalesce(sum(outstanding),0) from finance.accounts_receivable_v where derived_status='OVERDUE') as overdue_ar,
 coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as official_publish_enabled
from x;

create or replace view analytics.finance_dashboard_v as
with x as (select date_trunc('month',now() at time zone 'Asia/Bangkok')::date as month_start,(now() at time zone 'Asia/Bangkok')::date as today)
select now() as as_of,x.month_start,
 (select coalesce(sum(gross),0) from finance.revenue where status='EXPECTED') as expected_revenue,
 (select coalesce(sum(gross),0) from finance.revenue where status in ('EARNED','INVOICED','COLLECTED')) as earned_revenue,
 (select coalesce(sum(gross),0) from finance.revenue where status in ('INVOICED','COLLECTED')) as invoiced_revenue,
 (select coalesce(sum(net_received),0) from analytics.finance_collected_official_v where collection_date between x.month_start and x.today) as collected_month,
 (select coalesce(sum(outstanding),0) from finance.accounts_receivable_v) as ar_outstanding,
 (select coalesce(sum(outstanding),0) from finance.accounts_payable_v) as ap_outstanding,
 (select coalesce(sum(commission_amount),0) from finance.commissions where state='PAYABLE') as commission_payable,
 (select coalesce(sum(case when direction='IN' then amount else -amount end),0) from finance.bank_transactions where reconciled=true) as cash_balance,
 coalesce((select accounting_close_status from analytics.finance_monthly_v where month_start=x.month_start),'PROVISIONAL') as close_status,
 coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as official_publish_enabled
from x;

create or replace view analytics.data_quality_dashboard_v as
select now() as as_of,
 coalesce(max(metric_value) filter(where metric_key='OPEN_CRITICAL_DQ'),0)::bigint as critical_dq,
 coalesce(max(metric_value) filter(where metric_key='UNPROCESSED_RAW_INPUT'),0)::bigint as raw_backlog,
 coalesce(max(metric_value) filter(where metric_key='AUTOMATION_DEAD_LETTER'),0)::bigint as dead_letter,
 (select count(*) from analytics.partner_attribution_current_v where not data_ready) as unresolved_attribution,
 (select count(*) from analytics.source_readiness_v where readiness_status='STALE') as stale_sources,
 coalesce((select (setting_value #>> '{}')::boolean from config.system_settings where setting_key='analytics_postgres_publish_enabled'),false) as official_publish_enabled
from analytics.data_quality_v;

revoke all on analytics.founder_daily_v,analytics.founder_weekly_v,analytics.founder_monthly_v,analytics.candidate_ops_dashboard_v,analytics.client_sales_dashboard_v,analytics.finance_dashboard_v,analytics.data_quality_dashboard_v from public,anon,authenticated;
grant select on analytics.founder_daily_v,analytics.founder_weekly_v,analytics.founder_monthly_v,analytics.candidate_ops_dashboard_v,analytics.client_sales_dashboard_v,analytics.finance_dashboard_v,analytics.data_quality_dashboard_v to service_role;