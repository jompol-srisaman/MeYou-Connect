create table if not exists ops.credential_rotation_events (
  rotation_pk uuid primary key default gen_random_uuid(),
  credential_ref text not null,
  system_name text not null,
  environment text not null check(environment in ('TEST','PROD')),
  event_type text not null check(event_type in ('EXPOSURE_DECLARED','ROTATED','REVOKED','VERIFIED')),
  occurred_at timestamptz not null default now(),
  evidence_ref text,
  performed_by text not null,
  reason text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  constraint credential_rotation_no_secret_keys check (not (metadata ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists credential_rotation_ref_time_idx on ops.credential_rotation_events(credential_ref,occurred_at desc);

alter table ops.credential_rotation_events enable row level security;
revoke all on ops.credential_rotation_events from public,anon,authenticated;
grant select,insert,update,delete on ops.credential_rotation_events to service_role;

create or replace function ops.register_credential_binding(
 p_credential_ref text,p_system_name text,p_environment text,p_secret_inventory_ref text,p_purpose text,
 p_secret_store_type text,p_store_reference text,p_scope_summary text,p_status text,p_evidence_ref text default null,p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_pk uuid; v_env_ok boolean;
begin
 if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
 if p_status not in ('NOT_CREATED','REGISTERED','VERIFIED','REVOKED') then raise exception 'INVALID_BINDING_STATUS'; end if;
 if p_secret_store_type not in ('ENVIRONMENT_SECRET_STORE','SUPABASE_SECRET_STORE','CI_CD_SECRET_STORE','N8N_CREDENTIALS','PROVIDER_SECRET_STORE','NOT_CREATED') then raise exception 'INVALID_SECRET_STORE_TYPE'; end if;
 if coalesce(p_metadata,'{}'::jsonb) ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key'] then raise exception 'SECRET_MATERIAL_NOT_ALLOWED'; end if;
 if p_status='VERIFIED' then
   select (verified and lifecycle_status='ACTIVE') into v_env_ok from ops.security_environments where environment=p_environment;
   if coalesce(v_env_ok,false)=false then raise exception 'ENVIRONMENT_NOT_VERIFIED'; end if;
 end if;
 insert into ops.credential_bindings(credential_ref,system_name,environment,secret_inventory_ref,purpose,secret_store_type,store_reference,scope_summary,status,last_reviewed_at,evidence_ref,metadata)
 values(p_credential_ref,p_system_name,p_environment,p_secret_inventory_ref,p_purpose,p_secret_store_type,p_store_reference,p_scope_summary,p_status,case when p_status='VERIFIED' then now() end,p_evidence_ref,coalesce(p_metadata,'{}'::jsonb))
 returning binding_pk into v_pk;
 return v_pk;
end $$;

create or replace function ops.record_credential_rotation(
 p_credential_ref text,p_system_name text,p_environment text,p_event_type text,p_performed_by text,p_reason text,p_evidence_ref text default null,p_metadata jsonb default '{}'::jsonb
) returns uuid
language plpgsql security definer set search_path=''
as $$
declare v_pk uuid;
begin
 if p_environment not in ('TEST','PROD') then raise exception 'INVALID_ENVIRONMENT'; end if;
 if p_event_type not in ('EXPOSURE_DECLARED','ROTATED','REVOKED','VERIFIED') then raise exception 'INVALID_ROTATION_EVENT'; end if;
 if p_credential_ref is null or btrim(p_credential_ref)='' then raise exception 'CREDENTIAL_REF_REQUIRED'; end if;
 if p_performed_by is null or btrim(p_performed_by)='' then raise exception 'PERFORMED_BY_REQUIRED'; end if;
 if p_reason is null or btrim(p_reason)='' then raise exception 'REASON_REQUIRED'; end if;
 if coalesce(p_metadata,'{}'::jsonb) ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key'] then raise exception 'SECRET_MATERIAL_NOT_ALLOWED'; end if;
 insert into ops.credential_rotation_events(credential_ref,system_name,environment,event_type,evidence_ref,performed_by,reason,metadata)
 values(p_credential_ref,p_system_name,p_environment,p_event_type,p_evidence_ref,p_performed_by,p_reason,coalesce(p_metadata,'{}'::jsonb))
 returning rotation_pk into v_pk;
 return v_pk;
end $$;

create or replace view ops.rotation_readiness_v as
select b.credential_ref,b.system_name,b.environment,b.status,b.last_reviewed_at,
 max(r.occurred_at) filter(where r.event_type in ('ROTATED','REVOKED','VERIFIED')) as last_control_event_at,
 max(r.occurred_at) filter(where r.event_type='EXPOSURE_DECLARED') as last_exposure_at,
 case when max(r.occurred_at) filter(where r.event_type='EXPOSURE_DECLARED') is null then 'NO_EXPOSURE_RECORDED'
      when max(r.occurred_at) filter(where r.event_type in ('ROTATED','REVOKED')) > max(r.occurred_at) filter(where r.event_type='EXPOSURE_DECLARED') then 'REMEDIATED'
      else 'ROTATION_REQUIRED' end as rotation_status
from ops.credential_bindings b left join ops.credential_rotation_events r on r.credential_ref=b.credential_ref
group by b.credential_ref,b.system_name,b.environment,b.status,b.last_reviewed_at;

revoke all on function ops.record_credential_rotation(text,text,text,text,text,text,text,jsonb) from public,anon,authenticated;
grant execute on function ops.record_credential_rotation(text,text,text,text,text,text,text,jsonb) to service_role;
revoke all on ops.rotation_readiness_v from public,anon,authenticated;
grant select on ops.rotation_readiness_v to service_role;