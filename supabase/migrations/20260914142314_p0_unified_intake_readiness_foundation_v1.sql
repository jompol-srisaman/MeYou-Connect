-- P0 Data Completeness + Unified Intake Readiness V1
-- Extends existing canonical Raw/Event architecture only.
-- No business Master writes, no Source-of-Truth cutover, no paid AI activation.

-- 1) Candidate reconciliation workbench: conservative technical classification.
-- Master-dependent categories remain NEEDS_DQ until live Google Data Hub lookup proves the state.
create or replace view ops.candidate_reconciliation_workbench_v
with (security_invoker = true)
as
with base as (
  select
    v.raw_input_id,
    v.received_at,
    v.updated_at,
    v.gap_state,
    v.readiness,
    r.source_account_ref,
    r.thread_id,
    r.message_id,
    r.sender_ref,
    r.raw_summary,
    nullif(r.metadata #>> '{line_ingestion,candidate,full_name}', '') as candidate_name,
    nullif(r.metadata #>> '{line_ingestion,candidate,phone}', '') as candidate_phone,
    nullif(r.metadata #>> '{line_ingestion,candidate,date_of_birth}', '') as candidate_dob,
    nullif(r.metadata #>> '{line_ingestion,candidate,education}', '') as candidate_education,
    nullif(r.metadata #>> '{line_ingestion,candidate,partner_id}', '') as parsed_partner_id,
    nullif(r.metadata #>> '{line_ingestion,job_id}', '') as parsed_job_id,
    nullif(r.metadata #>> '{operational_master_effect,candidate_id}', '') as operational_candidate_id,
    lower(regexp_replace(regexp_replace(coalesce(nullif(r.metadata #>> '{line_ingestion,candidate,full_name}', ''), ''),
      '^(ชื่อ[- ]?นามสกุล|ชื่อนามสกุล|ชื่อ)\s*[:：]?\s*', '', 'i'), '\s+', '', 'g')) as normalized_name,
    (
      (coalesce(r.raw_summary,'') ~* 'วันเดือนปีเกิด|วันเกิด|เกิด\s*[:：]')::int +
      (coalesce(r.raw_summary,'') ~* 'วุฒิ|วุติ|การศึกษา|ปวช|ปวส')::int +
      (coalesce(r.raw_summary,'') ~* 'น้ำหนัก|น\.น|นน\.')::int +
      (coalesce(r.raw_summary,'') ~* 'ส่วนสูง|สูง\s*[:：]?\s*[0-9]|ส\.ส')::int +
      (coalesce(r.raw_summary,'') ~* 'อายุ\s*[:：]?\s*[0-9]')::int +
      (coalesce(r.raw_summary,'') ~* 'เบอร์โทร|โทร\s*[:：]?\s*0[0-9]{9}')::int +
      (coalesce(r.raw_summary,'') ~* 'โรงงาน|โรงาน')::int +
      (coalesce(r.raw_summary,'') ~* 'รอยสัก|ลอยสัก')::int
    ) as structured_signal_count,
    case
      when btrim(coalesce(r.raw_summary,'')) ~* '^(ใช่(ค่ะ|ครับ)?|คนนี้|อันนี้(นะ)?|รูปนี้|เอาอันนี้|ลบ|แก้|แก้ไข|เปลี่ยน)' then true
      else false
    end as context_like,
    case
      when coalesce(r.raw_summary,'') ~* 'ลูกทีม|เบอร์ติดต่อ|ติดต่อ.*(แพร|เจน|เจด้า|คิม)|ผู้แนะนำ\s*[:：]?\s*[ก-๙A-Za-z]+$' then true
      else false
    end as contact_or_internal_like
  from ops.candidate_promotion_gap_v v
  join ops.raw_inputs r on r.raw_input_id = v.raw_input_id
  where v.readiness = 'NOT_READY'
), fingerprinted as (
  select
    b.*,
    concat_ws('|', coalesce(candidate_phone,''), normalized_name, coalesce(candidate_dob,'')) as candidate_fingerprint
  from base b
), ranked as (
  select
    f.*,
    row_number() over (
      partition by candidate_fingerprint
      order by received_at, raw_input_id
    ) as fingerprint_row_no,
    count(*) over (partition by candidate_fingerprint) as fingerprint_raw_count
  from fingerprinted f
  where candidate_fingerprint <> '||'
)
select
  raw_input_id as canonical_id,
  raw_input_id,
  received_at,
  updated_at,
  source_account_ref,
  thread_id,
  message_id,
  sender_ref,
  raw_summary,
  candidate_name,
  candidate_phone,
  candidate_dob,
  candidate_education,
  parsed_partner_id,
  parsed_job_id,
  operational_candidate_id,
  candidate_fingerprint,
  fingerprint_raw_count,
  structured_signal_count,
  case
    when contact_or_internal_like and structured_signal_count <= 1 then 'INVALID/NOISE'
    when context_like and structured_signal_count <= 1 then 'CONTEXT_ONLY'
    when structured_signal_count <= 1 and char_length(btrim(coalesce(raw_summary,''))) < 120 then 'CONTEXT_ONLY'
    when structured_signal_count >= 2 and fingerprint_row_no > 1 then 'DUPLICATE'
    else 'NEEDS_DQ'
  end as reconciliation_category,
  case
    when structured_signal_count >= 2 and fingerprint_row_no = 1 then 'LIVE_DATAHUB_MASTER_LOOKUP_REQUIRED'
    when structured_signal_count >= 2 and fingerprint_row_no > 1 then 'RAW_DUPLICATE_OF_EARLIER_FINGERPRINT'
    when contact_or_internal_like and structured_signal_count <= 1 then 'NON_CANDIDATE_CONTACT_SHAPE'
    when context_like or structured_signal_count <= 1 then 'CONTEXT_NOT_STANDALONE_CANDIDATE'
    else 'REVIEW_REQUIRED'
  end as reconciliation_reason,
  'GOOGLE_SHEETS_DRIVE'::text as master_authority,
  'NOT_READY'::text as master_lookup_readiness
from ranked;

comment on view ops.candidate_reconciliation_workbench_v is
'P0 conservative Candidate reconciliation workbench. DUPLICATE/CONTEXT/NOISE are technical classifications only. ALREADY_IN_MASTER_LINK_MISSING and NEW_CANDIDATE_NEEDS_PROMOTION must not be asserted until live Google Data Hub Candidate Master lookup proves them.';

revoke all on ops.candidate_reconciliation_workbench_v from public, anon, authenticated;
grant select on ops.candidate_reconciliation_workbench_v to service_role;

-- 2) Deterministic LINE context resolver read model.
-- Strongest anchor: explicit LINE quotedMessageId in same source account + thread.
-- Conservative fallback: nearest non-context Raw from same account + thread + sender within 120 seconds.
create or replace view ops.line_context_resolution_v
with (security_invoker = true)
as
with src as (
  select
    r.*,
    nullif(r.metadata #>> '{provider_payload,message,quotedMessageId}', '') as quoted_message_id,
    case
      when r.content_type='LINE_TEXT' and btrim(coalesce(r.raw_summary,'')) ~* '^(ใช่(ค่ะ|ครับ)?|คนนี้|อันนี้(นะ)?|รูปนี้|เอาอันนี้|ลบ|แก้|แก้ไข|เปลี่ยน)' then true
      else false
    end as is_context_message
  from ops.raw_inputs r
  where r.source_system='LINE'
), resolved as (
  select
    c.raw_input_id,
    c.received_at,
    c.updated_at,
    c.source_account_ref,
    c.thread_id,
    c.message_id,
    c.sender_ref,
    c.raw_summary,
    c.content_type,
    c.quoted_message_id,
    q.raw_input_id as quoted_anchor_raw_input_id,
    q.message_id as quoted_anchor_message_id,
    q.sender_ref as quoted_anchor_sender_ref,
    q.content_type as quoted_anchor_content_type,
    p.raw_input_id as recent_anchor_raw_input_id,
    p.message_id as recent_anchor_message_id,
    p.sender_ref as recent_anchor_sender_ref,
    p.content_type as recent_anchor_content_type,
    p.received_at as recent_anchor_received_at
  from src c
  left join ops.raw_inputs q
    on c.quoted_message_id is not null
   and q.source_system='LINE'
   and q.source_account_ref=c.source_account_ref
   and q.thread_id=c.thread_id
   and q.message_id=c.quoted_message_id
  left join lateral (
    select p0.*
    from src p0
    where c.quoted_message_id is null
      and p0.raw_input_id <> c.raw_input_id
      and p0.source_account_ref=c.source_account_ref
      and p0.thread_id=c.thread_id
      and p0.sender_ref=c.sender_ref
      and p0.received_at < c.received_at
      and p0.received_at >= c.received_at - interval '120 seconds'
      and not p0.is_context_message
    order by p0.received_at desc, p0.raw_input_id desc
    limit 1
  ) p on true
  where c.is_context_message
)
select
  raw_input_id as canonical_id,
  raw_input_id,
  received_at,
  updated_at,
  source_account_ref,
  thread_id,
  message_id,
  sender_ref,
  raw_summary,
  content_type,
  quoted_message_id,
  coalesce(quoted_anchor_raw_input_id,recent_anchor_raw_input_id) as anchor_raw_input_id,
  coalesce(quoted_anchor_message_id,recent_anchor_message_id) as anchor_message_id,
  coalesce(quoted_anchor_sender_ref,recent_anchor_sender_ref) as anchor_sender_ref,
  coalesce(quoted_anchor_content_type,recent_anchor_content_type) as anchor_content_type,
  case
    when quoted_anchor_raw_input_id is not null then 'RESOLVED_REPLY'
    when quoted_message_id is not null then 'NEEDS_DQ'
    when recent_anchor_raw_input_id is not null then 'RESOLVED_RECENT_SENDER_CONTEXT'
    else 'NEEDS_DQ'
  end as resolution_status,
  case
    when quoted_anchor_raw_input_id is not null then 100
    when recent_anchor_raw_input_id is not null then 80
    else 0
  end as confidence,
  case
    when quoted_anchor_raw_input_id is not null then 'EXPLICIT_REPLY_SAME_ACCOUNT_THREAD'
    when quoted_message_id is not null then 'QUOTED_TARGET_NOT_FOUND_IN_SAME_ACCOUNT_THREAD'
    when recent_anchor_raw_input_id is not null then 'RECENT_SAME_ACCOUNT_THREAD_SENDER_WITHIN_120S'
    else 'AMBIGUOUS_OR_NO_SAFE_CONTEXT'
  end as reason_code,
  case when quoted_anchor_raw_input_id is null and recent_anchor_raw_input_id is null then true else false end as dq_required
from resolved;

comment on view ops.line_context_resolution_v is
'P0 deterministic context resolver. It never mutates Master. Ambiguous/deictic messages without a safe same-thread anchor are surfaced as NEEDS_DQ.';

revoke all on ops.line_context_resolution_v from public, anon, authenticated;
grant select on ops.line_context_resolution_v to service_role;

-- 3) Worker readiness: registry presence is not runtime readiness.
create or replace view ops.unified_worker_readiness_v
with (security_invoker = true)
as
with latest_hb as (
  select distinct on (worker_key)
    worker_key, worker_instance, environment, status as heartbeat_status, version, last_seen_at
  from ops.worker_heartbeats
  order by worker_key, last_seen_at desc
), runs as (
  select
    worker_key,
    count(*) filter (where status='SUCCEEDED') as successful_runs,
    count(*) filter (where status in ('FAILED','DEAD_LETTER')) as failed_runs,
    max(coalesce(finished_at,started_at)) as last_run_at
  from ops.worker_runs
  group by worker_key
), candidate_gap as (
  select count(*) filter (where readiness='NOT_READY')::bigint as gap_count
  from ops.candidate_promotion_gap_v
)
select
  wr.worker_key,
  wr.domain,
  wr.enabled,
  hb.worker_instance,
  hb.environment,
  hb.version,
  hb.heartbeat_status,
  hb.last_seen_at,
  case when hb.last_seen_at is null then null else extract(epoch from (now()-hb.last_seen_at))::bigint end as heartbeat_age_seconds,
  coalesce(r.successful_runs,0)::bigint as successful_runs,
  coalesce(r.failed_runs,0)::bigint as failed_runs,
  r.last_run_at,
  coalesce(wb.ready_count,0) as ready_count,
  coalesce(wb.retry_wait_count,0) as retry_wait_count,
  coalesce(wb.approval_wait_count,0) as approval_wait_count,
  coalesce(wb.dead_letter_count,0) as dead_letter_count,
  case
    when wr.enabled=false then 'BLOCKED'
    when hb.last_seen_at is not null and (hb.heartbeat_status in ('FAILED','UNHEALTHY','ERROR') or now()-hb.last_seen_at > interval '15 minutes') then 'BLOCKED'
    when hb.last_seen_at is null and coalesce(r.successful_runs,0)=0 then 'NOT_STARTED'
    when wr.worker_key='candidate_intake' and hb.last_seen_at is not null and now()-hb.last_seen_at <= interval '15 minutes' and candidate_gap.gap_count>0 then 'PARTIAL'
    when hb.last_seen_at is not null and now()-hb.last_seen_at <= interval '15 minutes' and coalesce(r.successful_runs,0)>0 and coalesce(wb.dead_letter_count,0)=0 then 'READY'
    when hb.last_seen_at is not null and now()-hb.last_seen_at <= interval '15 minutes' then 'PARTIAL'
    else 'PARTIAL'
  end as readiness,
  case
    when wr.worker_key='candidate_intake' and candidate_gap.gap_count>0 then 'HEARTBEAT_HEALTHY_BUT_CANDIDATE_COMPLETENESS_GAP'
    when hb.last_seen_at is null and coalesce(r.successful_runs,0)=0 then 'REGISTRY_ONLY_NO_HEARTBEAT_OR_RUN_EVIDENCE'
    when hb.last_seen_at is not null and now()-hb.last_seen_at > interval '15 minutes' then 'STALE_HEARTBEAT'
    when coalesce(wb.dead_letter_count,0)>0 then 'DEAD_LETTER_PRESENT'
    else 'RUNTIME_EVIDENCE_EVALUATED'
  end as reason_code
from ops.worker_registry wr
left join latest_hb hb using(worker_key)
left join runs r using(worker_key)
left join ops.worker_backlog_v wb using(worker_key)
cross join candidate_gap;

comment on view ops.unified_worker_readiness_v is
'P0 runtime readiness matrix. Registry/enabled alone never means RUNNING or READY; heartbeat/run/backlog evidence is required.';

revoke all on ops.unified_worker_readiness_v from public, anon, authenticated;
grant select on ops.unified_worker_readiness_v to service_role;

-- 4) File Intelligence Router: deterministic MIME routing only, no semantic AI call.
create or replace function ops.file_intelligence_route_v1(p_mime_type text, p_filename text default null)
returns jsonb
language sql
immutable
security invoker
set search_path=''
as $$
  select jsonb_build_object(
    'contract_version','v1',
    'mime_type',coalesce(p_mime_type,''),
    'filename',p_filename,
    'route_key',case
      when coalesce(p_mime_type,'') like 'image/%' then 'IMAGE'
      when p_mime_type='application/pdf' then 'PDF'
      when p_mime_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document' or lower(coalesce(p_filename,'')) like '%.docx' then 'DOCX'
      when p_mime_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' or lower(coalesce(p_filename,'')) like '%.xlsx' then 'XLSX'
      when p_mime_type in ('text/csv','application/csv') or lower(coalesce(p_filename,'')) like '%.csv' then 'CSV'
      when p_mime_type='text/plain' or lower(coalesce(p_filename,'')) like '%.txt' then 'TXT'
      when coalesce(p_mime_type,'') like 'audio/%' then 'AUDIO'
      when coalesce(p_mime_type,'') like 'video/%' then 'VIDEO'
      else 'UNSUPPORTED'
    end,
    'semantic_ai_status','SEMANTIC_AI_NOT_READY',
    'paid_ai_activated',false
  );
$$;

revoke all on function ops.file_intelligence_route_v1(text,text) from public, anon, authenticated;
grant execute on function ops.file_intelligence_route_v1(text,text) to service_role;

create or replace view ops.file_intelligence_compatibility_v
with (security_invoker = true)
as
with required(file_type, mime_probe, filename_probe) as (
  values
    ('image','image/jpeg','sample.jpg'),
    ('PDF','application/pdf','sample.pdf'),
    ('DOCX','application/vnd.openxmlformats-officedocument.wordprocessingml.document','sample.docx'),
    ('XLSX','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet','sample.xlsx'),
    ('CSV','text/csv','sample.csv'),
    ('TXT','text/plain','sample.txt'),
    ('audio','audio/mpeg','sample.mp3'),
    ('video','video/mp4','sample.mp4')
), evidence as (
  select
    case
      when content_type like 'image/%' then 'image'
      when content_type='application/pdf' then 'PDF'
      when content_type='application/vnd.openxmlformats-officedocument.wordprocessingml.document' then 'DOCX'
      when content_type='application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' then 'XLSX'
      when content_type in ('text/csv','application/csv') then 'CSV'
      when content_type='text/plain' then 'TXT'
      when content_type like 'audio/%' then 'audio'
      when content_type like 'video/%' then 'video'
      else null
    end as file_type,
    count(*) as intake_count,
    count(*) filter (where mirror_status='MIRRORED') as mirrored_count,
    max(updated_at) as latest_evidence_at
  from ops.file_intake
  where source_system='LINE'
  group by 1
)
select
  r.file_type,
  r.mime_probe,
  (ops.file_intelligence_route_v1(r.mime_probe,r.filename_probe)->>'route_key') as route_key,
  case when coalesce(e.intake_count,0)>0 then 'CAPTURE_SUPPORTED' else 'UNSUPPORTED' end as capture_status,
  case when coalesce(e.mirrored_count,0)>0 then 'STORAGE_SUPPORTED' else 'UNSUPPORTED' end as storage_status,
  'UNSUPPORTED'::text as parse_status,
  'SEMANTIC_AI_NOT_READY'::text as semantic_ai_status,
  coalesce(e.intake_count,0)::bigint as live_intake_evidence_count,
  coalesce(e.mirrored_count,0)::bigint as live_mirrored_evidence_count,
  e.latest_evidence_at,
  case when coalesce(e.intake_count,0)>0 then 'LIVE_CAPTURE_STORAGE_OBSERVED_PARSE_NOT_PROVEN' else 'ROUTER_CONTRACT_ONLY_NO_LIVE_E2E_EVIDENCE' end as test_state,
  false as production_ready
from required r
left join evidence e using(file_type);

comment on view ops.file_intelligence_compatibility_v is
'P0 live-evidence compatibility matrix. Unsupported here means not proven in current LINE TEST evidence, not necessarily impossible. No type is production-ready merely because routing exists.';

revoke all on ops.file_intelligence_compatibility_v from public, anon, authenticated;
grant select on ops.file_intelligence_compatibility_v to service_role;

-- 5) Consent readiness guard. Google Data Hub tab 14_Consent_PDPA remains authority.
create or replace view ops.consent_readiness_v
with (security_invoker = true)
as
select
  'CONSENT_PDPA'::text as canonical_id,
  'GOOGLE_SHEETS_DRIVE'::text as source_authority,
  'MEYOU_CONNECT_MVP_DATA_HUB_V1/14_Consent_PDPA'::text as source_ref,
  count(c.*)::bigint as supabase_registry_rows,
  false as datahub_readback_verified,
  false as auto_submit_allowed,
  'NOT_READY'::text as readiness,
  'DATA_HUB_CONSENT_READBACK_REQUIRED'::text as reason_code,
  max(c.created_at) as supabase_latest_consent_at
from privacy.consents c;

comment on view ops.consent_readiness_v is
'P0 consent guard. Empty Supabase registry must never be interpreted as permission. Auto Submit remains FALSE until live Data Hub 14_Consent_PDPA evidence is read and verified through the approved adapter.';

revoke all on ops.consent_readiness_v from public, anon, authenticated;
grant select on ops.consent_readiness_v to service_role;

-- 6) B2B semantic response mapping onto existing Event Kernel.
-- Contract-only: does not emit events or apply Master effects by itself.
create or replace view ops.b2b_response_event_map_v
with (security_invoker = true)
as
select * from (values
  ('ACCEPTED','b2b.response.accepted'),
  ('REJECTED','b2b.response.rejected'),
  ('NEED_INFO','b2b.response.need_info'),
  ('APPOINTMENT','b2b.response.appointment'),
  ('SLOT_CLOSED','b2b.response.slot_closed'),
  ('REQUIREMENT_CHANGED','b2b.response.requirement_changed'),
  ('WAITING','b2b.response.waiting')
) as m(outcome,event_type);

comment on view ops.b2b_response_event_map_v is
'P0 semantic map for the Founder-provided canonical B2B response taxonomy. Event emission must use existing ops.events/register_event and existing validation/permission/effect gates; this view creates no second architecture.';

revoke all on ops.b2b_response_event_map_v from public, anon, authenticated;
grant select on ops.b2b_response_event_map_v to service_role;

-- 7) Verify only the LINE identity that already has deterministic canonical Partner evidence
-- in the currently applied parser and repeated raw attribution. Leave all others UNVERIFIED.
update ops.channel_identities ci
set
  linked_entity_type='Partner',
  linked_entity_id='MYC-P-0001',
  link_status='VERIFIED',
  verified_at=coalesce(ci.verified_at,now()),
  verified_by='P0_UNIFIED_INTAKE_EVIDENCE_V1',
  metadata=coalesce(ci.metadata,'{}'::jsonb) || jsonb_build_object(
    'identity_verification_evidence',jsonb_build_object(
      'basis','EXISTING_APPLIED_PARSER_RULE_AND_CONSISTENT_RAW_ATTRIBUTION',
      'partner_id','MYC-P-0001',
      'consistent_raw_count',(select count(*) from ops.raw_inputs r where r.source_system='LINE' and r.source_account_ref=ci.source_account_ref and r.sender_ref=ci.identity_ref and coalesce(nullif(r.metadata #>> '{line_ingestion,partner_id}',''),nullif(r.metadata #>> '{line_ingestion,candidate,partner_id}',''))='MYC-P-0001'),
      'verified_at',now()
    )
  ),
  updated_at=now()
where ci.source_system='LINE'
  and ci.source_account_ref='LINE_OA:MYC_DATA_BOT'
  and ci.identity_ref='U1738e96a0eff5456a4656a2435712447'
  and ci.link_status='UNVERIFIED';
