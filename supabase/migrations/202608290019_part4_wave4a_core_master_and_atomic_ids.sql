begin;

create schema if not exists core;
create schema if not exists private;
create schema if not exists privacy;
create schema if not exists docs;
create schema if not exists finance;
create schema if not exists authz;
create schema if not exists config;
create schema if not exists api;

create table if not exists config.id_allocators (
  entity_key text primary key,
  prefix text not null,
  next_number bigint not null check (next_number >= 1),
  digits integer not null check (digits between 1 and 12),
  active boolean not null default true,
  allocation_enabled boolean not null default true,
  conflict_status text not null default 'NONE' check (conflict_status in ('NONE','SOURCE_CONFLICT','BLOCKED')),
  source_ref text,
  rule_notes text,
  last_allocated_id text,
  last_allocated_at timestamptz,
  last_allocation_owner text,
  source_snapshot_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(prefix)
);

create table if not exists config.id_allocation_audit (
  allocation_pk uuid primary key default gen_random_uuid(),
  entity_key text not null references config.id_allocators(entity_key) on delete restrict,
  allocated_number bigint not null,
  allocated_id text not null unique,
  allocation_owner text not null,
  allocated_at timestamptz not null default now(),
  metadata jsonb not null default '{}'::jsonb,
  unique(entity_key, allocated_number)
);
create index if not exists id_allocation_audit_entity_idx on config.id_allocation_audit(entity_key, allocated_at desc);

insert into config.id_allocators(entity_key,prefix,next_number,digits,active,allocation_enabled,conflict_status,source_ref,rule_notes,last_allocated_id,last_allocated_at,last_allocation_owner,source_snapshot_at)
values
 ('Candidate','MYC-C-',1,6,true,false,'SOURCE_CONFLICT','DataHub:98_System_Config','Data Hub says MYC-C- Founder approved 2026-08-29; Founder Master/Control still preserve WC-C-. Allocation blocked until Founder resolves.',null,null,null,now()),
 ('Job','WC-J-',1,6,true,true,'NONE','DataHub:98_System_Config','Data Hub ID format',null,null,null,now()),
 ('Client','WC-B2B-',1,4,true,true,'NONE','DataHub:98_System_Config','Founder Master ID Framework',null,null,null,now()),
 ('Partner','WC-P-',3,4,true,true,'NONE','DataHub:98_System_Config','Founder Master ID Framework','WC-P-0002','2026-08-29 13:48:00+07','CHAT_00 Founder Secretary',now()),
 ('Placement','WC-PL-',1,6,true,true,'NONE','DataHub:98_System_Config','Founder Master ID Framework',null,null,null,now()),
 ('Transport','WC-TR-',1,4,true,true,'NONE','DataHub:98_System_Config','System implementation ID',null,null,null,now()),
 ('Evidence','WC-EV-',1,6,true,true,'NONE','DataHub:98_System_Config','System implementation ID',null,null,null,now()),
 ('Consent','WC-CN-',1,6,true,true,'NONE','DataHub:98_System_Config','System implementation ID',null,null,null,now()),
 ('Content','WC-CT-',3,6,true,true,'NONE','DataHub:98_System_Config','System implementation ID','WC-CT-000002','2026-08-29 13:48:00+07','CHAT_00 Founder Secretary',now()),
 ('Activity','WC-ACT-',1,6,true,true,'NONE','DataHub:98_System_Config','System implementation ID',null,null,null,now()),
 ('AI Run','WC-AI-',1,6,true,true,'NONE','DataHub:98_System_Config','System implementation ID',null,null,null,now()),
 ('Risk','WC-RSK-',37,3,true,true,'NONE','DataHub:98_System_Config','001-036 already reserved/used by architecture risk register','WC-RSK-036',null,'System',now()),
 ('Raw Input','WC-RAW-',3,6,true,true,'NONE','DataHub:98_System_Config','Raw input provenance ID','WC-RAW-000002','2026-08-29 13:48:00+07','CHAT_00 Founder Secretary',now()),
 ('File Registry','WC-FILE-',3,6,true,true,'NONE','DataHub:98_System_Config','File registry ID','WC-FILE-000002','2026-08-29 13:48:00+07','CHAT_00 Founder Secretary',now()),
 ('DQ Issue','WC-DQ-',1,6,true,true,'NONE','DataHub:98_System_Config','Data quality issue ID',null,null,'System',now()),
 ('Journal Batch','WC-JRN-',1,6,true,true,'NONE','DataHub:98_System_Config','Accounting journal batch',null,null,'System',now()),
 ('AR','WC-AR-',1,6,true,true,'NONE','DataHub:98_System_Config','Accounts receivable record',null,null,'System',now()),
 ('AP','WC-AP-',1,6,true,true,'NONE','DataHub:98_System_Config','Accounts payable record',null,null,'System',now()),
 ('Bank Txn','WC-BANK-',1,6,true,true,'NONE','DataHub:98_System_Config','Bank/cash transaction',null,null,'System',now()),
 ('Tax Doc','WC-TAX-',1,6,true,true,'NONE','DataHub:98_System_Config','Accounting tax/document register',null,null,'System',now())
on conflict (entity_key) do update set
 prefix=excluded.prefix,
 next_number=greatest(config.id_allocators.next_number, excluded.next_number),
 digits=excluded.digits,
 active=excluded.active,
 allocation_enabled=excluded.allocation_enabled,
 conflict_status=excluded.conflict_status,
 source_ref=excluded.source_ref,
 rule_notes=excluded.rule_notes,
 last_allocated_id=coalesce(excluded.last_allocated_id,config.id_allocators.last_allocated_id),
 last_allocated_at=coalesce(excluded.last_allocated_at,config.id_allocators.last_allocated_at),
 last_allocation_owner=coalesce(excluded.last_allocation_owner,config.id_allocators.last_allocation_owner),
 source_snapshot_at=excluded.source_snapshot_at,
 updated_at=now();

create or replace function config.peek_business_id(p_entity_key text)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare v config.id_allocators; v_preview text;
begin
  select * into v from config.id_allocators where lower(entity_key)=lower(p_entity_key);
  if not found then raise exception 'unknown entity allocator: %',p_entity_key; end if;
  if length(v.next_number::text)>v.digits then raise exception 'allocator exhausted for %',v.entity_key; end if;
  v_preview:=v.prefix||lpad(v.next_number::text,v.digits,'0');
  return jsonb_build_object('entity_key',v.entity_key,'next_id',v_preview,'next_number',v.next_number,'active',v.active,'allocation_enabled',v.allocation_enabled,'conflict_status',v.conflict_status,'source_ref',v.source_ref);
end;$$;

create or replace function config.allocate_business_id(
  p_entity_key text,
  p_allocation_owner text default 'system',
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v config.id_allocators; v_id text; v_no bigint;
begin
  if p_allocation_owner is null or btrim(p_allocation_owner)='' then raise exception 'allocation_owner required'; end if;
  select * into v from config.id_allocators where lower(entity_key)=lower(p_entity_key) for update;
  if not found then raise exception 'unknown entity allocator: %',p_entity_key; end if;
  if not v.active then raise exception 'allocator inactive for %',v.entity_key; end if;
  if not v.allocation_enabled then raise exception 'allocator blocked for %: %',v.entity_key,v.conflict_status; end if;
  if length(v.next_number::text)>v.digits then raise exception 'allocator exhausted for %',v.entity_key; end if;
  v_no:=v.next_number;
  v_id:=v.prefix||lpad(v_no::text,v.digits,'0');
  insert into config.id_allocation_audit(entity_key,allocated_number,allocated_id,allocation_owner,metadata)
  values(v.entity_key,v_no,v_id,p_allocation_owner,coalesce(p_metadata,'{}'::jsonb));
  update config.id_allocators
     set next_number=v_no+1,last_allocated_id=v_id,last_allocated_at=now(),last_allocation_owner=p_allocation_owner,updated_at=now()
   where entity_key=v.entity_key;
  return jsonb_build_object('entity_key',v.entity_key,'allocated_number',v_no,'allocated_id',v_id,'next_number',v_no+1);
end;$$;

create table if not exists core.clients (
  client_id text primary key check (client_id ~ '^WC-B2B-[0-9]{4}$'),
  client_type text,
  company_name text,
  province text,
  area text,
  crm_status text,
  payment_term text,
  billing_cycle text,
  verification_status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists core.partners (
  partner_id text primary key check (partner_id ~ '^WC-P-[0-9]{4}$'),
  partner_name text,
  partner_type text,
  province text,
  parent_partner_id text references core.partners(partner_id) on delete restrict,
  status text,
  started_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists partners_parent_idx on core.partners(parent_partner_id) where parent_partner_id is not null;

create table if not exists core.jobs (
  job_id text primary key check (job_id ~ '^WC-J-[0-9]{6}$'),
  client_id text not null references core.clients(client_id) on delete restrict,
  workplace_name text,
  province text,
  area text,
  position_name text,
  headcount integer check (headcount is null or headcount >= 0),
  wage numeric(14,2) check (wage is null or wage >= 0),
  shift text,
  start_date date,
  milestone_deal text,
  payment_term text,
  status text,
  last_confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists jobs_client_idx on core.jobs(client_id);

create table if not exists core.candidates (
  candidate_id text primary key,
  nickname text,
  origin_province text,
  education text,
  primary_experience text,
  preferred_job text,
  expected_income numeric(14,2) check (expected_income is null or expected_income >= 0),
  shift_preference text,
  relocation_ready boolean,
  ready_date date,
  has_vehicle boolean,
  dorm_needed boolean,
  dorm_budget numeric(14,2) check (dorm_budget is null or dorm_budget >= 0),
  documents_ready boolean,
  medical_ready boolean,
  source_type text,
  partner_id text references core.partners(partner_id) on delete restrict,
  status text,
  next_action text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
comment on column core.candidates.candidate_id is 'Candidate business ID. Prefix constraint intentionally deferred because live Data Hub MYC-C- conflicts with Founder Master/Control WC-C- as of 2026-08-29.';
create index if not exists candidates_partner_idx on core.candidates(partner_id) where partner_id is not null;

create table if not exists core.dorms (
  dorm_id text primary key,
  dorm_name text,
  province text,
  area text,
  map_link text,
  rent numeric(14,2) check (rent is null or rent >= 0),
  deposit numeric(14,2) check (deposit is null or deposit >= 0),
  advance numeric(14,2) check (advance is null or advance >= 0),
  vacancy boolean,
  vacancy_count integer check (vacancy_count is null or vacancy_count >= 0),
  status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists core.transport_providers (
  transport_id text primary key check (transport_id ~ '^WC-TR-[0-9]{4}$'),
  provider_name text,
  vehicle_type text,
  origin_area text,
  service_area text,
  capacity integer check (capacity is null or capacity >= 0),
  price_per_trip numeric(14,2) check (price_per_trip is null or price_per_trip >= 0),
  payment_term text,
  availability text,
  status text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists core.placements (
  placement_id text primary key check (placement_id ~ '^WC-PL-[0-9]{6}$'),
  candidate_id text not null references core.candidates(candidate_id) on delete restrict,
  job_id text not null references core.jobs(job_id) on delete restrict,
  status text not null,
  submitted_at timestamptz,
  appointment_at timestamptz,
  applied_at timestamptz,
  start_date date,
  dropout_reason text,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists placements_candidate_idx on core.placements(candidate_id);
create index if not exists placements_job_idx on core.placements(job_id);
create unique index if not exists placements_candidate_job_status_uq on core.placements(candidate_id,job_id,status);

create table if not exists core.followups (
  followup_id text primary key,
  placement_id text not null references core.placements(placement_id) on delete restrict,
  followed_up_at timestamptz,
  milestone text,
  result text,
  issue_detail text,
  case_open boolean,
  owner text,
  next_action text,
  next_followup_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists followups_placement_idx on core.followups(placement_id);
create index if not exists followups_next_idx on core.followups(next_followup_at) where next_followup_at is not null;

revoke all on schema core,private,privacy,docs,finance,authz,config,api from public,anon,authenticated;
revoke all on all tables in schema core from anon,authenticated;
revoke all on all tables in schema config from anon,authenticated;
revoke execute on all functions in schema config from public,anon,authenticated;
grant usage on schema core,config to service_role;
grant select,insert,update,delete on all tables in schema core to service_role;
grant select,insert,update,delete on all tables in schema config to service_role;
grant execute on all functions in schema config to service_role;

commit;
