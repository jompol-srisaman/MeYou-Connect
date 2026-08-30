alter table ops.alert_occurrences drop constraint if exists alert_occurrences_alert_pk_fkey;
alter table ops.alert_occurrences add constraint alert_occurrences_alert_pk_fkey foreign key(alert_pk) references ops.alert_instances(alert_pk) on delete restrict;
alter table ops.incident_timeline drop constraint if exists incident_timeline_incident_pk_fkey;
alter table ops.incident_timeline add constraint incident_timeline_incident_pk_fkey foreign key(incident_pk) references ops.incidents(incident_pk) on delete restrict;
alter table ops.alert_delivery_queue drop constraint if exists alert_delivery_queue_alert_pk_fkey;
alter table ops.alert_delivery_queue add constraint alert_delivery_queue_alert_pk_fkey foreign key(alert_pk) references ops.alert_instances(alert_pk) on delete restrict;
alter table ops.incidents add column if not exists risk_ref text;

create or replace function ops.severity_rank(p_severity text)
returns integer language sql immutable set search_path='' as $$
 select case p_severity when 'SEV0' then 0 when 'SEV1' then 1 when 'SEV2' then 2 when 'SEV3' then 3 else 99 end;
$$;

create or replace function ops.ingest_alert_signal(
 p_environment text,
 p_signal_key text,
 p_fingerprint text,
 p_severity text,
 p_summary text,
 p_affected_count bigint default 1,
 p_source_ref text default null,
 p_metadata jsonb default '{}'::jsonb,
 p_observed_at timestamptz default now()
) returns jsonb
language plpgsql security definer set search_path='' as $$
declare
 v_rule ops.alert_rule_catalog;
 v_alert ops.alert_instances;
 v_incident ops.incidents;
 v_owner text;
 v_auto boolean;
 v_ack_due timestamptz;
 v_route record;
 v_delivery text;
begin
 if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
 if p_signal_key is null or btrim(p_signal_key)='' then raise exception 'SIGNAL_KEY_REQUIRED'; end if;
 if p_fingerprint is null or btrim(p_fingerprint)='' then raise exception 'FINGERPRINT_REQUIRED'; end if;
 if p_severity not in ('SEV0','SEV1','SEV2','SEV3') then raise exception 'INVALID_SEVERITY'; end if;
 if p_summary is null or btrim(p_summary)='' then raise exception 'SUMMARY_REQUIRED'; end if;
 if p_affected_count < 0 then raise exception 'INVALID_AFFECTED_COUNT'; end if;
 if coalesce(p_metadata,'{}'::jsonb) ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token'] then raise exception 'SECRET_MATERIAL_NOT_ALLOWED'; end if;

 select * into v_rule from ops.alert_rule_catalog where source_signal_key=p_signal_key and active=true limit 1;
 v_owner:=coalesce(v_rule.owner_role,case when p_severity='SEV0' then 'founder' else 'automation_worker' end);
 v_auto:=coalesce(v_rule.auto_incident,p_severity in ('SEV0','SEV1'));

 select * into v_alert from ops.alert_instances
 where environment=p_environment and fingerprint=p_fingerprint and status in ('OPEN','ACKNOWLEDGED')
 for update;

 if found then
   update ops.alert_instances set
     severity=case when ops.severity_rank(p_severity)<ops.severity_rank(severity) then p_severity else severity end,
     affected_count=greatest(affected_count,p_affected_count), occurrence_count=occurrence_count+1,
     last_seen_at=greatest(last_seen_at,coalesce(p_observed_at,now())), summary=p_summary,
     source_ref=coalesce(p_source_ref,source_ref), metadata=metadata||coalesce(p_metadata,'{}'::jsonb), updated_at=now()
   where alert_pk=v_alert.alert_pk returning * into v_alert;
 else
   insert into ops.alert_instances(environment,alert_rule_key,signal_key,fingerprint,severity,owner_role,summary,affected_count,first_seen_at,last_seen_at,source_ref,metadata)
   values(p_environment,v_rule.alert_rule_key,p_signal_key,p_fingerprint,p_severity,v_owner,p_summary,p_affected_count,coalesce(p_observed_at,now()),coalesce(p_observed_at,now()),p_source_ref,coalesce(p_metadata,'{}'::jsonb))
   returning * into v_alert;
 end if;

 insert into ops.alert_occurrences(alert_pk,observed_at,severity,affected_count,source_ref,summary,metadata)
 values(v_alert.alert_pk,coalesce(p_observed_at,now()),p_severity,p_affected_count,p_source_ref,p_summary,coalesce(p_metadata,'{}'::jsonb));

 if v_auto and v_alert.severity in ('SEV0','SEV1') then
   select * into v_incident from ops.incidents where alert_pk=v_alert.alert_pk and status<>'CLOSED' limit 1;
   if not found then
     v_ack_due:=case v_alert.severity when 'SEV0' then now()+interval '15 minutes' when 'SEV1' then now()+interval '30 minutes' else null end;
     insert into ops.incidents(environment,alert_pk,severity,owner_role,title,declared_at,ack_due_at)
     values(p_environment,v_alert.alert_pk,v_alert.severity,v_alert.owner_role,p_summary,now(),v_ack_due)
     returning * into v_incident;
     insert into ops.incident_timeline(incident_pk,action_type,actor_ref,summary,evidence_ref)
     values(v_incident.incident_pk,'DECLARED','SYSTEM',p_summary,p_source_ref);
   elsif ops.severity_rank(v_alert.severity)<ops.severity_rank(v_incident.severity) then
     update ops.incidents set severity=v_alert.severity,
       ack_due_at=case v_alert.severity when 'SEV0' then least(coalesce(ack_due_at,now()+interval '15 minutes'),now()+interval '15 minutes') when 'SEV1' then least(coalesce(ack_due_at,now()+interval '30 minutes'),now()+interval '30 minutes') else ack_due_at end,
       updated_at=now() where incident_pk=v_incident.incident_pk returning * into v_incident;
     insert into ops.incident_timeline(incident_pk,action_type,actor_ref,summary) values(v_incident.incident_pk,'SEVERITY_ESCALATED','SYSTEM','Incident severity escalated to '||v_alert.severity);
   end if;
 end if;

 for v_route in select * from ops.alert_routes where environment=p_environment and owner_role=v_alert.owner_role and active=true loop
   v_delivery:=case when config.setting_is_true('security_external_alert_delivery_enabled') and v_route.verified then 'READY' else 'HELD' end;
   insert into ops.alert_delivery_queue(alert_pk,route_pk,delivery_status,hold_reason)
   values(v_alert.alert_pk,v_route.route_pk,v_delivery,case when v_delivery='HELD' then 'EXTERNAL_DELIVERY_DISABLED_OR_ROUTE_UNVERIFIED' end)
   on conflict (alert_pk,route_pk) where route_pk is not null do update set
     delivery_status=case when ops.alert_delivery_queue.delivery_status='SENT' then 'SENT' else excluded.delivery_status end,
     hold_reason=excluded.hold_reason,updated_at=now();
 end loop;

 return jsonb_build_object('alert_pk',v_alert.alert_pk,'alert_status',v_alert.status,'severity',v_alert.severity,'occurrence_count',v_alert.occurrence_count,'incident_pk',v_incident.incident_pk,'external_delivery_enabled',config.setting_is_true('security_external_alert_delivery_enabled'));
end $$;

create or replace function ops.transition_incident(
 p_incident_pk uuid,p_new_status text,p_actor_ref text,p_summary text,
 p_evidence_ref text default null,p_root_cause text default null,p_corrective_action text default null,p_risk_ref text default null
) returns ops.incidents
language plpgsql security definer set search_path='' as $$
declare v ops.incidents;
begin
 if p_actor_ref is null or btrim(p_actor_ref)='' then raise exception 'ACTOR_REQUIRED'; end if;
 if p_summary is null or btrim(p_summary)='' then raise exception 'SUMMARY_REQUIRED'; end if;
 select * into v from ops.incidents where incident_pk=p_incident_pk for update;
 if not found then raise exception 'INCIDENT_NOT_FOUND'; end if;
 if not ((v.status='OPEN' and p_new_status in ('ACKNOWLEDGED','CONTAINED')) or
         (v.status='ACKNOWLEDGED' and p_new_status in ('CONTAINED','RECOVERING')) or
         (v.status='CONTAINED' and p_new_status in ('RECOVERING','RESOLVED')) or
         (v.status='RECOVERING' and p_new_status='RESOLVED') or
         (v.status='RESOLVED' and p_new_status='CLOSED')) then raise exception 'INVALID_INCIDENT_TRANSITION:%->%',v.status,p_new_status; end if;
 if p_new_status='CLOSED' and (coalesce(p_evidence_ref,v.evidence_ref) is null or coalesce(p_root_cause,v.root_cause) is null or coalesce(p_corrective_action,v.corrective_action) is null or coalesce(p_risk_ref,v.risk_ref) is null) then
   raise exception 'INCIDENT_CLOSURE_EVIDENCE_REQUIRED';
 end if;
 update ops.incidents set status=p_new_status,
   acknowledged_at=case when p_new_status='ACKNOWLEDGED' then coalesce(acknowledged_at,now()) else acknowledged_at end,
   contained_at=case when p_new_status='CONTAINED' then coalesce(contained_at,now()) else contained_at end,
   resolved_at=case when p_new_status='RESOLVED' then coalesce(resolved_at,now()) else resolved_at end,
   closed_at=case when p_new_status='CLOSED' then now() else closed_at end,
   evidence_ref=coalesce(p_evidence_ref,evidence_ref),root_cause=coalesce(p_root_cause,root_cause),corrective_action=coalesce(p_corrective_action,corrective_action),risk_ref=coalesce(p_risk_ref,risk_ref),updated_at=now()
 where incident_pk=p_incident_pk returning * into v;
 insert into ops.incident_timeline(incident_pk,action_type,actor_ref,summary,evidence_ref) values(v.incident_pk,p_new_status,p_actor_ref,p_summary,p_evidence_ref);
 if p_new_status='ACKNOWLEDGED' then update ops.alert_instances set status='ACKNOWLEDGED',acknowledged_at=coalesce(acknowledged_at,now()),acknowledged_by=p_actor_ref,updated_at=now() where alert_pk=v.alert_pk and status='OPEN'; end if;
 if p_new_status='CLOSED' then update ops.alert_instances set status='RESOLVED',resolved_at=now(),resolved_by=p_actor_ref,updated_at=now() where alert_pk=v.alert_pk and status<>'RESOLVED'; update ops.alert_delivery_queue set delivery_status='CANCELLED',hold_reason='INCIDENT_CLOSED',updated_at=now() where alert_pk=v.alert_pk and delivery_status in ('HELD','READY','FAILED'); end if;
 return v;
end $$;

create or replace function ops.refresh_observability_signals(p_environment text default 'TEST')
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record; v_alerts int:=0; v_security int:=0; v_result jsonb;
begin
 if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
 for r in select * from ops.alert_candidates_v loop
   v_result:=ops.ingest_alert_signal(p_environment,r.alert_key,r.alert_key,coalesce(r.severity,'SEV2'),r.reason,r.affected_count,r.alert_key,jsonb_build_object('source','ops.alert_candidates_v','first_seen_at',r.first_seen_at),now());
   v_alerts:=v_alerts+1;
 end loop;
 for r in select security_event_pk,event_type,severity,summary,evidence_ref,entity_type,entity_id,occurred_at from ops.security_events where environment=p_environment and status='OPEN' and severity in ('SEV0','SEV1') loop
   v_result:=ops.ingest_alert_signal(p_environment,r.event_type,'SECURITY_EVENT|'||r.event_type||'|'||coalesce(r.entity_type,'')||'|'||coalesce(r.entity_id,''),r.severity,r.summary,1,coalesce(r.evidence_ref,r.security_event_pk::text),jsonb_build_object('source','ops.security_events'),r.occurred_at);
   v_security:=v_security+1;
 end loop;
 return jsonb_build_object('alert_candidates_scanned',v_alerts,'security_events_scanned',v_security);
end $$;

revoke all on function ops.severity_rank(text) from public,anon,authenticated;
revoke all on function ops.ingest_alert_signal(text,text,text,text,text,bigint,text,jsonb,timestamptz) from public,anon,authenticated;
revoke all on function ops.transition_incident(uuid,text,text,text,text,text,text,text) from public,anon,authenticated;
revoke all on function ops.refresh_observability_signals(text) from public,anon,authenticated;
grant execute on function ops.severity_rank(text) to service_role;
grant execute on function ops.ingest_alert_signal(text,text,text,text,text,bigint,text,jsonb,timestamptz) to service_role;
grant execute on function ops.transition_incident(uuid,text,text,text,text,text,text,text) to service_role;
grant execute on function ops.refresh_observability_signals(text) to service_role;