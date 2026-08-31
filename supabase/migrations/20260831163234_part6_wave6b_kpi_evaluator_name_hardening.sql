create or replace function analytics.evaluate_kpi_v2(p_kpi_id text,p_as_of timestamptz default now(),p_allow_test_shadow boolean default false)
returns table(kpi_id text,status text,as_of timestamptz,numerator numeric,denominator numeric,metric_value numeric,result_type text,blocked_reason text,source_object text)
language plpgsql security definer set search_path=''
as $function$
declare v_rt text;v_num numeric;v_den numeric;v_val numeric;v_amb numeric;v_cnt numeric;v_publish boolean;
begin
  select k.result_type into v_rt from analytics.kpi_catalog k where k.kpi_id=p_kpi_id and k.active;
  if v_rt is null then raise exception 'UNKNOWN_KPI_ID'; end if;
  select coalesce((s.setting_value #>> '{}')::boolean,false) into v_publish from config.system_settings s where s.setting_key='analytics_postgres_publish_enabled';
  if not p_allow_test_shadow and not coalesce(v_publish,false) then
    return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'POSTGRES_ANALYTICS_IS_TEST_SHADOW_NOT_OPERATIONAL_SOURCE','analytics.source_readiness_v';return;
  end if;
  case p_kpi_id
    when 'KPI-CAN-004' then
      select count(distinct v.candidate_id)::numeric into v_den from analytics.candidate_stage_events_v v where upper(v.to_stage)='QUALIFIED' and v.occurred_at<=p_as_of;
      if coalesce(v_den,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'QUALIFIED_STAGE_HISTORY_UNAVAILABLE','analytics.candidate_stage_events_v';return;end if;
      select count(distinct p.candidate_id)::numeric into v_num from analytics.appointment_outcome_current_v a join core.placements p on p.placement_id=a.placement_id where a.appointment_at<=p_as_of;
      v_val:=round((coalesce(v_num,0)/v_den)*100,4);return query select p_kpi_id,'READY',p_as_of,coalesce(v_num,0),v_den,v_val,v_rt,null::text,'analytics.appointment_outcome_current_v';return;
    when 'KPI-CAN-005','KPI-CAN-006' then
      select count(*) filter(where a.outcome not in ('CANCELLED','RESCHEDULED'))::numeric,
             count(*) filter(where (p_kpi_id='KPI-CAN-005' and a.outcome='SHOW') or (p_kpi_id='KPI-CAN-006' and a.outcome='NO_SHOW'))::numeric,
             count(*) filter(where a.outcome in ('UNKNOWN','NEEDS_REVIEW') or a.verified=false)::numeric
      into v_den,v_num,v_amb from analytics.appointment_outcome_current_v a where a.appointment_at<=p_as_of;
      if coalesce(v_den,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'NO_OCCURRED_APPOINTMENT_COHORT','analytics.appointment_outcome_current_v';return;
      elsif coalesce(v_amb,0)>0 then return query select p_kpi_id,'NOT_READY',p_as_of,v_num,v_den,null::numeric,v_rt,'APPOINTMENT_OUTCOME_AMBIGUOUS_OR_UNVERIFIED','analytics.appointment_outcome_current_v';return;end if;
      v_val:=round((v_num/v_den)*100,4);return query select p_kpi_id,'READY',p_as_of,v_num,v_den,v_val,v_rt,null::text,'analytics.appointment_outcome_current_v';return;
    when 'KPI-PAR-001' then
      select count(distinct a.candidate_id)::numeric into v_num from analytics.partner_attribution_current_v a where a.data_ready and a.latest_approved_at<=p_as_of;
      select count(*)::numeric into v_cnt from analytics.partner_attribution_fact a where a.attributed_at<=p_as_of;
      if coalesce(v_cnt,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'ATTRIBUTION_FACTS_UNAVAILABLE','analytics.partner_attribution_current_v';return;end if;
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_rt,null::text,'analytics.partner_attribution_current_v';return;
    when 'KPI-PAR-002' then
      select count(distinct p.placement_id)::numeric into v_num from analytics.partner_attribution_current_v a join core.placements p on p.candidate_id=a.candidate_id where a.data_ready and p.start_date is not null and p.start_date<=((p_as_of at time zone 'Asia/Bangkok')::date);
      select count(*)::numeric into v_cnt from analytics.partner_attribution_fact a where a.attributed_at<=p_as_of;
      if coalesce(v_cnt,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'ATTRIBUTION_FACTS_UNAVAILABLE','analytics.partner_attribution_current_v';return;end if;
      return query select p_kpi_id,'READY',p_as_of,v_num,null::numeric,v_num,v_rt,null::text,'analytics.partner_attribution_current_v';return;
    when 'KPI-PAR-003' then
      select count(distinct a.candidate_id)::numeric into v_den from analytics.partner_attribution_current_v a where a.data_ready and a.latest_approved_at<=p_as_of;
      if coalesce(v_den,0)=0 then return query select p_kpi_id,'NOT_READY',p_as_of,null::numeric,null::numeric,null::numeric,v_rt,'NO_APPROVED_PARTNER_LEAD_COHORT','analytics.partner_attribution_current_v';return;end if;
      select count(distinct a.candidate_id)::numeric into v_num from analytics.partner_attribution_current_v a join core.placements p on p.candidate_id=a.candidate_id where a.data_ready and p.start_date is not null and p.start_date<=((p_as_of at time zone 'Asia/Bangkok')::date);
      v_val:=round((v_num/v_den)*100,4);return query select p_kpi_id,'READY',p_as_of,v_num,v_den,v_val,v_rt,null::text,'analytics.partner_attribution_current_v';return;
    else return query select * from analytics.evaluate_kpi(p_kpi_id,p_as_of,p_allow_test_shadow);return;
  end case;
end
$function$;
revoke all on function analytics.evaluate_kpi_v2(text,timestamptz,boolean) from public,anon,authenticated;
grant execute on function analytics.evaluate_kpi_v2(text,timestamptz,boolean) to service_role;