create or replace view analytics.candidate_current_v as
select c.candidate_id,
       c.status as current_status,
       c.source_type,
       c.partner_id,
       c.origin_province,
       c.preferred_job,
       c.relocation_ready,
       c.ready_date,
       c.documents_ready,
       c.medical_ready,
       c.next_action,
       c.created_at,
       c.updated_at
from core.candidates c;

create or replace view analytics.candidate_stage_events_v as
select f.transition_pk,
       f.entity_id as candidate_id,
       f.from_stage,
       f.to_stage,
       f.occurred_at,
       f.source_event_pk,
       f.raw_input_id,
       f.evidence_id,
       f.actor_service,
       f.valid_transition,
       f.source_kind,
       f.created_at
from analytics.stage_transition_fact f
where upper(f.entity_type)='CANDIDATE' and f.valid_transition=true;

create or replace view analytics.placement_cohort_v as
select p.placement_id,
       p.candidate_id,
       p.job_id,
       p.start_date,
       ((p.start_date is not null) and p.start_date <= ((now() at time zone 'Asia/Bangkok')::date - 7)) as eligible_d7,
       d7.outcome as d7_outcome,
       ((p.start_date is not null) and p.start_date <= ((now() at time zone 'Asia/Bangkok')::date - 30)) as eligible_d30,
       d30.outcome as d30_outcome,
       ((p.start_date is not null) and p.start_date <= ((now() at time zone 'Asia/Bangkok')::date - 90)) as eligible_d90,
       d90.outcome as d90_outcome,
       ((p.start_date is not null) and p.start_date <= ((now() at time zone 'Asia/Bangkok')::date - 120)) as eligible_d120,
       d120.outcome as d120_outcome,
       p.dropout_reason,
       p.status as current_placement_status
from core.placements p
left join lateral (
  select m.outcome from analytics.placement_milestone_fact m
  where m.placement_id=p.placement_id and m.milestone='D7'
  order by m.observed_at desc,m.created_at desc limit 1
) d7 on true
left join lateral (
  select m.outcome from analytics.placement_milestone_fact m
  where m.placement_id=p.placement_id and m.milestone='D30'
  order by m.observed_at desc,m.created_at desc limit 1
) d30 on true
left join lateral (
  select m.outcome from analytics.placement_milestone_fact m
  where m.placement_id=p.placement_id and m.milestone='D90'
  order by m.observed_at desc,m.created_at desc limit 1
) d90 on true
left join lateral (
  select m.outcome from analytics.placement_milestone_fact m
  where m.placement_id=p.placement_id and m.milestone='D120'
  order by m.observed_at desc,m.created_at desc limit 1
) d120 on true;

create or replace view analytics.job_demand_v as
select j.job_id,
       j.client_id,
       j.position_name,
       j.province,
       j.area,
       j.status as job_status,
       j.headcount as requested_headcount,
       count(p.placement_id) filter (where p.start_date is not null) as verified_fill_count,
       case when j.headcount is null then null
            else greatest(j.headcount - count(p.placement_id) filter (where p.start_date is not null),0)::integer end as open_headcount,
       (j.headcount is not null) as data_ready,
       case when j.headcount is null then 'CONFIRMED_HEADCOUNT_MISSING' end as blocked_reason,
       j.last_confirmed_at,
       j.updated_at
from core.jobs j
left join core.placements p on p.job_id=j.job_id
group by j.job_id,j.client_id,j.position_name,j.province,j.area,j.status,j.headcount,j.last_confirmed_at,j.updated_at;

create or replace view analytics.finance_collected_official_v as
select r.revenue_id,
       r.client_id,
       r.placement_id,
       r.collection_date,
       r.net_received,
       r.payment_ref,
       r.collection_evidence_id as evidence_id,
       r.collection_bank_txn_id as bank_txn_id,
       b.txn_at,
       b.amount as bank_amount,
       b.reconciled,
       e.verification_status as evidence_verification_status
from finance.revenue r
join finance.bank_transactions b on b.bank_txn_id=r.collection_bank_txn_id
join docs.evidence e on e.evidence_id=r.collection_evidence_id
where r.status='COLLECTED'
  and r.collection_date is not null
  and r.net_received is not null
  and r.payment_ref is not null
  and b.direction='IN'
  and b.reconciled=true
  and b.revenue_id=r.revenue_id
  and b.amount=r.net_received
  and e.verification_status='VERIFIED';

create or replace view analytics.data_quality_v as
select 'OPEN_CRITICAL_DQ'::text as metric_key,
       count(*)::numeric as metric_value,
       max(d.created_at) as latest_at,
       null::text as blocked_reason
from ops.data_quality_issues d
where upper(coalesce(d.severity,'')) in ('HIGH','CRITICAL')
  and upper(coalesce(d.status,'')) in ('OPEN','IN_REVIEW')
union all
select 'UNPROCESSED_RAW_INPUT',
       count(*)::numeric,
       max(r.received_at),
       null::text
from ops.raw_inputs r
where upper(coalesce(r.processing_status,'')) not in ('COMPLETED','REVIEWED','NO_OP','CANCELLED','REJECTED')
union all
select 'AUTOMATION_DEAD_LETTER',
       count(*)::numeric,
       max(d.failed_at),
       null::text
from ops.dead_letters d
join ops.events e on e.event_pk=d.event_pk
where e.processing_state::text='DEAD_LETTER';

create or replace view analytics.source_readiness_v as
select s.source_key,s.source_type,s.last_source_at,s.last_refresh_at,s.freshness_window_minutes,
       case when s.readiness_status='READY' and s.freshness_window_minutes is not null and s.last_refresh_at is not null
                  and s.last_refresh_at < now() - make_interval(mins=>s.freshness_window_minutes)
            then 'STALE'
            else s.readiness_status end as readiness_status,
       case when s.readiness_status='READY' and s.freshness_window_minutes is not null and s.last_refresh_at is not null
                  and s.last_refresh_at < now() - make_interval(mins=>s.freshness_window_minutes)
            then 'SOURCE_REFRESH_STALE'
            else s.blocked_reason end as blocked_reason,
       s.source_ref,s.updated_at
from analytics.source_freshness s;

create or replace function analytics.evaluate_kpi(
  p_kpi_id text,
  p_as_of timestamptz default now(),
  p_allow_test_shadow boolean default false
)
returns table(
  kpi_id text,
  status text,
  as_of timestamptz,
  numerator numeric,
  denominator numeric,
  metric_value numeric,
  result_type text,
  blocked_reason text,
  source_object text
)
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_result_type text;
  v_num numeric;
  v_den numeric;
  v_val numeric;
  v_count numeric;
  v_missing numeric;
  v_source_ready boolean;
begin
  select k.result_type into v_result_type from analytics.kpi_catalog k where k.kpi_id=p_kpi_id and k.active=true;
  if v_result_type is null then
    raise exception 'UNKNOWN_KPI_ID';
  end if;

  select coalesce((setting_value #>> '{}')::boolean,false)
  into v_source_ready
  from config.system_settings where setting_key='analytics_postgres_publish_enabled';
  v_source_ready:=coalesce(v_source_ready,false);

  if not p_allow_test_shadow and not v_source_ready then
    return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_result_type,
      'POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE'::text,'analytics.source_readiness_v'::text;
    return;
  end if;

  case p_kpi_id
    when 'KPI-CLI-001' then
      select count(*)::numeric into v_num from core.clients where upper(coalesce(crm_status,''))='ACTIVE';
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_result_type,null::text,'core.clients'::text;

    when 'KPI-CAN-001' then
      select count(distinct coalesce(entity_id,event_id))::numeric into v_num
      from ops.events
      where event_type='candidate.lead.received' and occurred_at<=p_as_of;
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_result_type,null::text,'ops.events'::text;

    when 'KPI-CAN-002' then
      select count(distinct candidate_id)::numeric into v_num
      from analytics.candidate_stage_events_v
      where upper(to_stage)='QUALIFIED' and occurred_at<=p_as_of;
      select count(*)::numeric into v_count from analytics.candidate_stage_events_v where occurred_at<=p_as_of;
      if v_count=0 then
        return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_result_type,
          'STAGE_TRANSITION_HISTORY_UNAVAILABLE'::text,'analytics.candidate_stage_events_v'::text;
      else
        return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_result_type,null::text,'analytics.candidate_stage_events_v'::text;
      end if;

    when 'KPI-CAN-003' then
      with leads as (
        select candidate_id,min(occurred_at) lead_at
        from analytics.candidate_stage_events_v
        where upper(to_stage)='LEAD' and occurred_at<=p_as_of
        group by candidate_id
      ), qualified as (
        select candidate_id,min(occurred_at) qualified_at
        from analytics.candidate_stage_events_v
        where upper(to_stage)='QUALIFIED' and occurred_at<=p_as_of
        group by candidate_id
      )
      select count(*)::numeric,
             count(*) filter(where q.qualified_at is not null and q.qualified_at>=l.lead_at)::numeric
      into v_den,v_num
      from leads l left join qualified q using(candidate_id);
      if coalesce(v_den,0)=0 then
        return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_result_type,
          'LEAD_COHORT_OR_STAGE_HISTORY_UNAVAILABLE'::text,'analytics.candidate_stage_events_v'::text;
      else
        v_val:=round((v_num/v_den)*100,4);
        return query select p_kpi_id,'READY',p_as_of,v_num,v_den,v_val,v_result_type,null::text,'analytics.candidate_stage_events_v'::text;
      end if;

    when 'KPI-RET-001','KPI-RET-002','KPI-RET-003' then
      if p_kpi_id='KPI-RET-001' then
        select count(*)::numeric,
               count(*) filter(where m.outcome in ('ACTIVE','PASS'))::numeric,
               count(*) filter(where m.outcome is null)::numeric
        into v_den,v_num,v_missing
        from core.placements p
        left join lateral (
          select outcome from analytics.placement_milestone_fact m
          where m.placement_id=p.placement_id and m.milestone='D7' and m.observed_at<=p_as_of
          order by m.observed_at desc,m.created_at desc limit 1
        ) m on true
        where p.start_date is not null and p.start_date <= ((p_as_of at time zone 'Asia/Bangkok')::date - 7);
      elsif p_kpi_id='KPI-RET-002' then
        select count(*)::numeric,
               count(*) filter(where m.outcome in ('ACTIVE','PASS'))::numeric,
               count(*) filter(where m.outcome is null)::numeric
        into v_den,v_num,v_missing
        from core.placements p
        left join lateral (
          select outcome from analytics.placement_milestone_fact m
          where m.placement_id=p.placement_id and m.milestone='D30' and m.observed_at<=p_as_of
          order by m.observed_at desc,m.created_at desc limit 1
        ) m on true
        where p.start_date is not null and p.start_date <= ((p_as_of at time zone 'Asia/Bangkok')::date - 30);
      else
        select count(*)::numeric,
               count(*) filter(where m.outcome in ('ACTIVE','PASS'))::numeric,
               count(*) filter(where m.outcome is null)::numeric
        into v_den,v_num,v_missing
        from core.placements p
        left join lateral (
          select outcome from analytics.placement_milestone_fact m
          where m.placement_id=p.placement_id and m.milestone='D90' and m.observed_at<=p_as_of
          order by m.observed_at desc,m.created_at desc limit 1
        ) m on true
        where p.start_date is not null and p.start_date <= ((p_as_of at time zone 'Asia/Bangkok')::date - 90);
      end if;
      if coalesce(v_den,0)=0 then
        return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_result_type,
          'NO_ELIGIBLE_MATURE_COHORT'::text,'analytics.placement_milestone_fact'::text;
      elsif coalesce(v_missing,0)>0 then
        return query select p_kpi_id,'NOT_READY',p_as_of,v_num,v_den,null::numeric,v_result_type,
          'ELIGIBLE_COHORT_HAS_MISSING_MILESTONE_OUTCOME'::text,'analytics.placement_milestone_fact'::text;
      else
        v_val:=round((v_num/v_den)*100,4);
        return query select p_kpi_id,'READY',p_as_of,v_num,v_den,v_val,v_result_type,null::text,'analytics.placement_milestone_fact'::text;
      end if;

    when 'KPI-FIN-004' then
      select coalesce(sum(net_received),0)::numeric into v_num from analytics.finance_collected_official_v where collection_date <= (p_as_of at time zone 'Asia/Bangkok')::date;
      select count(*)::numeric into v_missing
      from finance.revenue r
      where r.status='COLLECTED' and r.collection_date <= (p_as_of at time zone 'Asia/Bangkok')::date
        and not exists (select 1 from analytics.finance_collected_official_v v where v.revenue_id=r.revenue_id);
      if coalesce(v_missing,0)>0 then
        return query select p_kpi_id,'PARTIAL',p_as_of,v_num,null::numeric,v_num,v_result_type,
          'UNVERIFIED_OR_UNMATCHED_COLLECTED_ROWS_EXCLUDED'::text,'analytics.finance_collected_official_v'::text;
      else
        return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_result_type,null::text,'analytics.finance_collected_official_v'::text;
      end if;

    when 'KPI-DQ-001' then
      select metric_value into v_num from analytics.data_quality_v where metric_key='OPEN_CRITICAL_DQ';
      return query select p_kpi_id,'READY',p_as_of,coalesce(v_num,0),null::numeric,coalesce(v_num,0),v_result_type,null::text,'analytics.data_quality_v'::text;

    when 'KPI-DQ-002' then
      select metric_value into v_num from analytics.data_quality_v where metric_key='UNPROCESSED_RAW_INPUT';
      return query select p_kpi_id,'READY',p_as_of,coalesce(v_num,0),null::numeric,coalesce(v_num,0),v_result_type,null::text,'analytics.data_quality_v'::text;

    when 'KPI-OPS-002' then
      select metric_value into v_num from analytics.data_quality_v where metric_key='AUTOMATION_DEAD_LETTER';
      return query select p_kpi_id,'READY',p_as_of,coalesce(v_num,0),null::numeric,coalesce(v_num,0),v_result_type,null::text,'analytics.data_quality_v'::text;

    else
      return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_result_type,
        'KPI_RUNTIME_IMPLEMENTATION_NOT_INCLUDED_IN_PART6A'::text,'analytics.kpi_catalog'::text;
  end case;
end
$function$;

revoke all on function analytics.evaluate_kpi(text,timestamptz,boolean) from public,anon,authenticated;
grant execute on function analytics.evaluate_kpi(text,timestamptz,boolean) to service_role;

revoke all on analytics.candidate_current_v,analytics.candidate_stage_events_v,analytics.placement_cohort_v,analytics.job_demand_v,analytics.finance_collected_official_v,analytics.data_quality_v,analytics.source_readiness_v from public,anon,authenticated;
grant select on analytics.candidate_current_v,analytics.candidate_stage_events_v,analytics.placement_cohort_v,analytics.job_demand_v,analytics.finance_collected_official_v,analytics.data_quality_v,analytics.source_readiness_v to service_role;