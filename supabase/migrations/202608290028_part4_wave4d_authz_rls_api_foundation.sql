begin;

create table if not exists authz.role_catalog (
  role_key text primary key,
  display_name text not null,
  description text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into authz.role_catalog(role_key,display_name,description) values
 ('founder','Founder','Founder / final business authority'),
 ('secretary','Secretary','Senior Executive Secretary / orchestrator'),
 ('candidate_ops','Candidate Operations','Candidate screening, readiness, placement follow-up'),
 ('client_sales','Client & Sales','B2B client, job demand and sales pipeline'),
 ('finance_control','Finance Control','Finance, collection, commission and accounting control'),
 ('content_studio','Content Studio','Approved public-safe content and job communication'),
 ('data_audit','Data & Automation Audit','Data quality, audit, automation oversight'),
 ('automation_worker','Automation Worker','Server/function-scoped automation identity')
on conflict(role_key) do update set display_name=excluded.display_name,description=excluded.description,active=true,updated_at=now();

create table if not exists authz.user_profiles (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  status text not null default 'ACTIVE' check(status in ('ACTIVE','SUSPENDED','DISABLED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists authz.user_roles (
  auth_user_id uuid not null references auth.users(id) on delete cascade,
  role_key text not null references authz.role_catalog(role_key) on delete restrict,
  active boolean not null default true,
  assigned_by text not null,
  assigned_at timestamptz not null default now(),
  expires_at timestamptz,
  reason text,
  primary key(auth_user_id,role_key)
);
create index if not exists user_roles_active_idx on authz.user_roles(auth_user_id,active,expires_at);

create table if not exists authz.role_capabilities (
  role_key text not null references authz.role_catalog(role_key) on delete cascade,
  capability_key text not null,
  primary key(role_key,capability_key)
);

create table if not exists authz.role_assignment_audit (
  audit_id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null references auth.users(id) on delete restrict,
  role_key text not null references authz.role_catalog(role_key) on delete restrict,
  action text not null check(action in ('GRANT','REVOKE')),
  actor text not null,
  reason text,
  created_at timestamptz not null default now()
);
create index if not exists role_assignment_audit_user_idx on authz.role_assignment_audit(auth_user_id,created_at desc);

insert into authz.role_capabilities(role_key,capability_key) values
 ('founder','job_catalog_read'),('founder','candidate_summary_read'),('founder','candidate_contact_read'),('founder','client_record_read'),('founder','client_contact_read'),('founder','placement_status_read'),('founder','consent_status_read'),('founder','docs_read'),('founder','ops_read'),('founder','finance_read'),('founder','protected_action_approve'),
 ('secretary','job_catalog_read'),('secretary','candidate_summary_read'),('secretary','candidate_contact_read'),('secretary','client_record_read'),('secretary','client_contact_read'),('secretary','placement_status_read'),('secretary','consent_status_read'),('secretary','docs_read'),('secretary','ops_read'),('secretary','finance_read'),
 ('candidate_ops','job_catalog_read'),('candidate_ops','candidate_summary_read'),('candidate_ops','candidate_contact_read'),('candidate_ops','placement_status_read'),('candidate_ops','consent_status_read'),('candidate_ops','docs_read'),('candidate_ops','ops_read'),
 ('client_sales','job_catalog_read'),('client_sales','candidate_summary_read'),('client_sales','client_record_read'),('client_sales','client_contact_read'),('client_sales','placement_status_read'),('client_sales','docs_read'),('client_sales','ops_read'),
 ('finance_control','job_catalog_read'),('finance_control','candidate_summary_read'),('finance_control','client_record_read'),('finance_control','placement_status_read'),('finance_control','docs_read'),('finance_control','ops_read'),('finance_control','finance_read'),
 ('content_studio','job_catalog_read'),
 ('data_audit','job_catalog_read'),('data_audit','candidate_summary_read'),('data_audit','candidate_contact_read'),('data_audit','client_record_read'),('data_audit','client_contact_read'),('data_audit','placement_status_read'),('data_audit','consent_status_read'),('data_audit','docs_read'),('data_audit','ops_read'),('data_audit','finance_read')
on conflict do nothing;

create or replace function authz.ensure_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  insert into authz.user_profiles(auth_user_id,display_name)
  values(new.id,nullif(coalesce(new.raw_user_meta_data->>'display_name',new.raw_user_meta_data->>'full_name'),'') )
  on conflict(auth_user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists authz_user_profile_after_auth_insert on auth.users;
create trigger authz_user_profile_after_auth_insert
after insert on auth.users
for each row execute function authz.ensure_profile_for_new_user();

create or replace function authz.current_roles()
returns text[]
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(array_agg(ur.role_key order by ur.role_key),'{}'::text[])
  from authz.user_roles ur
  join authz.user_profiles up on up.auth_user_id=ur.auth_user_id
  where ur.auth_user_id=auth.uid()
    and ur.active
    and up.status='ACTIVE'
    and (ur.expires_at is null or ur.expires_at>now());
$$;

create or replace function authz.has_role(p_role_key text)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(exists(
    select 1 from authz.user_roles ur
    join authz.user_profiles up on up.auth_user_id=ur.auth_user_id
    where ur.auth_user_id=auth.uid() and ur.role_key=p_role_key and ur.active
      and up.status='ACTIVE' and (ur.expires_at is null or ur.expires_at>now())
  ),false);
$$;

create or replace function authz.has_any_role(p_roles text[])
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(exists(
    select 1 from authz.user_roles ur
    join authz.user_profiles up on up.auth_user_id=ur.auth_user_id
    where ur.auth_user_id=auth.uid() and ur.role_key=any(p_roles) and ur.active
      and up.status='ACTIVE' and (ur.expires_at is null or ur.expires_at>now())
  ),false);
$$;

create or replace function authz.current_capabilities()
returns text[]
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(array_agg(distinct rc.capability_key order by rc.capability_key),'{}'::text[])
  from authz.user_roles ur
  join authz.user_profiles up on up.auth_user_id=ur.auth_user_id
  join authz.role_capabilities rc on rc.role_key=ur.role_key
  where ur.auth_user_id=auth.uid() and ur.active and up.status='ACTIVE'
    and (ur.expires_at is null or ur.expires_at>now());
$$;

create or replace function authz.has_capability(p_capability_key text)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select coalesce(exists(
    select 1 from authz.user_roles ur
    join authz.user_profiles up on up.auth_user_id=ur.auth_user_id
    join authz.role_capabilities rc on rc.role_key=ur.role_key
    where ur.auth_user_id=auth.uid() and ur.active and up.status='ACTIVE'
      and (ur.expires_at is null or ur.expires_at>now())
      and rc.capability_key=p_capability_key
  ),false);
$$;

create or replace function authz.require_capability(p_capability_key text)
returns void
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  if not authz.has_capability(p_capability_key) then raise exception 'ACCESS_DENIED:%',p_capability_key; end if;
end;
$$;

create or replace function authz.assign_role(p_auth_user_id uuid,p_role_key text,p_actor text,p_reason text default null,p_expires_at timestamptz default null)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_actor is null or btrim(p_actor)='' then raise exception 'actor required'; end if;
  if not exists(select 1 from auth.users where id=p_auth_user_id) then raise exception 'unknown auth user'; end if;
  if not exists(select 1 from authz.role_catalog where role_key=p_role_key and active) then raise exception 'unknown/inactive role'; end if;
  insert into authz.user_profiles(auth_user_id) values(p_auth_user_id) on conflict do nothing;
  insert into authz.user_roles(auth_user_id,role_key,active,assigned_by,assigned_at,expires_at,reason)
  values(p_auth_user_id,p_role_key,true,p_actor,now(),p_expires_at,p_reason)
  on conflict(auth_user_id,role_key) do update set active=true,assigned_by=excluded.assigned_by,assigned_at=now(),expires_at=excluded.expires_at,reason=excluded.reason;
  insert into authz.role_assignment_audit(auth_user_id,role_key,action,actor,reason) values(p_auth_user_id,p_role_key,'GRANT',p_actor,p_reason);
end; $$;

create or replace function authz.revoke_role(p_auth_user_id uuid,p_role_key text,p_actor text,p_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
begin
  if p_actor is null or btrim(p_actor)='' then raise exception 'actor required'; end if;
  update authz.user_roles set active=false,reason=coalesce(p_reason,reason) where auth_user_id=p_auth_user_id and role_key=p_role_key;
  if not found then raise exception 'role assignment not found'; end if;
  insert into authz.role_assignment_audit(auth_user_id,role_key,action,actor,reason) values(p_auth_user_id,p_role_key,'REVOKE',p_actor,p_reason);
end; $$;

alter table authz.role_catalog enable row level security;
alter table authz.user_profiles enable row level security;
alter table authz.user_roles enable row level security;
alter table authz.role_capabilities enable row level security;
alter table authz.role_assignment_audit enable row level security;

drop policy if exists role_catalog_authenticated_read on authz.role_catalog;
create policy role_catalog_authenticated_read on authz.role_catalog for select to authenticated using (active=true);
drop policy if exists user_profiles_self_read on authz.user_profiles;
create policy user_profiles_self_read on authz.user_profiles for select to authenticated using (auth_user_id=auth.uid());
drop policy if exists user_roles_self_read on authz.user_roles;
create policy user_roles_self_read on authz.user_roles for select to authenticated using (auth_user_id=auth.uid());
drop policy if exists role_capabilities_direct_deny on authz.role_capabilities;
create policy role_capabilities_direct_deny on authz.role_capabilities as restrictive for all to anon,authenticated using(false) with check(false);
drop policy if exists role_assignment_audit_direct_deny on authz.role_assignment_audit;
create policy role_assignment_audit_direct_deny on authz.role_assignment_audit as restrictive for all to anon,authenticated using(false) with check(false);

alter table core.candidates enable row level security;
alter table core.clients enable row level security;
alter table core.partners enable row level security;
alter table core.jobs enable row level security;
alter table core.placements enable row level security;
alter table core.followups enable row level security;
alter table core.dorms enable row level security;
alter table core.transport_providers enable row level security;

do $$ declare t text; begin
  foreach t in array array['candidates','clients','partners','jobs','placements','followups','dorms','transport_providers'] loop
    execute format('drop policy if exists %I on core.%I','part4d_direct_deny_'||t,t);
    execute format('create policy %I on core.%I as restrictive for all to anon,authenticated using(false) with check(false)','part4d_direct_deny_'||t,t);
  end loop;
end $$;

revoke all on all tables in schema core from anon,authenticated;
revoke all on all tables in schema private from anon,authenticated;
revoke all on all tables in schema privacy from anon,authenticated;
revoke all on all tables in schema docs from anon,authenticated;

create or replace function api.current_access_context()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_uid uuid:=auth.uid(); begin
  if v_uid is null then raise exception 'AUTH_REQUIRED'; end if;
  return jsonb_build_object('auth_user_id',v_uid,'roles',to_jsonb(authz.current_roles()),'capabilities',to_jsonb(authz.current_capabilities()),'production_cutover_approved',coalesce((select setting_value from config.system_settings where setting_key='production_cutover_approved'),'false'::jsonb),'business_master_apply_enabled',coalesce((select setting_value from config.system_settings where setting_key='business_master_apply_enabled'),'false'::jsonb));
end; $$;

create or replace function api.list_job_catalog(p_status text default null)
returns table(job_id text,workplace_name text,province text,area text,position_name text,headcount integer,wage numeric,shift text,start_date date,status text,last_confirmed_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
  perform authz.require_capability('job_catalog_read');
  return query select j.job_id,j.workplace_name,j.province,j.area,j.position_name,j.headcount,j.wage,j.shift,j.start_date,j.status,j.last_confirmed_at
  from core.jobs j where (p_status is null or j.status=p_status)
  and (not authz.has_role('content_studio') or authz.has_any_role(array['founder','secretary','candidate_ops','client_sales','finance_control','data_audit']) or j.status in ('OPEN','ACTIVE','PUBLISHED'))
  order by j.updated_at desc,j.job_id;
end; $$;

create or replace function api.get_candidate_summary(p_candidate_id text)
returns table(candidate_id text,nickname text,origin_province text,education text,primary_experience text,preferred_job text,expected_income numeric,shift_preference text,relocation_ready boolean,ready_date date,has_vehicle boolean,dorm_needed boolean,dorm_budget numeric,documents_ready boolean,medical_ready boolean,status text,next_action text)
language plpgsql stable security definer set search_path='' as $$
declare v_full boolean; v_sales boolean; v_fin boolean;
begin
  perform authz.require_capability('candidate_summary_read');
  v_full:=authz.has_any_role(array['founder','secretary','candidate_ops','data_audit']);
  v_sales:=authz.has_role('client_sales');
  v_fin:=authz.has_role('finance_control');
  return query select c.candidate_id,c.nickname,
    case when v_full or v_sales then c.origin_province else null end,
    case when v_full then c.education else null end,
    case when v_full then c.primary_experience else null end,
    case when v_full or v_sales then c.preferred_job else null end,
    case when v_full or v_sales then c.expected_income else null end,
    case when v_full or v_sales then c.shift_preference else null end,
    case when v_full or v_sales then c.relocation_ready else null end,
    case when v_full or v_sales then c.ready_date else null end,
    case when v_full then c.has_vehicle else null end,
    case when v_full then c.dorm_needed else null end,
    case when v_full then c.dorm_budget else null end,
    case when v_full or v_sales then c.documents_ready else null end,
    case when v_full or v_sales then c.medical_ready else null end,
    c.status,case when v_full then c.next_action else null end
  from core.candidates c where c.candidate_id=p_candidate_id;
end; $$;

create or replace function api.get_candidate_contact(p_candidate_id text)
returns table(candidate_id text,full_name text,phone text,line_id text,email text,current_address text)
language plpgsql stable security definer set search_path='' as $$
begin
  perform authz.require_capability('candidate_contact_read');
  return query select cc.candidate_id,cc.full_name,cc.phone,cc.line_id,cc.email,cc.current_address from private.candidate_contacts cc where cc.candidate_id=p_candidate_id;
end; $$;

create or replace function api.get_client_record(p_client_id text)
returns table(client_id text,client_type text,company_name text,province text,area text,crm_status text,payment_term text,billing_cycle text,verification_status text,contact_name text,contact_role text,phone text,line_id text,email text)
language plpgsql stable security definer set search_path='' as $$
declare v_contact boolean;
begin
  perform authz.require_capability('client_record_read');
  v_contact:=authz.has_capability('client_contact_read');
  return query select c.client_id,c.client_type,c.company_name,c.province,c.area,c.crm_status,c.payment_term,c.billing_cycle,c.verification_status,
    case when v_contact then cc.contact_name else null end,case when v_contact then cc.contact_role else null end,case when v_contact then cc.phone else null end,case when v_contact then cc.line_id else null end,case when v_contact then cc.email else null end
  from core.clients c left join private.client_contacts cc on cc.client_id=c.client_id where c.client_id=p_client_id;
end; $$;

create or replace function api.list_placement_status(p_candidate_id text default null,p_job_id text default null)
returns table(placement_id text,candidate_id text,job_id text,status text,start_date date,last_followup_at timestamptz,last_milestone text,last_result text,next_followup_at timestamptz)
language plpgsql stable security definer set search_path='' as $$
begin
  perform authz.require_capability('placement_status_read');
  return query select p.placement_id,p.candidate_id,p.job_id,p.status,p.start_date,f.followed_up_at,f.milestone,f.result,f.next_followup_at
  from core.placements p left join lateral (select x.followed_up_at,x.milestone,x.result,x.next_followup_at from core.followups x where x.placement_id=p.placement_id order by x.followed_up_at desc nulls last,x.created_at desc limit 1) f on true
  where (p_candidate_id is null or p.candidate_id=p_candidate_id) and (p_job_id is null or p.job_id=p_job_id)
  order by p.updated_at desc,p.placement_id;
end; $$;

create or replace function api.get_consent_status(p_candidate_id text)
returns table(consent_id text,candidate_id text,purpose_code text,decision text,effective_at timestamptz,evidence_id text)
language plpgsql stable security definer set search_path='' as $$
begin
  perform authz.require_capability('consent_status_read');
  return query select c.consent_id,c.candidate_id,c.purpose_code,c.decision,c.effective_at,c.evidence_id from privacy.current_consents_v c where c.candidate_id=p_candidate_id order by c.purpose_code;
end; $$;

create or replace view api.my_access_v with (security_invoker=true) as select api.current_access_context() as access_context;
create or replace view api.job_catalog_v with (security_invoker=true) as select * from api.list_job_catalog(null);

revoke all on schema authz from public,anon;
grant usage on schema authz to authenticated,service_role;
revoke all on authz.role_catalog,authz.user_profiles,authz.user_roles,authz.role_capabilities,authz.role_assignment_audit from anon,authenticated;
grant select on authz.role_catalog,authz.user_profiles,authz.user_roles to authenticated;
revoke execute on function authz.assign_role(uuid,text,text,text,timestamptz) from public,anon,authenticated;
revoke execute on function authz.revoke_role(uuid,text,text,text) from public,anon,authenticated;
grant execute on function authz.assign_role(uuid,text,text,text,timestamptz) to service_role;
grant execute on function authz.revoke_role(uuid,text,text,text) to service_role;

revoke all on schema api from public,anon;
grant usage on schema api to authenticated,service_role;
revoke all on function api.current_access_context() from public,anon;
revoke all on function api.list_job_catalog(text) from public,anon;
revoke all on function api.get_candidate_summary(text) from public,anon;
revoke all on function api.get_candidate_contact(text) from public,anon;
revoke all on function api.get_client_record(text) from public,anon;
revoke all on function api.list_placement_status(text,text) from public,anon;
revoke all on function api.get_consent_status(text) from public,anon;
grant execute on function api.current_access_context() to authenticated,service_role;
grant execute on function api.list_job_catalog(text) to authenticated,service_role;
grant execute on function api.get_candidate_summary(text) to authenticated,service_role;
grant execute on function api.get_candidate_contact(text) to authenticated,service_role;
grant execute on function api.get_client_record(text) to authenticated,service_role;
grant execute on function api.list_placement_status(text,text) to authenticated,service_role;
grant execute on function api.get_consent_status(text) to authenticated,service_role;
revoke all on api.my_access_v,api.job_catalog_v from public,anon;
grant select on api.my_access_v,api.job_catalog_v to authenticated,service_role;

commit;