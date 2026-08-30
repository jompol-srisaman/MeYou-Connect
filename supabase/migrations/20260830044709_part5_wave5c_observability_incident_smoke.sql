begin;

insert into ops.alert_routes(environment,owner_role,channel_type,destination_ref,verified,verified_at,verified_by,active)
values
 ('TEST','automation_worker','DB_ONLY','test://automation',true,now(),'part5c-smoke',true),
 ('TEST','founder','DB_ONLY','test://founder',true,now(),'part5c-smoke',true)
on conflict (environment,owner_role,channel_type) do update set destination_ref=excluded.destination_ref,verified=true,verified_at=now(),verified_by='part5c-smoke',active=true;

select ops.ingest_alert_signal('TEST','WEBHOOK_SIGNATURE_FAILURE_SPIKE','TST5C|WEBHOOK|SOURCE-A','SEV2','Synthetic webhook anomaly',2,'TST5C-SRC-1','{"test":true}'::jsonb,now());
select ops.ingest_alert_signal('TEST','WEBHOOK_SIGNATURE_FAILURE_SPIKE','TST5C|WEBHOOK|SOURCE-A','SEV1','Synthetic webhook anomaly escalated',5,'TST5C-SRC-2','{"test":true}'::jsonb,now());
select ops.ingest_alert_signal('TEST','WEBHOOK_SIGNATURE_FAILURE_SPIKE','TST5C|WEBHOOK|SOURCE-A','SEV1','Synthetic webhook anomaly repeated',7,'TST5C-SRC-3','{"test":true}'::jsonb,now());
select ops.ingest_alert_signal('TEST','PRIVATE_EVIDENCE_PUBLIC','TST5C|PRIVATE-FILE|1','SEV0','Synthetic private evidence exposure',1,'TST5C-EVIDENCE','{"test":true}'::jsonb,now());

do $$
declare v_alert uuid; v_inc uuid; v_count int; v_occ bigint; v_sev text; v_due timestamptz; v_status text; begin
 select alert_pk,occurrence_count,severity into v_alert,v_occ,v_sev from ops.alert_instances where fingerprint='TST5C|WEBHOOK|SOURCE-A';
 if v_occ<>3 or v_sev<>'SEV1' then raise exception 'alert aggregation/escalation failed: occ %, sev %',v_occ,v_sev; end if;
 select count(*) into v_count from ops.incidents where alert_pk=v_alert;
 if v_count<>1 then raise exception 'duplicate incident created: %',v_count; end if;
 select incident_pk,ack_due_at into v_inc,v_due from ops.incidents where alert_pk=v_alert order by declared_at limit 1;
 if v_due < now()+interval '29 minutes' or v_due > now()+interval '31 minutes' then raise exception 'SEV1 ack due incorrect: %',v_due; end if;
 select count(*) into v_count from ops.alert_delivery_queue where alert_pk=v_alert and delivery_status='HELD';
 if v_count<>1 then raise exception 'external delivery should be HELD'; end if;
 perform ops.transition_incident(v_inc,'ACKNOWLEDGED','part5c-smoke','Acknowledged synthetic incident');
 perform ops.transition_incident(v_inc,'CONTAINED','part5c-smoke','Contained synthetic incident');
 perform ops.transition_incident(v_inc,'RESOLVED','part5c-smoke','Resolved synthetic incident');
 begin
   perform ops.transition_incident(v_inc,'CLOSED','part5c-smoke','Attempt close without evidence');
   raise exception 'incident closed without closure evidence';
 exception when others then
   if position('INCIDENT_CLOSURE_EVIDENCE_REQUIRED' in sqlerrm)=0 then raise; end if;
 end;
 perform ops.transition_incident(v_inc,'CLOSED','part5c-smoke','Closed after evidence','TST5C-CLOSE-EVIDENCE','Synthetic root cause','Synthetic corrective action','MYC-RSK-999');
 select status into v_status from ops.incidents where incident_pk=v_inc;
 if v_status<>'CLOSED' then raise exception 'incident close failed'; end if;
 if (select status from ops.alert_instances where alert_pk=v_alert)<>'RESOLVED' then raise exception 'alert not resolved with incident close'; end if;
end $$;

do $$ declare v_due timestamptz; v_count int; begin
 select i.ack_due_at into v_due from ops.incidents i join ops.alert_instances a on a.alert_pk=i.alert_pk where a.fingerprint='TST5C|PRIVATE-FILE|1';
 if v_due < now()+interval '14 minutes' or v_due > now()+interval '16 minutes' then raise exception 'SEV0 ack due incorrect: %',v_due; end if;
 select count(*) into v_count from ops.incidents i join ops.alert_instances a on a.alert_pk=i.alert_pk where a.fingerprint='TST5C|PRIVATE-FILE|1';
 if v_count<>1 then raise exception 'SEV0 incident creation failed'; end if;
end $$;

insert into auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous) values
 ('50000000-0000-0000-0000-000000000001','authenticated','authenticated','tst5c-founder@example.invalid',now(),now(),false,false),
 ('50000000-0000-0000-0000-000000000002','authenticated','authenticated','tst5c-content@example.invalid',now(),now(),false,false);
select authz.assign_role('50000000-0000-0000-0000-000000000001','founder','part5c-smoke','synthetic founder',null);
select authz.assign_role('50000000-0000-0000-0000-000000000002','content_studio','part5c-smoke','synthetic content',null);

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000001',true);
set local role authenticated;
do $$ declare v_count int; v jsonb; begin
 select count(*) into v_count from api.observability_alerts(null); if v_count<2 then raise exception 'founder alert API missing rows'; end if;
 select count(*) into v_count from api.observability_incidents(null); if v_count<2 then raise exception 'founder incident API missing rows'; end if;
 v:=api.observability_foundation_status(); if coalesce((v->>'part5c_foundation_ready')::boolean,false) is not true then raise exception 'foundation status false'; end if;
 begin perform 1 from ops.alert_instances limit 1; raise exception 'direct alert table unexpectedly allowed'; exception when insufficient_privilege then null; end;
end $$;

select set_config('request.jwt.claim.sub','50000000-0000-0000-0000-000000000002',true);
do $$ begin
 begin perform * from api.observability_alerts(null); raise exception 'content observability unexpectedly allowed'; exception when others then if position('ACCESS_DENIED' in sqlerrm)=0 then raise; end if; end;
end $$;

set local role anon;
select set_config('request.jwt.claim.sub','',true);
do $$ begin
 begin perform api.observability_foundation_status(); raise exception 'anon observability unexpectedly allowed'; exception when insufficient_privilege then null; end;
end $$;
reset role;

rollback;