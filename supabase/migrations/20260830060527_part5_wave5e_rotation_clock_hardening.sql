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
 insert into ops.credential_rotation_events(credential_ref,system_name,environment,event_type,occurred_at,evidence_ref,performed_by,reason,metadata)
 values(p_credential_ref,p_system_name,p_environment,p_event_type,clock_timestamp(),p_evidence_ref,p_performed_by,p_reason,coalesce(p_metadata,'{}'::jsonb))
 returning rotation_pk into v_pk;
 return v_pk;
end $$;