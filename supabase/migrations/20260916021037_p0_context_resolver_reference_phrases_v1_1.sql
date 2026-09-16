create or replace view ops.line_context_resolution_v as
with src as (
  select
    r.*,
    nullif(r.metadata #>> '{provider_payload,message,quotedMessageId}', '') as quoted_message_id,
    case
      when r.content_type = 'LINE_TEXT'
       and btrim(coalesce(r.raw_summary,'')) ~* '^(ใช่(\s*(ค่ะ|ครับ))?|คนนี้|อันนี้(นะ)?|รูปนี้|เอาอันนี้|ไม่เอา(คนนี้|อันนี้)|ลบ(อันนี้|คนนี้)?|แก้|แก้ไข|เปลี่ยน)'
      then true else false
    end as is_context_message
  from ops.raw_inputs r
  where r.source_system = 'LINE'
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
   and q.source_system = 'LINE'
   and q.source_account_ref = c.source_account_ref
   and q.thread_id = c.thread_id
   and q.message_id = c.quoted_message_id
  left join lateral (
    select p0.*
    from src p0
    where c.quoted_message_id is null
      and p0.raw_input_id <> c.raw_input_id
      and p0.source_account_ref = c.source_account_ref
      and p0.thread_id = c.thread_id
      and p0.sender_ref = c.sender_ref
      and p0.received_at < c.received_at
      and p0.received_at >= c.received_at - interval '2 minutes'
      and not p0.is_context_message
      and p0.content_type not in ('LINE_STICKER')
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

comment on view ops.line_context_resolution_v is 'Deterministic LINE context resolver v1.1. Explicit quoted reply stays scoped to source_account+thread. Recent fallback is scoped to source_account+thread+sender within 120s, excludes stickers, and ambiguous context fails closed to DQ.';
