begin;

create table if not exists ops.domain_worker_contracts (
  worker_key text primary key references ops.worker_registry(worker_key) on delete restrict,
  domain text not null,
  allowed_event_types text[] not null,
  command_type text not null,
  target_entity_type text,
  requires_raw_input boolean not null default true,
  requires_file_intake boolean not null default false,
  requires_approval boolean not null default false,
  active boolean not null default true,
  contract_version text not null default '1.0',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.domain_worker_contracts(
  worker_key, domain, allowed_event_types, command_type, target_entity_type,
  requires_raw_input, requires_file_intake, requires_approval, active
) values
  ('candidate_intake','Candidate',array['candidate.lead.received'],'candidate.upsert_proposal','Candidate',true,false,false,true),
  ('candidate_worker','Candidate',array['candidate.profile.updated'],'candidate.update_proposal','Candidate',true,false,false,true),
  ('client_job_worker','Client/Job',array['client.demand.received'],'client_job.upsert_proposal','Client/Job',true,false,false,true),
  ('job_worker','Job',array['job.detail.confirmed'],'job.update_proposal','Job',true,false,false,true),
  ('file_evidence_worker','Evidence',array['file.uploaded'],'evidence.register_proposal','Evidence',true,true,false,true),
  ('domain_router','Evidence',array['evidence.registered'],'evidence.route_proposal','Evidence',true,false,false,true),
  ('attribution_worker','Partner',array['partner.referral.received'],'partner_attribution.proposal','Candidate/Partner',true,false,false,true),
  ('consent_worker','Consent',array['candidate.consent.received'],'consent.record_proposal','Consent',true,false,false,true)
on conflict (worker_key) do update set
  domain=excluded.domain,
  allowed_event_types=excluded.allowed_event_types,
  command_type=excluded.command_type,
  target_entity_type=excluded.target_entity_type,
  requires_raw_input=excluded.requires_raw_input,
  requires_file_intake=excluded.requires_file_intake,
  requires_approval=excluded.requires_approval,
  active=excluded.active,
  contract_version=excluded.contract_version,
  updated_at=now();

create table if not exists ops.domain_commands (
  command_pk uuid primary key default gen_random_uuid(),
  command_key text not null unique,
  event_pk uuid not null references ops.events(event_pk) on delete restrict,
  worker_run_pk uuid not null references ops.worker_runs(worker_run_pk) on delete restrict,
  worker_key text not null references ops.worker_registry(worker_key) on delete restrict,
  command_type text not null,
  target_entity_type text,
  target_entity_id text,
  source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
  payload jsonb not null default '{}'::jsonb,
  validation_status text not null default 'PENDING'
    check (validation_status in ('PENDING','VALID','INVALID','REVIEW')),
  validation_errors jsonb not null default '[]'::jsonb,
  apply_status text not null default 'PROPOSED'
    check (apply_status in ('PROPOSED','READY','APPLIED','CANCELLED','FAILED')),
  approval_id uuid references ops.approvals(approval_id) on delete restrict,
  master_effect_ref text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  applied_at timestamptz
);

create index if not exists domain_commands_event_idx on ops.domain_commands(event_pk, created_at);
create index if not exists domain_commands_worker_idx on ops.domain_commands(worker_key, validation_status, apply_status);
create index if not exists domain_commands_raw_idx on ops.domain_commands(source_raw_input_id) where source_raw_input_id is not null;
create index if not exists domain_commands_worker_run_idx on ops.domain_commands(worker_run_pk);
create index if not exists domain_commands_approval_idx on ops.domain_commands(approval_id) where approval_id is not null;

create or replace function ops.validate_domain_command(p_command_pk uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_cmd ops.domain_commands;
  v_event ops.events;
  v_contract ops.domain_worker_contracts;
  v_errors jsonb := '[]'::jsonb;
  v_status text := 'VALID';
  v_has_file boolean := false;
begin
  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk for update;
  if not found then raise exception 'unknown command_pk: %', p_command_pk; end if;

  select * into v_event from ops.events where event_pk=v_cmd.event_pk;
  select * into v_contract from ops.domain_worker_contracts where worker_key=v_cmd.worker_key and active=true;

  if not found then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','CONTRACT_MISSING','message','active worker contract not found'));
  else
    if not (v_event.event_type = any(v_contract.allowed_event_types)) then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','EVENT_NOT_ALLOWED','message','event type is not allowed by worker contract'));
    end if;
    if v_cmd.command_type <> v_contract.command_type then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','COMMAND_TYPE_MISMATCH','message','command type does not match worker contract'));
    end if;
    if v_contract.requires_raw_input and v_cmd.source_raw_input_id is null then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','RAW_INPUT_REQUIRED','message','material domain command requires raw input provenance'));
    end if;
    if v_contract.requires_file_intake then
      select exists(select 1 from ops.file_intake f where f.raw_input_id=v_cmd.source_raw_input_id) into v_has_file;
      if not v_has_file then
        v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','FILE_INTAKE_REQUIRED','message','evidence command requires registered file intake'));
      end if;
    end if;
  end if;

  if jsonb_typeof(v_cmd.payload) <> 'object' or v_cmd.payload = '{}'::jsonb then
    v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','PAYLOAD_REQUIRED','message','command payload must be a non-empty JSON object'));
  end if;

  if v_cmd.worker_key in ('candidate_intake','candidate_worker') then
    if not (v_cmd.payload ? 'candidate' or v_cmd.payload ? 'fields') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','CANDIDATE_FIELDS_REQUIRED','message','candidate command requires candidate or fields object'));
    end if;
    if v_cmd.target_entity_id is not null and v_cmd.target_entity_id !~ '^WC-C-[0-9]{6}$' then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','INVALID_CANDIDATE_ID','message','known Candidate ID must match WC-C-######'));
    end if;
  elsif v_cmd.worker_key in ('client_job_worker','job_worker') then
    if not (v_cmd.payload ? 'client' or v_cmd.payload ? 'job' or v_cmd.payload ? 'fields') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','CLIENT_JOB_FIELDS_REQUIRED','message','client/job command requires client, job, or fields object'));
    end if;
  elsif v_cmd.worker_key='file_evidence_worker' then
    if not (v_cmd.payload ? 'file' or v_cmd.payload ? 'evidence' or v_cmd.payload ? 'file_intake_pk') then
      v_errors := v_errors || jsonb_build_array(jsonb_build_object('code','EVIDENCE_FIELDS_REQUIRED','message','evidence command requires file/evidence reference'));
    end if;
  end if;

  if jsonb_array_length(v_errors)>0 then v_status := 'INVALID'; end if;

  update ops.domain_commands
     set validation_status=v_status,
         validation_errors=v_errors,
         apply_status=case when v_status='VALID' then 'READY' else 'PROPOSED' end,
         updated_at=now()
   where command_pk=p_command_pk
   returning * into v_cmd;

  return jsonb_build_object(
    'command_pk',v_cmd.command_pk,
    'command_key',v_cmd.command_key,
    'validation_status',v_cmd.validation_status,
    'apply_status',v_cmd.apply_status,
    'validation_errors',v_cmd.validation_errors
  );
end;
$$;

create or replace function ops.prepare_domain_command(
  p_event_pk uuid,
  p_worker_key text,
  p_lease_token uuid,
  p_payload jsonb,
  p_target_entity_type text default null,
  p_target_entity_id text default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_event ops.events;
  v_contract ops.domain_worker_contracts;
  v_run ops.worker_runs;
  v_cmd ops.domain_commands;
  v_key text;
  v_duplicate boolean := false;
  v_validation jsonb;
begin
  select * into v_event from ops.events where event_pk=p_event_pk;
  if not found then raise exception 'unknown event_pk: %', p_event_pk; end if;

  select * into v_contract from ops.domain_worker_contracts where worker_key=p_worker_key and active=true;
  if not found then raise exception 'worker % has no active domain contract', p_worker_key; end if;

  if not (v_event.event_type=any(v_contract.allowed_event_types)) then
    raise exception 'event_type % is not allowed for worker %', v_event.event_type, p_worker_key;
  end if;

  select * into v_run
    from ops.worker_runs
   where event_pk=p_event_pk
     and worker_key=p_worker_key
     and lease_token=p_lease_token
     and status='RUNNING'
     and lease_until>now()
   order by started_at desc
   limit 1;
  if not found then raise exception 'valid active worker lease required'; end if;

  v_key := v_event.idempotency_key || '|command|' || v_contract.command_type;

  select * into v_cmd from ops.domain_commands where command_key=v_key;
  if found then
    v_duplicate := true;
  else
    insert into ops.domain_commands(
      command_key,event_pk,worker_run_pk,worker_key,command_type,target_entity_type,target_entity_id,
      source_raw_input_id,payload,validation_status,apply_status
    ) values (
      v_key,p_event_pk,v_run.worker_run_pk,p_worker_key,v_contract.command_type,
      coalesce(p_target_entity_type,v_contract.target_entity_type),p_target_entity_id,
      v_event.raw_input_id,coalesce(p_payload,'{}'::jsonb),'PENDING','PROPOSED'
    ) returning * into v_cmd;
  end if;

  v_validation := ops.validate_domain_command(v_cmd.command_pk);

  return v_validation || jsonb_build_object(
    'event_pk',v_cmd.event_pk,
    'worker_key',v_cmd.worker_key,
    'command_type',v_cmd.command_type,
    'duplicate_command',v_duplicate,
    'source_raw_input_id',v_cmd.source_raw_input_id
  );
end;
$$;

create or replace view ops.domain_command_backlog_v
with (security_invoker=true)
as
select
  c.command_pk,c.command_key,c.event_pk,e.event_id,e.event_type,e.trace_id,
  c.worker_key,c.command_type,c.target_entity_type,c.target_entity_id,
  c.source_raw_input_id,c.validation_status,c.apply_status,c.validation_errors,
  c.approval_id,c.master_effect_ref,c.created_at,c.updated_at
from ops.domain_commands c
join ops.events e on e.event_pk=c.event_pk
where c.apply_status in ('PROPOSED','READY','FAILED');

revoke all on ops.domain_worker_contracts,ops.domain_commands from anon,authenticated;
revoke execute on function ops.validate_domain_command(uuid) from public,anon,authenticated;
revoke execute on function ops.prepare_domain_command(uuid,text,uuid,jsonb,text,text) from public,anon,authenticated;
grant select,insert,update,delete on ops.domain_worker_contracts,ops.domain_commands to service_role;
grant select on ops.domain_command_backlog_v to service_role;
grant execute on function ops.validate_domain_command(uuid) to service_role;
grant execute on function ops.prepare_domain_command(uuid,text,uuid,jsonb,text,text) to service_role;

commit;
