create or replace function api.portal_candidate_self_profile()
returns table(
  candidate_id text,
  nickname text,
  origin_province text,
  education text,
  primary_experience text,
  preferred_job text,
  expected_income numeric,
  shift_preference text,
  relocation_ready boolean,
  ready_date date,
  has_vehicle boolean,
  dorm_needed boolean,
  dorm_budget numeric,
  documents_ready boolean,
  medical_ready boolean,
  status text,
  next_action text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_candidate_id text;
begin
  perform authz.require_external_portal_enabled('CANDIDATE');
  v_candidate_id:=authz.current_candidate_id();
  if v_candidate_id is null then raise exception 'VERIFIED_CANDIDATE_LINK_REQUIRED'; end if;
  return query
  select c.candidate_id,c.nickname,c.origin_province,c.education,c.primary_experience,c.preferred_job,
         c.expected_income,c.shift_preference,c.relocation_ready,c.ready_date,c.has_vehicle,c.dorm_needed,
         c.dorm_budget,c.documents_ready,c.medical_ready,c.status,c.next_action,c.updated_at
  from core.candidates c
  where c.candidate_id=v_candidate_id
    and authz.is_verified_candidate_user(c.candidate_id);
end
$$;

create or replace function api.portal_partner_referral_status(p_org_id uuid)
returns table(
  candidate_id text,
  candidate_nickname text,
  candidate_status text,
  placement_id text,
  job_id text,
  placement_status text,
  appointment_at timestamptz,
  start_date date,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_partner_id text;
begin
  perform authz.require_external_portal_enabled('PARTNER');
  if not authz.is_active_org_member(p_org_id) then raise exception 'ORG_MEMBERSHIP_REQUIRED'; end if;
  select o.business_party_id into v_partner_id
  from authz.organizations o where o.org_id=p_org_id and o.org_type='PARTNER' and o.status='ACTIVE';
  if v_partner_id is null then raise exception 'ACTIVE_PARTNER_ORGANIZATION_REQUIRED'; end if;

  return query
  select c.candidate_id,c.nickname,c.status,p.placement_id,p.job_id,p.status,p.appointment_at,p.start_date,
         greatest(c.updated_at,coalesce(p.updated_at,c.updated_at))
  from core.candidates c
  left join core.placements p on p.candidate_id=c.candidate_id
  where c.partner_id=v_partner_id
  order by c.candidate_id,p.placement_id;
end
$$;

create or replace function api.portal_partner_commission_status(p_org_id uuid)
returns table(
  commission_id text,
  placement_id text,
  milestone text,
  commission_amount numeric,
  state text,
  earned_date date,
  payable_date date,
  paid_date date,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_partner_id text;
begin
  perform authz.require_external_portal_enabled('PARTNER');
  if not authz.is_active_org_member(p_org_id) then raise exception 'ORG_MEMBERSHIP_REQUIRED'; end if;
  if not authz.has_portal_role(p_org_id,'partner_admin') then raise exception 'PARTNER_ADMIN_REQUIRED'; end if;
  select o.business_party_id into v_partner_id
  from authz.organizations o where o.org_id=p_org_id and o.org_type='PARTNER' and o.status='ACTIVE';
  if v_partner_id is null then raise exception 'ACTIVE_PARTNER_ORGANIZATION_REQUIRED'; end if;

  return query
  select c.commission_id,c.placement_id,c.milestone,c.commission_amount,c.state,
         c.earned_date,c.payable_date,c.paid_date,c.updated_at
  from finance.commissions c
  where c.partner_id=v_partner_id
  order by c.updated_at desc,c.commission_id;
end
$$;

create or replace function api.portal_client_jobs(p_org_id uuid)
returns table(
  job_id text,
  workplace_name text,
  province text,
  area text,
  position_name text,
  headcount integer,
  wage numeric,
  shift text,
  start_date date,
  status text,
  last_confirmed_at timestamptz,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_client_id text;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  if not authz.is_active_org_member(p_org_id) then raise exception 'ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_admin') or authz.has_portal_role(p_org_id,'client_recruiter') or authz.has_portal_role(p_org_id,'client_finance')) then
    raise exception 'CLIENT_PORTAL_ROLE_REQUIRED';
  end if;
  select o.business_party_id into v_client_id
  from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORGANIZATION_REQUIRED'; end if;

  return query
  select j.job_id,j.workplace_name,j.province,j.area,j.position_name,j.headcount,j.wage,j.shift,
         j.start_date,j.status,j.last_confirmed_at,j.updated_at
  from core.jobs j where j.client_id=v_client_id
  order by j.updated_at desc,j.job_id;
end
$$;

create or replace function api.portal_client_candidate_submissions(p_org_id uuid)
returns table(
  placement_id text,
  job_id text,
  candidate_id text,
  candidate_nickname text,
  education text,
  primary_experience text,
  relocation_ready boolean,
  ready_date date,
  documents_ready boolean,
  medical_ready boolean,
  placement_status text,
  submitted_at timestamptz,
  appointment_at timestamptz,
  applied_at timestamptz,
  start_date date,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_client_id text;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  if not authz.is_active_org_member(p_org_id) then raise exception 'ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_admin') or authz.has_portal_role(p_org_id,'client_recruiter')) then
    raise exception 'CLIENT_RECRUITMENT_ROLE_REQUIRED';
  end if;
  select o.business_party_id into v_client_id
  from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORGANIZATION_REQUIRED'; end if;

  return query
  select p.placement_id,p.job_id,p.candidate_id,c.nickname,c.education,c.primary_experience,
         c.relocation_ready,c.ready_date,c.documents_ready,c.medical_ready,p.status,
         p.submitted_at,p.appointment_at,p.applied_at,p.start_date,p.updated_at
  from core.placements p
  join core.jobs j on j.job_id=p.job_id and j.client_id=v_client_id
  join core.candidates c on c.candidate_id=p.candidate_id
  where authz.is_active_client_candidate_purpose(p_org_id,p.placement_id,p.candidate_id)
  order by p.updated_at desc,p.placement_id;
end
$$;

create or replace function api.portal_client_invoices(p_org_id uuid)
returns table(
  ar_id text,
  placement_id text,
  invoice_no text,
  invoice_date date,
  due_date date,
  gross_amount numeric,
  deduction numeric,
  collected numeric,
  outstanding_amount numeric,
  next_action text,
  updated_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_client_id text;
begin
  perform authz.require_external_portal_enabled('CLIENT');
  if not authz.is_active_org_member(p_org_id) then raise exception 'ORG_MEMBERSHIP_REQUIRED'; end if;
  if not (authz.has_portal_role(p_org_id,'client_admin') or authz.has_portal_role(p_org_id,'client_finance')) then
    raise exception 'CLIENT_FINANCE_ROLE_REQUIRED';
  end if;
  select o.business_party_id into v_client_id
  from authz.organizations o where o.org_id=p_org_id and o.org_type='CLIENT' and o.status='ACTIVE';
  if v_client_id is null then raise exception 'ACTIVE_CLIENT_ORGANIZATION_REQUIRED'; end if;

  return query
  select a.ar_id,a.placement_id,a.invoice_no,a.invoice_date,a.due_date,a.gross_amount,a.deduction,a.collected,
         greatest(a.gross_amount-a.deduction-a.collected,0::numeric),a.next_action,a.updated_at
  from finance.accounts_receivable a
  where a.client_id=v_client_id
  order by a.due_date,a.invoice_no;
end
$$;

revoke all on function api.portal_candidate_self_profile() from public, anon, authenticated;
revoke all on function api.portal_partner_referral_status(uuid) from public, anon, authenticated;
revoke all on function api.portal_partner_commission_status(uuid) from public, anon, authenticated;
revoke all on function api.portal_client_jobs(uuid) from public, anon, authenticated;
revoke all on function api.portal_client_candidate_submissions(uuid) from public, anon, authenticated;
revoke all on function api.portal_client_invoices(uuid) from public, anon, authenticated;

grant execute on function api.portal_candidate_self_profile() to authenticated;
grant execute on function api.portal_partner_referral_status(uuid) to authenticated;
grant execute on function api.portal_partner_commission_status(uuid) to authenticated;
grant execute on function api.portal_client_jobs(uuid) to authenticated;
grant execute on function api.portal_client_candidate_submissions(uuid) to authenticated;
grant execute on function api.portal_client_invoices(uuid) to authenticated;

grant execute on function api.portal_candidate_self_profile() to service_role;
grant execute on function api.portal_partner_referral_status(uuid) to service_role;
grant execute on function api.portal_partner_commission_status(uuid) to service_role;
grant execute on function api.portal_client_jobs(uuid) to service_role;
grant execute on function api.portal_client_candidate_submissions(uuid) to service_role;
grant execute on function api.portal_client_invoices(uuid) to service_role;