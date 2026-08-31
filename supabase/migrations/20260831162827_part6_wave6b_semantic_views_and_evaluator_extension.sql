create or replace view analytics.appointment_outcome_current_v as
with conflicts as (
  select placement_id,appointment_at,count(distinct outcome) filter(where verified) as verified_outcome_count
  from analytics.appointment_outcome_fact group by placement_id,appointment_at
), ranked as (
  select a.*,c.verified_outcome_count,
         row_number() over(partition by a.placement_id,a.appointment_at order by a.verified desc,(a.evidence_id is not null) desc,a.observed_at desc,a.created_at desc) as rn
  from analytics.appointment_outcome_fact a join conflicts c using(placement_id,appointment_at)
)
select appointment_fact_pk,fact_key,placement_id,appointment_at,
       case when verified_outcome_count>1 then 'NEEDS_REVIEW' else outcome end as outcome,
       observed_at,evidence_id,raw_input_id,source_followup_id,source_kind,verified,actor_service,created_at,
       (verified_outcome_count>1) as verified_conflict
from ranked where rn=1;

create or replace view analytics.partner_attribution_current_v as
with approved as (
  select p.candidate_id,
         count(distinct p.partner_id) filter(where p.attribution_status='APPROVED') as approved_partner_count,
         min(p.partner_id) filter(where p.attribution_status='APPROVED') as single_partner_id,
         max(p.attributed_at) filter(where p.attribution_status='APPROVED') as latest_approved_at
  from analytics.partner_attribution_fact p group by p.candidate_id
)
select c.candidate_id,
       case when a.approved_partner_count=1 then a.single_partner_id end as approved_partner_id,
       coalesce(a.approved_partner_count,0) as approved_partner_count,
       (coalesce(a.approved_partner_count,0)=1) as data_ready,
       case when coalesce(a.approved_partner_count,0)=0 then 'APPROVED_ATTRIBUTION_MISSING'
            when a.approved_partner_count>1 then 'APPROVED_ATTRIBUTION_CONFLICT' end as blocked_reason,
       a.latest_approved_at
from core.candidates c left join approved a on a.candidate_id=c.candidate_id;

create or replace view analytics.candidate_funnel_period_v as
with st as (
  select (occurred_at at time zone 'Asia/Bangkok')::date as d,
         count(distinct candidate_id) filter(where upper(to_stage)='LEAD') as leads,
         count(distinct candidate_id) filter(where upper(to_stage)='QUALIFIED') as qualified
  from analytics.candidate_stage_events_v group by 1
), ap as (
  select (appointment_at at time zone 'Asia/Bangkok')::date as d,
         count(*) filter(where outcome not in ('CANCELLED','RESCHEDULED')) as appointments_occurred,
         count(*) filter(where outcome='SHOW') as shows,
         count(*) filter(where outcome='NO_SHOW') as no_shows,
         count(*) filter(where outcome in ('UNKNOWN','NEEDS_REVIEW') or verified=false) as ambiguous_outcomes
  from analytics.appointment_outcome_current_v group by 1
), starts as (
  select start_date as d,count(*) as starts from core.placements where start_date is not null group by start_date
)
select d.calendar_date as period_date,
       coalesce(st.leads,0)::bigint as leads,
       coalesce(st.qualified,0)::bigint as qualified,
       coalesce(ap.appointments_occurred,0)::bigint as appointments_occurred,
       coalesce(ap.shows,0)::bigint as shows,
       coalesce(ap.no_shows,0)::bigint as no_shows,
       coalesce(ap.ambiguous_outcomes,0)::bigint as ambiguous_outcomes,
       coalesce(starts.starts,0)::bigint as starts
from analytics.dim_date d
left join st on st.d=d.calendar_date
left join ap on ap.d=d.calendar_date
left join starts on starts.d=d.calendar_date;

create or replace view analytics.partner_performance_v as
with attr as (
  select candidate_id,approved_partner_id as partner_id,latest_approved_at from analytics.partner_attribution_current_v where data_ready
), starts as (
  select p.candidate_id,count(distinct p.placement_id) as starts from core.placements p where p.start_date is not null group by p.candidate_id
), collected as (
  select p.candidate_id,sum(v.net_received) as collected_amount from core.placements p join analytics.finance_collected_official_v v on v.placement_id=p.placement_id group by p.candidate_id
)
select a.partner_id,
       count(distinct a.candidate_id) as attributed_leads,
       count(distinct a.candidate_id) filter(where coalesce(s.starts,0)>0) as started_candidates,
       coalesce(sum(c.collected_amount),0)::numeric as collected_revenue,
       case when count(distinct a.candidate_id)=0 then null else round((count(distinct a.candidate_id) filter(where coalesce(s.starts,0)>0)::numeric/count(distinct a.candidate_id)::numeric)*100,4) end as start_conversion_percent
from attr a left join starts s on s.candidate_id=a.candidate_id left join collected c on c.candidate_id=a.candidate_id group by a.partner_id;

create or replace view analytics.finance_monthly_v as
with journal as (
  select date_trunc('month',jb.journal_date)::date as month_start,
         sum(jl.debit)::numeric as posted_debit,sum(jl.credit)::numeric as posted_credit,
         sum(case when a.account_type='Revenue' then jl.credit-jl.debit else 0 end)::numeric as revenue_amount,
         sum(case when a.account_type='Expense' then jl.debit-jl.credit else 0 end)::numeric as expense_amount
  from finance.journal_batches jb join finance.journal_lines jl on jl.journal_batch_id=jb.journal_batch_id join finance.accounts a on a.account_code=jl.account_code
  where jb.status='POSTED' group by 1
), cls as (
  select close_month as month_start,count(*) as check_count,count(*) filter(where status in ('PASS','WAIVED')) as satisfied_count,count(*) filter(where status='ISSUE') as issue_count
  from finance.monthly_close_checks group by close_month
)
select m.month_start,
       coalesce(j.posted_debit,0)::numeric as posted_debit,coalesce(j.posted_credit,0)::numeric as posted_credit,
       coalesce(j.revenue_amount,0)::numeric as revenue_amount,coalesce(j.expense_amount,0)::numeric as expense_amount,
       (coalesce(j.revenue_amount,0)-coalesce(j.expense_amount,0))::numeric as net_result,
       case when coalesce(c.check_count,0)=6 and c.satisfied_count=6 and coalesce(c.issue_count,0)=0 then 'CLOSED' else 'PROVISIONAL' end as accounting_close_status,
       case when coalesce(j.posted_debit,0)=coalesce(j.posted_credit,0) then 'BALANCED' else 'BLOCKED' end as journal_balance_status
from (select distinct month_start from analytics.dim_date) m left join journal j using(month_start) left join cls c using(month_start);

create or replace function analytics.evaluate_kpi_v2(p_kpi_id text,p_as_of timestamptz default now(),p_allow_test_shadow boolean default false)
returns table(kpi_id text,status text,as_of timestamptz,numerator numeric,denominator numeric,metric_value numeric,result_type text,blocked_reason text,source_object text)
language plpgsql security definer set search_path=''
as $function$
declare v_rt text;v_num numeric;v_den numeric;v_val numeric;v_amb numeric;v_cnt numeric;v_publish boolean;
begin
  select result_type into v_rt from analytics.kpi_catalog where kpi_id=p_kpi_id and active;
  if v_rt is null then raise exception 'UNKNOWN_KPI_ID'; end if;
  select coalesce((setting_value #>> '{}')::boolean,false) into v_publish from config.system_settings where setting_key='analytics_postgres_publish_enabled';
  if not p_allow_test_shadow and not coalesce(v_publish,false) then
    return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE','analytics.source_readiness_v';return;
  end if;
  case p_kpi_id
    when 'KPI-CAN-004' then
      select count(distinct candidate_id)::numeric into v_den from analytics.candidate_stage_events_v where upper(to_stage)='QUALIFIED' and occurred_at<=p_as_of;
      if coalesce(v_den,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'QUALIFIED_STAGE_HISTORY_UNAVAILABLE','analytics.candidate_stage_events_v';return;end if;
      select count(distinct p.candidate_id)::numeric into v_num from analytics.appointment_outcome_current_v a join core.placements p on p.placement_id=a.placement_id where a.appointment_at<=p_as_of;
      v_val:=round((coalesce(v_num,0)/v_den)*100,4);return query select p_kpi_id,'READY',p_as_of,coalesce(v_num,0),v_den,v_val,v_rt,null::text,'analytics.appointment_outcome_current_v';return;
    when 'KPI-CAN-005','KPI-CAN-006' then
      select count(*) filter(where outcome not in ('CANCELLED','RESCHEDULED'))::numeric,
             count(*) filter(where (p_kpi_id='KPI-CAN-005' and outcome='SHOW') or (p_kpi_id='KPI-CAN-006' and outcome='NO_SHOW'))::numeric,
             count(*) filter(where outcome in ('UNKNOWN','NEEDS_REVIEW') or verified=false)::numeric
      into v_den,v_num,v_amb from analytics.appointment_outcome_current_v where appointment_at<=p_as_of;
      if coalesce(v_den,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'NO_OCCURRED_APPOINTMENT_COHORT','analytics.appointment_outcome_current_v';return;
      elsif coalesce(v_amb,0)>0 then return query select p_kpi_id,'NOT_READY',p_as_of,v_num,v_den,null::numeric,v_rt,'APPOINTMENT_OUTCOME_AMBIGUOUS_OR_UNVERIFIED','analytics.appointment_outcome_current_v';return;end if;
      v_val:=round((v_num/v_den)*100,4);return query select p_kpi_id,'READY',p_as_of,v_num,v_den,v_val,v_rt,null::text,'analytics.appointment_outcome_current_v';return;
    when 'KPI-PAR-001' then
      select count(distinct candidate_id)::numeric into v_num from analytics.partner_attribution_current_v where data_ready and latest_approved_at<=p_as_of;
      select count(*)::numeric into v_cnt from analytics.partner_attribution_fact where attributed_at<=p_as_of;
      if coalesce(v_cnt,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'ATTRIBUTION_FACTS_UNAVAILABLE','analytics.partner_attribution_current_v';return;end if;
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_rt,null::text,'analytics.partner_attribution_current_v';return;
    when 'KPI-PAR-002' then
      select count(distinct p.placement_id)::numeric into v_num from analytics.partner_attribution_current_v a join core.placements p on p.candidate_id=a.candidate_id where a.data_ready and p.start_date is not null and p.start_date<=((p_as_of at time zone 'Asia/Bangkok')::date);
      select count(*)::numeric into v_cnt from analytics.partner_attribution_fact where attributed_at<=p_as_of;
      if coalesce(v_cnt,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'ATTRIBUTION_FACTS_UNAVAILABLE','analytics.partner_attribution_current_v';return;end if;
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_rt,null::text,'analytics.partner_attribution_current_v';return;
    when 'KPI-PAR-003' then
      select count(distinct candidate_id)::numeric into v_den from analytics.partner_attribution_current_v where data_ready and latest_approved_at<=p_as_of;
      if coalesce(v_den,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'NO_APPROVED_PARTNER_LEAD_COHORT','analytics.partner_attribution_current_v';return;end if;
      select count(distinct a.candidate_id)::numeric into v_num from analytics.partner_attribution_current_v a join core.placements p on p.candidate_id=a.candidate_id where a.data_ready and p.start_date is not null and p.start_date<=((p_as_of at time zone 'Asia/Bangkok')::date);
      v_val:=round((v_num/v_den)*100,4);return query select p_kpi_id,'READY',p_as_of,v_num,v_den,v_val,v_rt,null::text,'analytics.partner_attribution_current_v';return;
    else return query select * from analytics.evaluate_kpi(p_kpi_id,p_as_of,p_allow_test_shadow);return;
  end case;
end
$function$;

revoke all on analytics.appointment_outcome_current_v,analytics.partner_attribution_current_v,analytics.candidate_funnel_period_v,analytics.partner_performance_v,analytics.finance_monthly_v from public,anon,authenticated;
grant select on analytics.appointment_outcome_current_v,analytics.partner_attribution_current_v,analytics.candidate_funnel_period_v,analytics.partner_performance_v,analytics.finance_monthly_v to service_role;
revoke all on function analytics.evaluate_kpi_v2(text,timestamptz,boolean) from public,anon,authenticated;
grant execute on function analytics.evaluate_kpi_v2(text,timestamptz,boolean) to service_role;