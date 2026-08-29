begin;

alter table ops.domain_commands drop constraint if exists domain_commands_apply_status_check;
alter table ops.domain_commands add constraint domain_commands_apply_status_check
  check (apply_status in ('PROPOSED','READY','APPLYING','APPLIED','BLOCKED','CANCELLED','FAILED'));

create table if not exists ops.master_apply_contracts (
  command_type text primary key,
  target_scope text not null check (target_scope in ('CORE','DOCS','PRIVACY')),
  gate_key text not null,
  handler_key text not null,
  allow_create boolean not null default false,
  allow_update boolean not null default false,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into ops.master_apply_contracts(command_type,target_scope,gate_key,handler_key,allow_create,allow_update,notes)
values
 ('candidate.upsert_proposal','CORE','business_master_apply_enabled','CANDIDATE',true,true,'Candidate create remains subject to Candidate allocator conflict gate.'),
 ('candidate.update_proposal','CORE','business_master_apply_enabled','CANDIDATE',false,true,'Existing Candidate update only.'),
 ('client_job.upsert_proposal','CORE','business_master_apply_enabled','CLIENT_JOB',true,true,'Controlled Client/Job create or update.'),
 ('job.update_proposal','CORE','business_master_apply_enabled','JOB',false,true,'Existing Job update only; protected terms conflict to DQ.'),
 ('partner_attribution.proposal','CORE','business_master_apply_enabled','PARTNER_ATTRIBUTION',false,true,'Attribution only; does not create Partner or Candidate.'),
 ('evidence.register_proposal','DOCS','postgres_docs_write_enabled','EVIDENCE_REGISTER',true,false,'File Intake/File Registry to Evidence.'),
 ('evidence.route_proposal','DOCS','postgres_docs_write_enabled','EVIDENCE_ROUTE',false,true,'Links existing Evidence to entity.'),
 ('consent.record_proposal','PRIVACY','postgres_consent_write_enabled','CONSENT',true,false,'Evidence-backed immutable consent history.')
on conflict(command_type) do update set
 target_scope=excluded.target_scope, gate_key=excluded.gate_key, handler_key=excluded.handler_key,
 allow_create=excluded.allow_create, allow_update=excluded.allow_update, active=true,
 notes=excluded.notes, updated_at=now();

create table if not exists ops.domain_command_apply_audit (
  apply_id uuid primary key default gen_random_uuid(),
  command_pk uuid not null unique references ops.domain_commands(command_pk) on delete restrict,
  command_key text not null,
  command_type text not null,
  status text not null check (status in ('APPLYING','APPLIED','BLOCKED','FAILED')),
  actor text not null,
  target_entity_type text,
  target_entity_id text,
  effect_ref text,
  result jsonb not null default '{}'::jsonb,
  error_class text,
  error_message text,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists domain_command_apply_audit_status_idx
  on ops.domain_command_apply_audit(status, updated_at desc);
create index if not exists domain_command_apply_audit_type_idx
  on ops.domain_command_apply_audit(command_type, updated_at desc);

create or replace function ops.open_apply_conflict(
  p_command_pk uuid,
  p_entity_type text,
  p_entity_id text,
  p_field_name text,
  p_current_value text,
  p_incoming_value text,
  p_actor text default 'system'
)
returns text
language plpgsql
security definer
set search_path=''
as $$
declare
  v_cmd ops.domain_commands;
  v_existing text;
  v_alloc jsonb;
  v_id text;
begin
  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk;
  if not found then raise exception 'unknown command_pk'; end if;

  select dq_issue_id into v_existing
  from ops.data_quality_issues
  where entity_type=p_entity_type
    and entity_id=p_entity_id
    and field_name=p_field_name
    and issue_type='DOMAIN_APPLY_CONFLICT'
    and coalesce(current_value,'')=coalesce(p_current_value,'')
    and coalesce(incoming_value,'')=coalesce(p_incoming_value,'')
    and coalesce(raw_input_id,'')=coalesce(v_cmd.source_raw_input_id,'')
    and status='OPEN'
  order by created_at desc limit 1;
  if found then return v_existing; end if;

  v_alloc:=config.allocate_business_id('DQ Issue',p_actor,jsonb_build_object('source','Part4C domain apply conflict','command_pk',p_command_pk));
  v_id:=v_alloc->>'allocated_id';
  insert into ops.data_quality_issues(
    dq_issue_id,entity_type,entity_id,field_name,issue_type,current_value,incoming_value,
    raw_input_id,severity,status,resolution
  ) values(
    v_id,p_entity_type,p_entity_id,p_field_name,'DOMAIN_APPLY_CONFLICT',p_current_value,p_incoming_value,
    v_cmd.source_raw_input_id,'HIGH','OPEN','Blocked by Part4C controlled apply; human/source-authority review required.'
  );
  return v_id;
end;
$$;

create or replace function ops.apply_domain_command(
  p_command_pk uuid,
  p_actor text default 'system'
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_cmd ops.domain_commands;
  v_contract ops.master_apply_contracts;
  v_audit ops.domain_command_apply_audit;
  v_existing_audit ops.domain_command_apply_audit;
  v_data jsonb;
  v_client jsonb;
  v_job jsonb;
  v_file jsonb;
  v_evidence jsonb;
  v_consent jsonb;
  v_alloc jsonb;
  v_target_id text;
  v_client_id text;
  v_job_id text;
  v_partner_id text;
  v_candidate_id text;
  v_file_id text;
  v_evidence_id text;
  v_consent_id text;
  v_effect_ref text;
  v_entity_type text;
  v_dq_id text;
  v_result jsonb;
  v_current text;
  v_incoming text;
  v_intake ops.file_intake;
  v_status text;
begin
  if p_actor is null or btrim(p_actor)='' then raise exception 'actor required'; end if;

  select * into v_cmd from ops.domain_commands where command_pk=p_command_pk for update;
  if not found then raise exception 'unknown command_pk: %',p_command_pk; end if;

  if v_cmd.apply_status='APPLIED' then
    select * into v_existing_audit from ops.domain_command_apply_audit where command_pk=p_command_pk;
    return coalesce(v_existing_audit.result,'{}'::jsonb) || jsonb_build_object(
      'command_pk',p_command_pk,'apply_status','APPLIED','duplicate_apply',true,
      'master_effect_ref',v_cmd.master_effect_ref
    );
  end if;

  if v_cmd.validation_status<>'VALID' then
    raise exception 'domain command must be VALID before apply';
  end if;
  if v_cmd.apply_status not in ('READY','BLOCKED') then
    raise exception 'domain command apply_status must be READY/BLOCKED, got %',v_cmd.apply_status;
  end if;

  select * into v_contract from ops.master_apply_contracts
  where command_type=v_cmd.command_type and active=true;
  if not found then raise exception 'no active master apply contract for %',v_cmd.command_type; end if;

  insert into ops.domain_command_apply_audit(command_pk,command_key,command_type,status,actor,target_entity_type,target_entity_id)
  values(v_cmd.command_pk,v_cmd.command_key,v_cmd.command_type,'APPLYING',p_actor,v_cmd.target_entity_type,v_cmd.target_entity_id)
  on conflict(command_pk) do update set
    status='APPLYING',actor=excluded.actor,error_class=null,error_message=null,
    started_at=now(),finished_at=null,updated_at=now()
  returning * into v_audit;

  if not config.setting_is_true(v_contract.gate_key) then
    v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','GATE_DISABLED','gate_key',v_contract.gate_key);
    update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
    update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='GATE_DISABLED',
      error_message='Required write gate is disabled',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
    return v_result;
  end if;

  update ops.domain_commands set apply_status='APPLYING',updated_at=now() where command_pk=p_command_pk;

  begin
    if v_contract.handler_key='CANDIDATE' then
      v_data:=coalesce(v_cmd.payload->'candidate',v_cmd.payload->'fields',v_cmd.payload);
      v_candidate_id:=coalesce(nullif(v_cmd.target_entity_id,''),nullif(v_data->>'candidate_id',''));

      if v_candidate_id is not null and exists(select 1 from core.candidates where candidate_id=v_candidate_id) then
        update core.candidates c set
          nickname=case when v_data ? 'nickname' then nullif(v_data->>'nickname','') else c.nickname end,
          origin_province=case when v_data ? 'origin_province' then nullif(v_data->>'origin_province','') else c.origin_province end,
          education=case when v_data ? 'education' then nullif(v_data->>'education','') else c.education end,
          primary_experience=case when v_data ? 'primary_experience' then nullif(v_data->>'primary_experience','') else c.primary_experience end,
          preferred_job=case when v_data ? 'preferred_job' then nullif(v_data->>'preferred_job','') else c.preferred_job end,
          expected_income=case when v_data ? 'expected_income' then nullif(v_data->>'expected_income','')::numeric else c.expected_income end,
          shift_preference=case when v_data ? 'shift_preference' then nullif(v_data->>'shift_preference','') else c.shift_preference end,
          relocation_ready=case when v_data ? 'relocation_ready' then nullif(v_data->>'relocation_ready','')::boolean else c.relocation_ready end,
          ready_date=case when v_data ? 'ready_date' then nullif(v_data->>'ready_date','')::date else c.ready_date end,
          has_vehicle=case when v_data ? 'has_vehicle' then nullif(v_data->>'has_vehicle','')::boolean else c.has_vehicle end,
          dorm_needed=case when v_data ? 'dorm_needed' then nullif(v_data->>'dorm_needed','')::boolean else c.dorm_needed end,
          dorm_budget=case when v_data ? 'dorm_budget' then nullif(v_data->>'dorm_budget','')::numeric else c.dorm_budget end,
          documents_ready=case when v_data ? 'documents_ready' then nullif(v_data->>'documents_ready','')::boolean else c.documents_ready end,
          medical_ready=case when v_data ? 'medical_ready' then nullif(v_data->>'medical_ready','')::boolean else c.medical_ready end,
          source_type=case when v_data ? 'source_type' then nullif(v_data->>'source_type','') else c.source_type end,
          status=case when v_data ? 'status' then nullif(v_data->>'status','') else c.status end,
          next_action=case when v_data ? 'next_action' then nullif(v_data->>'next_action','') else c.next_action end,
          updated_at=now()
        where c.candidate_id=v_candidate_id;
      else
        if not v_contract.allow_create then
          v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','TARGET_NOT_FOUND','target_entity_id',v_candidate_id);
          update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
          update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='TARGET_NOT_FOUND',error_message='Candidate update target does not exist',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
          return v_result;
        end if;
        if exists(select 1 from config.id_allocators where entity_key='Candidate' and (not allocation_enabled or conflict_status<>'NONE')) then
          v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','CANDIDATE_ID_SOURCE_CONFLICT');
          update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
          update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='SOURCE_CONFLICT',error_message='Candidate allocator remains blocked by source conflict',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
          return v_result;
        end if;
        if v_candidate_id is null then
          v_alloc:=config.allocate_business_id('Candidate',p_actor,jsonb_build_object('command_pk',p_command_pk));
          v_candidate_id:=v_alloc->>'allocated_id';
        end if;
        insert into core.candidates(candidate_id,nickname,origin_province,education,primary_experience,preferred_job,expected_income,shift_preference,relocation_ready,ready_date,has_vehicle,dorm_needed,dorm_budget,documents_ready,medical_ready,source_type,status,next_action)
        values(v_candidate_id,nullif(v_data->>'nickname',''),nullif(v_data->>'origin_province',''),nullif(v_data->>'education',''),nullif(v_data->>'primary_experience',''),nullif(v_data->>'preferred_job',''),nullif(v_data->>'expected_income','')::numeric,nullif(v_data->>'shift_preference',''),nullif(v_data->>'relocation_ready','')::boolean,nullif(v_data->>'ready_date','')::date,nullif(v_data->>'has_vehicle','')::boolean,nullif(v_data->>'dorm_needed','')::boolean,nullif(v_data->>'dorm_budget','')::numeric,nullif(v_data->>'documents_ready','')::boolean,nullif(v_data->>'medical_ready','')::boolean,nullif(v_data->>'source_type',''),nullif(v_data->>'status',''),nullif(v_data->>'next_action',''));
      end if;
      v_entity_type:='Candidate'; v_target_id:=v_candidate_id; v_effect_ref:='core.candidates:'||v_candidate_id;

    elsif v_contract.handler_key='CLIENT_JOB' then
      v_client:=coalesce(v_cmd.payload->'client','{}'::jsonb);
      v_job:=coalesce(v_cmd.payload->'job',v_cmd.payload->'fields','{}'::jsonb);
      v_client_id:=coalesce(nullif(v_client->>'client_id',''),nullif(v_cmd.payload->>'client_id',''),nullif(v_job->>'client_id',''));
      v_job_id:=coalesce(nullif(v_job->>'job_id',''),nullif(v_cmd.payload->>'job_id',''));

      if v_client_id is not null and exists(select 1 from core.clients where client_id=v_client_id) and v_client ? 'payment_term' then
        select payment_term into v_current from core.clients where client_id=v_client_id;
        v_incoming:=nullif(v_client->>'payment_term','');
        if v_current is not null and v_incoming is not null and v_current is distinct from v_incoming then
          v_dq_id:=ops.open_apply_conflict(p_command_pk,'Client',v_client_id,'payment_term',v_current,v_incoming,p_actor);
          v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','DQ_CONFLICT','dq_issue_id',v_dq_id,'field','payment_term');
          update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
          update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='DQ_CONFLICT',error_message='Client payment_term conflict',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
          return v_result;
        end if;
      end if;

      if v_job_id is not null and exists(select 1 from core.jobs where job_id=v_job_id) then
        foreach v_status in array array['wage','shift','start_date','milestone_deal','payment_term'] loop
          if v_job ? v_status then
            execute format('select %I::text from core.jobs where job_id=$1',v_status) into v_current using v_job_id;
            v_incoming:=nullif(v_job->>v_status,'');
            if v_current is not null and v_incoming is not null and v_current is distinct from v_incoming then
              v_dq_id:=ops.open_apply_conflict(p_command_pk,'Job',v_job_id,v_status,v_current,v_incoming,p_actor);
              v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','DQ_CONFLICT','dq_issue_id',v_dq_id,'field',v_status);
              update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
              update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='DQ_CONFLICT',error_message='Job protected-term conflict',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
              return v_result;
            end if;
          end if;
        end loop;
      end if;

      if v_client_id is null then
        if v_client='{}'::jsonb then raise exception 'client_id or client object required'; end if;
        v_alloc:=config.allocate_business_id('Client',p_actor,jsonb_build_object('command_pk',p_command_pk)); v_client_id:=v_alloc->>'allocated_id';
      end if;
      insert into core.clients(client_id,client_type,company_name,province,area,crm_status,payment_term,billing_cycle,verification_status)
      values(v_client_id,nullif(v_client->>'client_type',''),nullif(v_client->>'company_name',''),nullif(v_client->>'province',''),nullif(v_client->>'area',''),nullif(v_client->>'crm_status',''),nullif(v_client->>'payment_term',''),nullif(v_client->>'billing_cycle',''),nullif(v_client->>'verification_status',''))
      on conflict(client_id) do update set
        client_type=case when v_client ? 'client_type' then excluded.client_type else core.clients.client_type end,
        company_name=case when v_client ? 'company_name' then excluded.company_name else core.clients.company_name end,
        province=case when v_client ? 'province' then excluded.province else core.clients.province end,
        area=case when v_client ? 'area' then excluded.area else core.clients.area end,
        crm_status=case when v_client ? 'crm_status' then excluded.crm_status else core.clients.crm_status end,
        payment_term=case when v_client ? 'payment_term' then coalesce(core.clients.payment_term,excluded.payment_term) else core.clients.payment_term end,
        billing_cycle=case when v_client ? 'billing_cycle' then excluded.billing_cycle else core.clients.billing_cycle end,
        verification_status=case when v_client ? 'verification_status' then excluded.verification_status else core.clients.verification_status end,
        updated_at=now();

      if v_job<>'{}'::jsonb then
        if v_job_id is null then v_alloc:=config.allocate_business_id('Job',p_actor,jsonb_build_object('command_pk',p_command_pk)); v_job_id:=v_alloc->>'allocated_id'; end if;
        insert into core.jobs(job_id,client_id,workplace_name,province,area,position_name,headcount,wage,shift,start_date,milestone_deal,payment_term,status,last_confirmed_at)
        values(v_job_id,v_client_id,nullif(v_job->>'workplace_name',''),nullif(v_job->>'province',''),nullif(v_job->>'area',''),nullif(v_job->>'position_name',''),nullif(v_job->>'headcount','')::integer,nullif(v_job->>'wage','')::numeric,nullif(v_job->>'shift',''),nullif(v_job->>'start_date','')::date,nullif(v_job->>'milestone_deal',''),nullif(v_job->>'payment_term',''),nullif(v_job->>'status',''),nullif(v_job->>'last_confirmed_at','')::timestamptz)
        on conflict(job_id) do update set
          workplace_name=case when v_job ? 'workplace_name' then excluded.workplace_name else core.jobs.workplace_name end,
          province=case when v_job ? 'province' then excluded.province else core.jobs.province end,
          area=case when v_job ? 'area' then excluded.area else core.jobs.area end,
          position_name=case when v_job ? 'position_name' then excluded.position_name else core.jobs.position_name end,
          headcount=case when v_job ? 'headcount' then excluded.headcount else core.jobs.headcount end,
          wage=case when v_job ? 'wage' then coalesce(core.jobs.wage,excluded.wage) else core.jobs.wage end,
          shift=case when v_job ? 'shift' then coalesce(core.jobs.shift,excluded.shift) else core.jobs.shift end,
          start_date=case when v_job ? 'start_date' then coalesce(core.jobs.start_date,excluded.start_date) else core.jobs.start_date end,
          milestone_deal=case when v_job ? 'milestone_deal' then coalesce(core.jobs.milestone_deal,excluded.milestone_deal) else core.jobs.milestone_deal end,
          payment_term=case when v_job ? 'payment_term' then coalesce(core.jobs.payment_term,excluded.payment_term) else core.jobs.payment_term end,
          status=case when v_job ? 'status' then excluded.status else core.jobs.status end,
          last_confirmed_at=case when v_job ? 'last_confirmed_at' then excluded.last_confirmed_at else core.jobs.last_confirmed_at end,
          updated_at=now();
      end if;
      v_entity_type:=case when v_job_id is null then 'Client' else 'Client/Job' end;
      v_target_id:=coalesce(v_job_id,v_client_id);
      v_effect_ref:='core.clients:'||v_client_id||case when v_job_id is null then '' else '|core.jobs:'||v_job_id end;

    elsif v_contract.handler_key='JOB' then
      v_job:=coalesce(v_cmd.payload->'job',v_cmd.payload->'fields',v_cmd.payload);
      v_job_id:=coalesce(nullif(v_cmd.target_entity_id,''),nullif(v_job->>'job_id',''));
      if v_job_id is null or not exists(select 1 from core.jobs where job_id=v_job_id) then
        v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','TARGET_NOT_FOUND','target_entity_id',v_job_id);
        update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
        update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='TARGET_NOT_FOUND',error_message='Job update target does not exist',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
        return v_result;
      end if;
      foreach v_status in array array['wage','shift','start_date','milestone_deal','payment_term'] loop
        if v_job ? v_status then
          execute format('select %I::text from core.jobs where job_id=$1',v_status) into v_current using v_job_id;
          v_incoming:=nullif(v_job->>v_status,'');
          if v_current is not null and v_incoming is not null and v_current is distinct from v_incoming then
            v_dq_id:=ops.open_apply_conflict(p_command_pk,'Job',v_job_id,v_status,v_current,v_incoming,p_actor);
            v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','DQ_CONFLICT','dq_issue_id',v_dq_id,'field',v_status);
            update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
            update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='DQ_CONFLICT',error_message='Job protected-term conflict',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
            return v_result;
          end if;
        end if;
      end loop;
      update core.jobs j set
        workplace_name=case when v_job ? 'workplace_name' then nullif(v_job->>'workplace_name','') else j.workplace_name end,
        province=case when v_job ? 'province' then nullif(v_job->>'province','') else j.province end,
        area=case when v_job ? 'area' then nullif(v_job->>'area','') else j.area end,
        position_name=case when v_job ? 'position_name' then nullif(v_job->>'position_name','') else j.position_name end,
        headcount=case when v_job ? 'headcount' then nullif(v_job->>'headcount','')::integer else j.headcount end,
        wage=case when v_job ? 'wage' then coalesce(j.wage,nullif(v_job->>'wage','')::numeric) else j.wage end,
        shift=case when v_job ? 'shift' then coalesce(j.shift,nullif(v_job->>'shift','')) else j.shift end,
        start_date=case when v_job ? 'start_date' then coalesce(j.start_date,nullif(v_job->>'start_date','')::date) else j.start_date end,
        milestone_deal=case when v_job ? 'milestone_deal' then coalesce(j.milestone_deal,nullif(v_job->>'milestone_deal','')) else j.milestone_deal end,
        payment_term=case when v_job ? 'payment_term' then coalesce(j.payment_term,nullif(v_job->>'payment_term','')) else j.payment_term end,
        status=case when v_job ? 'status' then nullif(v_job->>'status','') else j.status end,
        last_confirmed_at=case when v_job ? 'last_confirmed_at' then nullif(v_job->>'last_confirmed_at','')::timestamptz else j.last_confirmed_at end,
        updated_at=now()
      where j.job_id=v_job_id;
      v_entity_type:='Job'; v_target_id:=v_job_id; v_effect_ref:='core.jobs:'||v_job_id;

    elsif v_contract.handler_key='PARTNER_ATTRIBUTION' then
      v_data:=coalesce(v_cmd.payload->'fields',v_cmd.payload);
      v_candidate_id:=coalesce(nullif(v_cmd.target_entity_id,''),nullif(v_data->>'candidate_id',''));
      v_partner_id:=nullif(v_data->>'partner_id','');
      if v_candidate_id is null or not exists(select 1 from core.candidates where candidate_id=v_candidate_id) then raise exception 'existing candidate_id required'; end if;
      if v_partner_id is null or not exists(select 1 from core.partners where partner_id=v_partner_id) then raise exception 'existing partner_id required'; end if;
      select partner_id into v_current from core.candidates where candidate_id=v_candidate_id;
      if v_current is not null and v_current is distinct from v_partner_id then
        v_dq_id:=ops.open_apply_conflict(p_command_pk,'Candidate',v_candidate_id,'partner_id',v_current,v_partner_id,p_actor);
        v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','BLOCKED','reason','DQ_CONFLICT','dq_issue_id',v_dq_id,'field','partner_id');
        update ops.domain_commands set apply_status='BLOCKED',updated_at=now() where command_pk=p_command_pk;
        update ops.domain_command_apply_audit set status='BLOCKED',result=v_result,error_class='DQ_CONFLICT',error_message='Partner attribution conflict',finished_at=now(),updated_at=now() where command_pk=p_command_pk;
        return v_result;
      end if;
      update core.candidates set partner_id=v_partner_id,updated_at=now() where candidate_id=v_candidate_id and partner_id is null;
      v_entity_type:='Candidate'; v_target_id:=v_candidate_id; v_effect_ref:='core.candidates:'||v_candidate_id||'|partner:'||v_partner_id;

    elsif v_contract.handler_key='EVIDENCE_REGISTER' then
      v_file:=coalesce(v_cmd.payload->'file','{}'::jsonb);
      v_evidence:=coalesce(v_cmd.payload->'evidence','{}'::jsonb);
      v_file_id:=coalesce(nullif(v_file->>'file_id',''),nullif(v_cmd.payload->>'file_id',''));
      if v_file_id is null and v_cmd.payload ? 'file_intake_pk' then
        select * into v_intake from ops.file_intake where file_intake_pk=(v_cmd.payload->>'file_intake_pk')::uuid;
        if not found then raise exception 'file_intake_pk not found'; end if;
        v_file_id:=docs.register_file_metadata(
          v_intake.raw_input_id,
          case when upper(v_intake.source_system) like '%DRIVE%' then 'GOOGLE_DRIVE' else 'OTHER' end,
          'raw-inbox-private',null,null,v_intake.provider_file_ref,null,
          coalesce(v_intake.metadata->>'source_url',v_intake.provider_file_ref),
          v_intake.original_filename,null,v_intake.content_type,v_intake.size_bytes,v_intake.checksum_sha256,
          case when v_intake.mirror_status in ('SOURCE_ONLY','MIRRORED','SOURCE_NOT_MIRRORED','STORED','ARCHIVED','FAILED') then v_intake.mirror_status else 'SOURCE_ONLY' end,
          case when v_intake.sensitive then 'PII' else 'INTERNAL' end,
          '{}'::text[],coalesce(v_intake.metadata->>'description','Applied from Part3 file intake'),p_actor
        );
      end if;
      if v_file_id is null or not exists(select 1 from docs.files where file_id=v_file_id) then raise exception 'existing file_id or valid file_intake_pk required'; end if;
      v_evidence_id:=docs.register_evidence_record(
        v_file_id,
        coalesce(nullif(v_evidence->>'evidence_type',''),nullif(v_cmd.payload->>'evidence_type',''),'FILE_EVIDENCE'),
        coalesce(nullif(v_evidence->>'evidence_class',''),nullif(v_cmd.payload->>'evidence_class',''),'BUSINESS_EVIDENCE'),
        coalesce(nullif(v_evidence->>'evidence_date',''),nullif(v_cmd.payload->>'evidence_date',''))::timestamptz,
        coalesce(nullif(v_evidence->>'source_authority',''),nullif(v_cmd.payload->>'source_authority','')),
        coalesce(nullif(v_evidence->>'notes',''),nullif(v_cmd.payload->>'notes','')),
        p_actor
      );
      if coalesce(nullif(v_evidence->>'entity_type',''),nullif(v_cmd.payload->>'entity_type','')) is not null
         and coalesce(nullif(v_evidence->>'entity_id',''),nullif(v_cmd.payload->>'entity_id','')) is not null then
        perform docs.link_evidence(v_evidence_id,
          coalesce(nullif(v_evidence->>'entity_type',''),nullif(v_cmd.payload->>'entity_type','')),
          coalesce(nullif(v_evidence->>'entity_id',''),nullif(v_cmd.payload->>'entity_id','')),
          coalesce(nullif(v_evidence->>'link_role',''),nullif(v_cmd.payload->>'link_role',''),'SUPPORTS'),p_actor);
      end if;
      v_entity_type:='Evidence'; v_target_id:=v_evidence_id; v_effect_ref:='docs.evidence:'||v_evidence_id;

    elsif v_contract.handler_key='EVIDENCE_ROUTE' then
      v_evidence:=coalesce(v_cmd.payload->'evidence',v_cmd.payload->'fields',v_cmd.payload);
      v_evidence_id:=coalesce(nullif(v_cmd.target_entity_id,''),nullif(v_evidence->>'evidence_id',''));
      if v_evidence_id is null or not exists(select 1 from docs.evidence where evidence_id=v_evidence_id) then raise exception 'existing evidence_id required'; end if;
      if nullif(v_evidence->>'entity_type','') is null or nullif(v_evidence->>'entity_id','') is null then raise exception 'entity_type and entity_id required'; end if;
      perform docs.link_evidence(v_evidence_id,v_evidence->>'entity_type',v_evidence->>'entity_id',coalesce(nullif(v_evidence->>'link_role',''),'SUPPORTS'),p_actor);
      v_entity_type:='Evidence'; v_target_id:=v_evidence_id; v_effect_ref:='docs.evidence:'||v_evidence_id||'|link:'||(v_evidence->>'entity_type')||':'||(v_evidence->>'entity_id');

    elsif v_contract.handler_key='CONSENT' then
      v_consent:=coalesce(v_cmd.payload->'consent',v_cmd.payload->'fields',v_cmd.payload);
      v_candidate_id:=coalesce(nullif(v_cmd.target_entity_id,''),nullif(v_consent->>'candidate_id',''));
      v_evidence_id:=nullif(v_consent->>'evidence_id','');
      v_consent_id:=privacy.record_consent(
        v_candidate_id,
        v_consent->>'purpose_code',
        v_consent->>'decision',
        coalesce(nullif(v_consent->>'effective_at','')::timestamptz,now()),
        v_evidence_id,
        coalesce(nullif(v_consent->>'source_raw_input_id',''),v_cmd.source_raw_input_id),
        nullif(v_consent->>'supersedes_consent_id',''),
        nullif(v_consent->>'notes',''),p_actor
      );
      v_entity_type:='Consent'; v_target_id:=v_consent_id; v_effect_ref:='privacy.consents:'||v_consent_id;
    else
      raise exception 'unsupported handler_key: %',v_contract.handler_key;
    end if;

    perform ops.register_effect(v_cmd.event_pk,'master_apply','master_apply|'||v_cmd.command_key,v_entity_type,v_target_id,v_effect_ref);
    v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','APPLIED','duplicate_apply',false,'target_entity_type',v_entity_type,'target_entity_id',v_target_id,'master_effect_ref',v_effect_ref);
    update ops.domain_commands set apply_status='APPLIED',target_entity_type=coalesce(v_entity_type,target_entity_type),target_entity_id=coalesce(v_target_id,target_entity_id),master_effect_ref=v_effect_ref,applied_at=now(),updated_at=now() where command_pk=p_command_pk;
    update ops.domain_command_apply_audit set status='APPLIED',target_entity_type=v_entity_type,target_entity_id=v_target_id,effect_ref=v_effect_ref,result=v_result,error_class=null,error_message=null,finished_at=now(),updated_at=now() where command_pk=p_command_pk;
    return v_result;
  exception when others then
    v_result:=jsonb_build_object('command_pk',p_command_pk,'apply_status','FAILED','error',sqlerrm);
    update ops.domain_commands set apply_status='FAILED',updated_at=now() where command_pk=p_command_pk;
    update ops.domain_command_apply_audit set status='FAILED',result=v_result,error_class='APPLY_ERROR',error_message=left(sqlerrm,2000),finished_at=now(),updated_at=now() where command_pk=p_command_pk;
    return v_result;
  end;
end;
$$;

create or replace view ops.domain_command_apply_backlog_v as
select
  dc.command_pk,dc.command_key,dc.command_type,dc.target_entity_type,dc.target_entity_id,
  dc.validation_status,dc.apply_status,dc.created_at,dc.updated_at,
  mac.target_scope,mac.gate_key,mac.handler_key,
  coalesce((select setting_value from config.system_settings where setting_key=mac.gate_key),'false'::jsonb) as gate_value,
  aa.status as last_apply_status,aa.error_class,aa.error_message,aa.finished_at as last_apply_finished_at
from ops.domain_commands dc
left join ops.master_apply_contracts mac on mac.command_type=dc.command_type and mac.active=true
left join ops.domain_command_apply_audit aa on aa.command_pk=dc.command_pk
where dc.validation_status='VALID' and dc.apply_status in ('READY','BLOCKED','FAILED');

revoke all on ops.master_apply_contracts from anon, authenticated;
revoke all on ops.domain_command_apply_audit from anon, authenticated;
revoke all on ops.domain_command_apply_backlog_v from anon, authenticated;
revoke execute on function ops.open_apply_conflict(uuid,text,text,text,text,text,text) from public, anon, authenticated;
revoke execute on function ops.apply_domain_command(uuid,text) from public, anon, authenticated;
grant execute on function ops.open_apply_conflict(uuid,text,text,text,text,text,text) to service_role;
grant execute on function ops.apply_domain_command(uuid,text) to service_role;

revoke insert,update,delete on core.candidates,core.clients,core.partners,core.jobs,core.placements,core.followups from anon,authenticated;

commit;