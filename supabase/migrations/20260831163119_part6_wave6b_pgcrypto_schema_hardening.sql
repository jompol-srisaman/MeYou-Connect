create or replace function analytics.record_appointment_outcome(
  p_placement_id text,p_appointment_at timestamptz,p_outcome text,p_observed_at timestamptz,
  p_evidence_id text default null,p_raw_input_id text default null,p_source_followup_id text default null,
  p_source_kind text default 'EVENT',p_verified boolean default false,p_actor_service text default 'SYSTEM',p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_key text;v_pk uuid;
begin
  v_key:=pg_catalog.encode(extensions.digest(pg_catalog.concat_ws('|','appointment',p_placement_id,p_appointment_at::text,upper(coalesce(p_outcome,'')),coalesce(p_evidence_id,''),coalesce(p_raw_input_id,''),coalesce(p_source_followup_id,''),p_observed_at::text),'sha256'),'hex');
  select appointment_fact_pk into v_pk from analytics.appointment_outcome_fact where fact_key=v_key;
  if v_pk is not null then return v_pk; end if;
  insert into analytics.appointment_outcome_fact(fact_key,placement_id,appointment_at,outcome,observed_at,evidence_id,raw_input_id,source_followup_id,source_kind,verified,actor_service,metadata)
  values(v_key,p_placement_id,p_appointment_at,upper(p_outcome),p_observed_at,p_evidence_id,p_raw_input_id,p_source_followup_id,p_source_kind,p_verified,p_actor_service,coalesce(p_metadata,'{}'::jsonb)) returning appointment_fact_pk into v_pk;
  return v_pk;
end
$function$;

create or replace function analytics.record_partner_attribution(
  p_candidate_id text,p_partner_id text,p_attributed_at timestamptz,p_status text,p_evidence_id text default null,p_raw_input_id text default null,
  p_source_kind text default 'EVENT',p_approved_by text default null,p_approved_at timestamptz default null,p_actor_service text default 'SYSTEM',p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $function$
declare v_key text;v_pk uuid;
begin
  v_key:=pg_catalog.encode(extensions.digest(pg_catalog.concat_ws('|','partner_attribution',p_candidate_id,p_partner_id,p_attributed_at::text,upper(coalesce(p_status,'')),coalesce(p_evidence_id,''),coalesce(p_raw_input_id,'')),'sha256'),'hex');
  select attribution_fact_pk into v_pk from analytics.partner_attribution_fact where fact_key=v_key;
  if v_pk is not null then return v_pk; end if;
  insert into analytics.partner_attribution_fact(fact_key,candidate_id,partner_id,attributed_at,attribution_status,evidence_id,raw_input_id,source_kind,approved_by,approved_at,actor_service,metadata)
  values(v_key,p_candidate_id,p_partner_id,p_attributed_at,upper(p_status),p_evidence_id,p_raw_input_id,p_source_kind,p_approved_by,p_approved_at,p_actor_service,coalesce(p_metadata,'{}'::jsonb)) returning attribution_fact_pk into v_pk;
  return v_pk;
end
$function$;

revoke all on function analytics.record_appointment_outcome(text,timestamptz,text,timestamptz,text,text,text,text,boolean,text,jsonb) from public,anon,authenticated;
revoke all on function analytics.record_partner_attribution(text,text,timestamptz,text,text,text,text,text,timestamptz,text,jsonb) from public,anon,authenticated;
grant execute on function analytics.record_appointment_outcome(text,timestamptz,text,timestamptz,text,text,text,text,boolean,text,jsonb) to service_role;
grant execute on function analytics.record_partner_attribution(text,text,timestamptz,text,text,text,text,text,timestamptz,text,jsonb) to service_role;