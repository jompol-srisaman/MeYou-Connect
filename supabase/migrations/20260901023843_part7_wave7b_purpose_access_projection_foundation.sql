create table authz.client_candidate_purpose_access (
  access_id uuid primary key default gen_random_uuid(),
  org_id uuid not null references authz.organizations(org_id) on delete restrict,
  placement_id text not null references core.placements(placement_id) on delete restrict,
  candidate_id text not null references core.candidates(candidate_id) on delete restrict,
  purpose text not null default 'RECRUITMENT_SUBMISSION' check (purpose in ('RECRUITMENT_SUBMISSION')),
  access_status text not null default 'ACTIVE' check (access_status in ('ACTIVE','REVOKED','EXPIRED')),
  valid_from timestamptz not null default now(),
  valid_until timestamptz,
  granted_by text not null,
  evidence_ref text,
  revoked_at timestamptz,
  revoked_by text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint client_candidate_purpose_access_window_check check (valid_until is null or valid_until > valid_from),
  unique (org_id, placement_id, purpose)
);

create index client_candidate_purpose_access_placement_idx
  on authz.client_candidate_purpose_access(placement_id, access_status);
create index client_candidate_purpose_access_candidate_idx
  on authz.client_candidate_purpose_access(candidate_id, access_status);
create index client_candidate_purpose_access_active_window_idx
  on authz.client_candidate_purpose_access(org_id, access_status, valid_until);

create or replace function authz.validate_client_candidate_purpose_access()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_org_type text;
  v_business_party_id text;
  v_org_status text;
  v_candidate_id text;
  v_client_id text;
begin
  select o.org_type,o.business_party_id,o.status
    into v_org_type,v_business_party_id,v_org_status
  from authz.organizations o
  where o.org_id=new.org_id;

  if v_org_type is distinct from 'CLIENT' or v_org_status is distinct from 'ACTIVE' then
    raise exception 'CLIENT_ORGANIZATION_REQUIRED';
  end if;

  select p.candidate_id,j.client_id
    into v_candidate_id,v_client_id
  from core.placements p
  join core.jobs j on j.job_id=p.job_id
  where p.placement_id=new.placement_id;

  if v_candidate_id is null then
    raise exception 'PLACEMENT_NOT_FOUND';
  end if;
  if v_candidate_id is distinct from new.candidate_id then
    raise exception 'PURPOSE_ACCESS_CANDIDATE_MISMATCH';
  end if;
  if v_client_id is distinct from v_business_party_id then
    raise exception 'PURPOSE_ACCESS_CLIENT_MISMATCH';
  end if;

  new.updated_at:=now();
  return new;
end
$$;

revoke all on function authz.validate_client_candidate_purpose_access() from public, anon, authenticated;
grant execute on function authz.validate_client_candidate_purpose_access() to service_role;

create trigger client_candidate_purpose_access_validate_trg
before insert or update on authz.client_candidate_purpose_access
for each row execute function authz.validate_client_candidate_purpose_access();

create or replace function authz.is_active_client_candidate_purpose(
  p_org_id uuid,
  p_placement_id text,
  p_candidate_id text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select authz.is_active_org_member(p_org_id)
     and exists (
       select 1
       from authz.organizations o
       join authz.client_candidate_purpose_access a on a.org_id=o.org_id
       join core.placements p on p.placement_id=a.placement_id and p.candidate_id=a.candidate_id
       join core.jobs j on j.job_id=p.job_id and j.client_id=o.business_party_id
       where o.org_id=p_org_id
         and o.org_type='CLIENT'
         and o.status='ACTIVE'
         and a.placement_id=p_placement_id
         and a.candidate_id=p_candidate_id
         and a.purpose='RECRUITMENT_SUBMISSION'
         and a.access_status='ACTIVE'
         and a.valid_from<=now()
         and (a.valid_until is null or a.valid_until>now())
         and a.revoked_at is null
     );
$$;

revoke all on function authz.is_active_client_candidate_purpose(uuid,text,text) from public, anon, authenticated;
grant execute on function authz.is_active_client_candidate_purpose(uuid,text,text) to service_role;

create or replace function authz.require_external_portal_enabled(p_portal_kind text)
returns void
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_master boolean;
  v_portal boolean;
  v_key text;
begin
  select coalesce((setting_value #>> '{}')::boolean,false)
    into v_master
  from config.system_settings
  where setting_key='portal_external_access_enabled';
  if not coalesce(v_master,false) then
    raise exception 'PORTAL_EXTERNAL_ACCESS_DISABLED';
  end if;

  v_key:=case upper(p_portal_kind)
    when 'CANDIDATE' then 'portal_candidate_enabled'
    when 'PARTNER' then 'portal_partner_enabled'
    when 'CLIENT' then 'portal_client_enabled'
    else null
  end;
  if v_key is null then raise exception 'INVALID_PORTAL_KIND'; end if;

  select coalesce((setting_value #>> '{}')::boolean,false)
    into v_portal
  from config.system_settings
  where setting_key=v_key;
  if not coalesce(v_portal,false) then
    raise exception '%_PORTAL_DISABLED',upper(p_portal_kind);
  end if;
end
$$;

revoke all on function authz.require_external_portal_enabled(text) from public, anon, authenticated;
grant execute on function authz.require_external_portal_enabled(text) to service_role;

create table ops.part7b_acceptance_catalog (
  test_id text primary key,
  scenario text not null,
  expected_behavior text not null,
  status text not null default 'NOT_RUN' check (status in ('NOT_RUN','PASS','FAIL','BLOCKED')),
  evidence_ref text,
  last_tested_at timestamptz,
  updated_at timestamptz not null default now()
);

insert into ops.part7b_acceptance_catalog(test_id,scenario,expected_behavior) values
('P7B-001','Candidate self projection','Only verified linked Candidate is returned; no cross-candidate selector'),
('P7B-002','Partner referral projection isolation','Partner member sees only own attributed referrals'),
('P7B-003','Partner commission projection isolation','Partner member sees only own commission status projection'),
('P7B-004','Client job projection isolation','Client member sees only own jobs'),
('P7B-005','Client candidate purpose isolation','Only active purpose-window submissions are visible'),
('P7B-006','Client invoice projection isolation','Client member sees only own AR/invoice projection'),
('P7B-007','Removed membership endpoint denial','Removed member is denied with stale JWT subject'),
('P7B-008','Spoofed organization denial','User cannot query an organization without active membership'),
('P7B-009','Anonymous portal projection denial','anon cannot execute external portal projection RPCs'),
('P7B-010','Minimum candidate projection boundary','Client projection omits full Candidate Master/source/partner/notes/history')
on conflict (test_id) do update set scenario=excluded.scenario,expected_behavior=excluded.expected_behavior,updated_at=now();

alter table authz.client_candidate_purpose_access enable row level security;
alter table ops.part7b_acceptance_catalog enable row level security;

create policy deny_client_authz_client_candidate_purpose_access
on authz.client_candidate_purpose_access as restrictive for all to anon, authenticated
using (false) with check (false);
create policy deny_client_ops_part7b_acceptance_catalog
on ops.part7b_acceptance_catalog as restrictive for all to anon, authenticated
using (false) with check (false);

revoke all on authz.client_candidate_purpose_access from anon, authenticated;
revoke all on ops.part7b_acceptance_catalog from anon, authenticated;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at) values
('part7b_projection_foundation_ready','true'::jsonb,'Part 7B purpose-specific portal read projection foundation exists in TEST.','Part7B',now()),
('part7b_foundation_closed','false'::jsonb,'Part 7B remains open until projection acceptance, security/performance and closeout pass.','Part7B',now())
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;