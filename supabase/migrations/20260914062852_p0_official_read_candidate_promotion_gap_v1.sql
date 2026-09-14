-- P0 Official Read Contract V1
-- Read-only technical projection used to prevent silent Candidate omissions in PWA reads.
-- Does NOT promote Raw to Master, does NOT write Google Data Hub, and does NOT change Source of Truth.

create or replace view ops.candidate_promotion_gap_v
with (security_invoker = true)
as
select
  r.raw_input_id as canonical_id,
  r.raw_input_id,
  r.received_at,
  r.updated_at,
  r.source_system,
  r.source_account_ref,
  r.thread_id,
  r.message_id,
  r.classification,
  r.processing_status,
  nullif(r.metadata #>> '{line_ingestion,parser_version}', '') as parser_version,
  nullif(r.metadata ->> 'candidate_command_pk', '') as candidate_command_pk,
  nullif(r.metadata ->> 'candidate_command_validation', '') as candidate_command_validation,
  r.entity_type,
  r.entity_id,
  nullif(r.metadata #>> '{operational_master_effect,candidate_id}', '') as operational_candidate_id,
  case
    when nullif(r.metadata #>> '{operational_master_effect,verified_at}', '') is not null
      then (r.metadata #>> '{operational_master_effect,verified_at}')::timestamptz
    else null
  end as operational_master_verified_at,
  case
    when nullif(r.metadata #>> '{operational_master_effect,candidate_id}', '') is not null
      or (r.entity_type = 'Candidate' and nullif(r.entity_id, '') is not null)
      then 'VERIFIED_MASTER_EFFECT'
    when nullif(r.metadata ->> 'candidate_command_pk', '') is not null
      then 'PROPOSAL_UNVERIFIED_MASTER_EFFECT'
    else 'RAW_CANDIDATE_SHAPE_UNPROMOTED'
  end as gap_state,
  case
    when nullif(r.metadata #>> '{operational_master_effect,candidate_id}', '') is not null
      or (r.entity_type = 'Candidate' and nullif(r.entity_id, '') is not null)
      then 'READY'
    else 'NOT_READY'
  end as readiness,
  'SUPABASE_TECHNICAL'::text as source_authority
from ops.raw_inputs r
where r.source_system = 'LINE'
  and r.content_type = 'LINE_TEXT'
  and (
    r.classification = 'CANDIDATE_LEAD'
    or (
      nullif(r.metadata #>> '{line_ingestion,candidate,phone}', '') is not null
      and nullif(r.metadata #>> '{line_ingestion,candidate,full_name}', '') is not null
    )
  );

comment on view ops.candidate_promotion_gap_v is
'P0 Official Read Contract guard. Read-only technical projection that detects candidate-shaped LINE Raw records lacking verified Google Data Hub operational Master Effect linkage. It does not promote or write business Master data.';

revoke all on ops.candidate_promotion_gap_v from public, anon, authenticated;
grant select on ops.candidate_promotion_gap_v to service_role;
