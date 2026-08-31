do $policies$
declare t text;
begin
  foreach t in array array['appointment_outcome_fact','partner_attribution_fact'] loop
    execute format('drop policy if exists %I on analytics.%I','deny_client_'||t,t);
    execute format('create policy %I on analytics.%I as restrictive for all to anon,authenticated using (false) with check (false)','deny_client_'||t,t);
  end loop;
end
$policies$;

create or replace function api.analytics_kpi_result(p_kpi_id text)
returns table(kpi_id text,status text,as_of timestamptz,numerator numeric,denominator numeric,metric_value numeric,result_type text,blocked_reason text,source_object text)
language plpgsql security definer set search_path=''
as $function$
begin
  perform authz.require_capability('analytics_read');
  return query select * from analytics.evaluate_kpi_v2(p_kpi_id,now(),false);
end
$function$;

create or replace function api.analytics_kpi_drillthrough(p_kpi_id text,p_limit integer default 100)
returns table(kpi_id text,entity_type text,entity_id text,related_entity_id text,evidence_id text,raw_input_id text,occurred_at timestamptz,source_object text)
language plpgsql security definer set search_path=''
as $function$
declare v_publish boolean;v_limit integer;
begin
  perform authz.require_capability('analytics_read');
  select coalesce((setting_value #>> '{}')::boolean,false) into v_publish from config.system_settings where setting_key='analytics_postgres_publish_enabled';
  if not coalesce(v_publish,false) then return; end if;
  v_limit:=least(greatest(coalesce(p_limit,100),1),500);
  case p_kpi_id
    when 'KPI-FIN-004' then
      return query select p_kpi_id,'REVENUE',v.revenue_id,v.placement_id,v.evidence_id,null::text,v.txn_at,'analytics.finance_collected_official_v' from analytics.finance_collected_official_v v order by v.txn_at desc limit v_limit;
    when 'KPI-CAN-006' then
      return query select p_kpi_id,'PLACEMENT',a.placement_id,p.candidate_id,a.evidence_id,a.raw_input_id,a.appointment_at,'analytics.appointment_outcome_current_v' from analytics.appointment_outcome_current_v a join core.placements p on p.placement_id=a.placement_id where a.outcome='NO_SHOW' order by a.appointment_at desc limit v_limit;
    when 'KPI-CAN-005' then
      return query select p_kpi_id,'PLACEMENT',a.placement_id,p.candidate_id,a.evidence_id,a.raw_input_id,a.appointment_at,'analytics.appointment_outcome_current_v' from analytics.appointment_outcome_current_v a join core.placements p on p.placement_id=a.placement_id where a.outcome='SHOW' order by a.appointment_at desc limit v_limit;
    when 'KPI-RET-002' then
      return query select p_kpi_id,'PLACEMENT',m.placement_id,p.candidate_id,m.evidence_id,m.raw_input_id,m.observed_at,'analytics.placement_milestone_fact' from analytics.placement_milestone_fact m join core.placements p on p.placement_id=m.placement_id where m.milestone='D30' order by m.observed_at desc limit v_limit;
    when 'KPI-PAR-001' then
      return query select p_kpi_id,'CANDIDATE',a.candidate_id,a.partner_id,a.evidence_id,a.raw_input_id,a.attributed_at,'analytics.partner_attribution_fact' from analytics.partner_attribution_fact a where a.attribution_status='APPROVED' order by a.attributed_at desc limit v_limit;
    else return;
  end case;
end
$function$;

create or replace function api.analytics_finance_monthly(p_month date)
returns table(month_start date,posted_debit numeric,posted_credit numeric,revenue_amount numeric,expense_amount numeric,net_result numeric,accounting_close_status text,journal_balance_status text)
language plpgsql security definer set search_path=''
as $function$
declare v_publish boolean;
begin
  perform authz.require_capability('analytics_read');
  select coalesce((setting_value #>> '{}')::boolean,false) into v_publish from config.system_settings where setting_key='analytics_postgres_publish_enabled';
  if not coalesce(v_publish,false) then return; end if;
  return query select f.month_start,f.posted_debit,f.posted_credit,f.revenue_amount,f.expense_amount,f.net_result,f.accounting_close_status,f.journal_balance_status from analytics.finance_monthly_v f where f.month_start=date_trunc('month',p_month)::date;
end
$function$;

revoke all on function api.analytics_kpi_result(text) from public,anon;
revoke all on function api.analytics_kpi_drillthrough(text,integer) from public,anon;
revoke all on function api.analytics_finance_monthly(date) from public,anon;
grant execute on function api.analytics_kpi_result(text) to authenticated,service_role;
grant execute on function api.analytics_kpi_drillthrough(text,integer) to authenticated,service_role;
grant execute on function api.analytics_finance_monthly(date) to authenticated,service_role;