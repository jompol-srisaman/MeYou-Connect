do $$ declare t text; begin
 foreach t in array array['alert_rule_catalog','alert_routes','alert_instances','alert_occurrences','incidents','incident_timeline','alert_delivery_queue'] loop
   execute format('alter table ops.%I enable row level security',t);
   execute format('revoke all on ops.%I from anon, authenticated',t);
   execute format('drop policy if exists %I on ops.%I','deny_client_direct_'||t,t);
   execute format('create policy %I on ops.%I for all to anon, authenticated using (false) with check (false)','deny_client_direct_'||t,t);
   execute format('grant select,insert,update,delete on ops.%I to service_role',t);
 end loop;
end $$;

create or replace function api.observability_alerts(p_status text default null)
returns table(alert_pk uuid,signal_key text,severity text,status text,owner_role text,summary text,affected_count bigint,occurrence_count bigint,first_seen_at timestamptz,last_seen_at timestamptz,incident_pk uuid,delivery_state text)
language plpgsql security definer set search_path='' as $$
begin
 perform authz.require_capability('security_read');
 return query
 select a.alert_pk,a.signal_key,a.severity,a.status,a.owner_role,a.summary,a.affected_count,a.occurrence_count,a.first_seen_at,a.last_seen_at,
        i.incident_pk,
        case when exists(select 1 from ops.alert_delivery_queue q where q.alert_pk=a.alert_pk and q.delivery_status='READY') then 'READY'
             when exists(select 1 from ops.alert_delivery_queue q where q.alert_pk=a.alert_pk and q.delivery_status='SENT') then 'SENT'
             when exists(select 1 from ops.alert_delivery_queue q where q.alert_pk=a.alert_pk) then 'HELD'
             else 'NO_ROUTE' end
 from ops.alert_instances a left join ops.incidents i on i.alert_pk=a.alert_pk and i.status<>'CLOSED'
 where (p_status is null or a.status=p_status) order by ops.severity_rank(a.severity),a.last_seen_at desc;
end $$;

create or replace function api.observability_incidents(p_status text default null)
returns table(incident_pk uuid,severity text,status text,owner_role text,owner_identity_ref text,title text,declared_at timestamptz,ack_due_at timestamptz,acknowledged_at timestamptz,contained_at timestamptz,resolved_at timestamptz,risk_ref text)
language plpgsql security definer set search_path='' as $$
begin
 perform authz.require_capability('security_read');
 return query select i.incident_pk,i.severity,i.status,i.owner_role,i.owner_identity_ref,i.title,i.declared_at,i.ack_due_at,i.acknowledged_at,i.contained_at,i.resolved_at,i.risk_ref
 from ops.incidents i where (p_status is null or i.status=p_status) order by ops.severity_rank(i.severity),i.declared_at desc;
end $$;

create or replace function api.observability_route_readiness()
returns table(environment text,owner_role text,channel_type text,route_active boolean,verified boolean,external_delivery_enabled boolean,readiness text)
language plpgsql security definer set search_path='' as $$
begin
 perform authz.require_capability('security_audit_read');
 return query select r.environment,r.owner_role,r.channel_type,r.active,r.verified,config.setting_is_true('security_external_alert_delivery_enabled'),
  case when not r.active then 'DISABLED' when not r.verified then 'UNVERIFIED' when not config.setting_is_true('security_external_alert_delivery_enabled') then 'HELD' else 'READY' end
 from ops.alert_routes r order by r.environment,r.owner_role,r.channel_type;
end $$;

create or replace function api.observability_foundation_status()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v jsonb;
begin
 perform authz.require_capability('security_read');
 select jsonb_build_object(
  'part5c_foundation_ready',to_regclass('ops.alert_instances') is not null and to_regclass('ops.incidents') is not null,
  'open_alerts',(select count(*) from ops.alert_instances where status in ('OPEN','ACKNOWLEDGED')),
  'open_incidents',(select count(*) from ops.incidents where status<>'CLOSED'),
  'verified_external_routes',(select count(*) from ops.alert_routes where verified=true and active=true and channel_type<>'DB_ONLY'),
  'external_delivery_enabled',config.setting_is_true('security_external_alert_delivery_enabled'),
  'production_cutover_approved',config.setting_is_true('production_cutover_approved'),
  'operational_source',(select setting_value from config.system_settings where setting_key='current_operational_source')
 ) into v;
 return v;
end $$;

revoke all on function api.observability_alerts(text) from public,anon;
revoke all on function api.observability_incidents(text) from public,anon;
revoke all on function api.observability_route_readiness() from public,anon;
revoke all on function api.observability_foundation_status() from public,anon;
grant execute on function api.observability_alerts(text) to authenticated,service_role;
grant execute on function api.observability_incidents(text) to authenticated,service_role;
grant execute on function api.observability_route_readiness() to authenticated,service_role;
grant execute on function api.observability_foundation_status() to authenticated,service_role;