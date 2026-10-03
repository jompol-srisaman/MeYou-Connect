create or replace view ops.identity_resolution_readiness_v as
select
  source_system,
  source_account_ref,
  identity_ref,
  display_name,
  linked_entity_type,
  linked_entity_id,
  case
    when link_status='VERIFIED'
      and linked_entity_type is not null
      and linked_entity_id is not null
      and coalesce(metadata ? 'identity_verification_evidence',false)
      and verified_at is not null
      and verified_by is not null
      then 'VERIFIED'
    when (linked_entity_type is not null or linked_entity_id is not null or coalesce(metadata ? 'identity_verification_evidence',false))
      then 'PARTIAL'
    else 'UNVERIFIED'
  end as resolution_status,
  case
    when link_status='VERIFIED'
      and linked_entity_type is not null
      and linked_entity_id is not null
      and coalesce(metadata ? 'identity_verification_evidence',false)
      and verified_at is not null
      and verified_by is not null
      then 'EVIDENCE_BACKED_ENTITY_LINK'
    when (linked_entity_type is not null or linked_entity_id is not null or coalesce(metadata ? 'identity_verification_evidence',false))
      then 'INCOMPLETE_LINK_OR_EVIDENCE'
    else 'NO_ENTITY_LINK_EVIDENCE'
  end as reason_code,
  metadata->'identity_verification_evidence' as evidence,
  verified_at,
  verified_by,
  last_seen_at
from ops.channel_identities;

comment on view ops.identity_resolution_readiness_v is 'Evidence-gated identity readiness. Display name alone never yields VERIFIED. PARTIAL is used only when some link/evidence exists but the complete evidence-backed link is not satisfied.';
