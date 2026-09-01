create schema if not exists geo;

create table if not exists geo.provinces (
  province_code text primary key,
  name_th text not null,
  name_en text,
  active boolean not null default true,
  source_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint provinces_code_nonblank_ck check (btrim(province_code)<>''),
  constraint provinces_name_th_nonblank_ck check (btrim(name_th)<>'')
);

create table if not exists geo.service_areas (
  service_area_id uuid primary key default gen_random_uuid(),
  area_type text not null check (area_type in ('PROVINCE','DISTRICT','INDUSTRIAL_ZONE','ROUTE','CUSTOM')),
  name text not null,
  province_code text references geo.provinces(province_code) on delete restrict,
  parent_service_area_id uuid references geo.service_areas(service_area_id) on delete restrict,
  active boolean not null default true,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_area_name_nonblank_ck check (btrim(name)<>''),
  constraint service_area_no_self_parent_ck check (parent_service_area_id is null or parent_service_area_id<>service_area_id),
  constraint service_area_no_secret_keys_ck check (not (config ?| array['password','secret','secret_value','service_role_key','api_key','access_token','refresh_token','private_key']))
);
create index if not exists service_areas_province_idx on geo.service_areas(province_code,active);
create index if not exists service_areas_parent_idx on geo.service_areas(parent_service_area_id);

create table if not exists authz.organizations (
  org_id uuid primary key default gen_random_uuid(),
  org_type text not null check (org_type in ('CLIENT','PARTNER')),
  business_party_id text not null,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','SUSPENDED','CLOSED')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(org_type,business_party_id),
  constraint organization_party_format_ck check (
    (org_type='CLIENT' and business_party_id ~ '^MYC-B2B-[0-9]{4}$') or
    (org_type='PARTNER' and business_party_id ~ '^MYC-P-[0-9]{4}$')
  )
);

create or replace function authz.validate_organization_business_party()
returns trigger language plpgsql security definer set search_path=''
as $function$
begin
  if new.org_type='CLIENT' and not exists(select 1 from core.clients c where c.client_id=new.business_party_id) then raise exception 'CLIENT_BUSINESS_PARTY_NOT_FOUND'; end if;
  if new.org_type='PARTNER' and not exists(select 1 from core.partners p where p.partner_id=new.business_party_id) then raise exception 'PARTNER_BUSINESS_PARTY_NOT_FOUND'; end if;
  return new;
end
$function$;

drop trigger if exists organizations_business_party_guard on authz.organizations;
create trigger organizations_business_party_guard before insert or update of org_type,business_party_id on authz.organizations for each row execute function authz.validate_organization_business_party();

create table if not exists authz.organization_members (
  org_id uuid not null references authz.organizations(org_id) on delete restrict,
  auth_user_id uuid not null references auth.users(id) on delete restrict,
  portal_role text not null check (portal_role in ('client_admin','client_recruiter','client_finance','partner_admin','partner_member')),
  membership_status text not null default 'INVITED' check (membership_status in ('INVITED','ACTIVE','SUSPENDED','EXPIRED','REMOVED')),
  invited_at timestamptz, active_from timestamptz, expires_at timestamptz, removed_at timestamptz,
  created_by text not null, updated_by text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  primary key(org_id,auth_user_id),
  constraint membership_time_order_ck check (expires_at is null or active_from is null or expires_at>active_from),
  constraint membership_removed_state_ck check ((membership_status='REMOVED' and removed_at is not null) or membership_status<>'REMOVED')
);
create index if not exists organization_members_active_user_idx on authz.organization_members(auth_user_id,membership_status,org_id);
create index if not exists organization_members_org_status_idx on authz.organization_members(org_id,membership_status);

create or replace function authz.validate_portal_role_for_org()
returns trigger language plpgsql security definer set search_path=''
as $function$
declare v_type text;
begin
  select o.org_type into v_type from authz.organizations o where o.org_id=new.org_id;
  if v_type is null then raise exception 'ORGANIZATION_NOT_FOUND'; end if;
  if v_type='CLIENT' and new.portal_role not in ('client_admin','client_recruiter','client_finance') then raise exception 'PORTAL_ROLE_ORG_TYPE_MISMATCH'; end if;
  if v_type='PARTNER' and new.portal_role not in ('partner_admin','partner_member') then raise exception 'PORTAL_ROLE_ORG_TYPE_MISMATCH'; end if;
  return new;
end
$function$;

drop trigger if exists organization_members_role_guard on authz.organization_members;
create trigger organization_members_role_guard before insert or update of org_id,portal_role on authz.organization_members for each row execute function authz.validate_portal_role_for_org();

create table if not exists authz.candidate_user_links (
  auth_user_id uuid primary key references auth.users(id) on delete restrict,
  candidate_id text not null references core.candidates(candidate_id) on delete restrict,
  verification_status text not null default 'PENDING' check (verification_status in ('PENDING','VERIFIED','REJECTED')),
  verified_by text, verified_at timestamptz,
  linked_at timestamptz not null default now(), disabled_at timestamptz, disable_reason text,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint candidate_link_verified_evidence_ck check ((verification_status='VERIFIED' and verified_by is not null and verified_at is not null) or verification_status<>'VERIFIED')
);
create unique index if not exists candidate_user_links_one_verified_candidate_idx on authz.candidate_user_links(candidate_id) where verification_status='VERIFIED' and disabled_at is null;
create index if not exists candidate_user_links_candidate_idx on authz.candidate_user_links(candidate_id,verification_status);

create table if not exists core.job_service_areas (job_id text not null references core.jobs(job_id) on delete restrict, service_area_id uuid not null references geo.service_areas(service_area_id) on delete restrict, status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE')), created_at timestamptz not null default now(), primary key(job_id,service_area_id));
create index if not exists job_service_areas_area_idx on core.job_service_areas(service_area_id,status);
create table if not exists core.partner_service_areas (partner_id text not null references core.partners(partner_id) on delete restrict, service_area_id uuid not null references geo.service_areas(service_area_id) on delete restrict, capability text, status text not null default 'ACTIVE' check (status in ('ACTIVE','LIMITED','INACTIVE')), created_at timestamptz not null default now(), primary key(partner_id,service_area_id));
create index if not exists partner_service_areas_area_idx on core.partner_service_areas(service_area_id,status);
create table if not exists core.dorm_service_areas (dorm_id text not null references core.dorms(dorm_id) on delete restrict, service_area_id uuid not null references geo.service_areas(service_area_id) on delete restrict, status text not null default 'ACTIVE' check (status in ('ACTIVE','LIMITED','INACTIVE')), created_at timestamptz not null default now(), primary key(dorm_id,service_area_id));
create index if not exists dorm_service_areas_area_idx on core.dorm_service_areas(service_area_id,status);
create table if not exists core.transport_service_areas (transport_id text not null references core.transport_providers(transport_id) on delete restrict, service_area_id uuid not null references geo.service_areas(service_area_id) on delete restrict, coverage_type text not null default 'SERVICE' check (coverage_type in ('ORIGIN','DESTINATION','SERVICE','ROUTE')), status text not null default 'ACTIVE' check (status in ('ACTIVE','LIMITED','INACTIVE')), created_at timestamptz not null default now(), primary key(transport_id,service_area_id,coverage_type));
create index if not exists transport_service_areas_area_idx on core.transport_service_areas(service_area_id,status);

create table if not exists ops.region_assignments (
  assignment_id uuid primary key default gen_random_uuid(), service_area_id uuid not null references geo.service_areas(service_area_id) on delete restrict,
  owner_user_id uuid references auth.users(id) on delete restrict, owner_team text,
  responsibility_type text not null check (responsibility_type in ('CLIENT','CANDIDATE_OPS','DORM_TRANSPORT','PARTNER','DATA_QUALITY','ESCALATION')),
  effective_from timestamptz not null default now(), effective_to timestamptz,
  status text not null default 'ACTIVE' check (status in ('ACTIVE','INACTIVE','EXPIRED')), created_by text not null,
  created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
  constraint region_assignment_owner_ck check ((owner_user_id is not null) <> (owner_team is not null)),
  constraint region_assignment_time_ck check (effective_to is null or effective_to>effective_from)
);
create index if not exists region_assignments_area_status_idx on ops.region_assignments(service_area_id,status,responsibility_type);
create index if not exists region_assignments_owner_idx on ops.region_assignments(owner_user_id,status) where owner_user_id is not null;

insert into config.system_settings(setting_key,setting_value,description,source_ref) values
('portal_external_access_enabled','false'::jsonb,'Master switch for external portal access. Must remain off until portal acceptance and Founder/Architect approval.','Part7A'),
('portal_candidate_enabled','false'::jsonb,'Candidate external portal feature gate.','Part7A'),('portal_partner_enabled','false'::jsonb,'Partner external portal feature gate.','Part7A'),('portal_client_enabled','false'::jsonb,'Client external portal feature gate.','Part7A'),('province_scale_activation_enabled','false'::jsonb,'Province ACTIVE lifecycle transition master gate.','Part7A'),('marketplace_enabled','false'::jsonb,'Part 7 does not authorize public marketplace capability.','Part7A'),('portal_scale_foundation_ready','false'::jsonb,'Part 7A geography/organization/access foundation readiness.','Part7A'),('part7a_foundation_closed','false'::jsonb,'Part 7A implementation closeout flag.','Part7A')
on conflict(setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=now();

alter table geo.provinces enable row level security; alter table geo.service_areas enable row level security; alter table authz.organizations enable row level security; alter table authz.organization_members enable row level security; alter table authz.candidate_user_links enable row level security; alter table core.job_service_areas enable row level security; alter table core.partner_service_areas enable row level security; alter table core.dorm_service_areas enable row level security; alter table core.transport_service_areas enable row level security; alter table ops.region_assignments enable row level security;
revoke all on schema geo from public,anon,authenticated;
revoke all on geo.provinces,geo.service_areas,authz.organizations,authz.organization_members,authz.candidate_user_links,core.job_service_areas,core.partner_service_areas,core.dorm_service_areas,core.transport_service_areas,ops.region_assignments from public,anon,authenticated;
grant usage on schema geo to service_role;
grant select,insert,update,delete on geo.provinces,geo.service_areas,authz.organizations,authz.organization_members,authz.candidate_user_links,core.job_service_areas,core.partner_service_areas,core.dorm_service_areas,core.transport_service_areas,ops.region_assignments to service_role;
revoke all on function authz.validate_organization_business_party() from public,anon,authenticated; revoke all on function authz.validate_portal_role_for_org() from public,anon,authenticated; grant execute on function authz.validate_organization_business_party() to service_role; grant execute on function authz.validate_portal_role_for_org() to service_role;