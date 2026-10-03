do $$
declare eb bigint; xb bigint; cb bigint; ea bigint; xa bigint; ca bigint; v jsonb;
begin
 select count(*) into eb from ops.events where event_type='candidate.lead.received' and event_id like 'DERIVED:CANDIDATE_RECONCILIATION:%';
 select count(*) into xb from ops.event_effects where effect_key like 'candidate_reconciliation_enqueued|%';
 select count(*) into cb from ops.domain_commands where command_type='candidate.upsert_proposal';
 v:=ops.enqueue_candidate_reconciliation_v1(500);
 select count(*) into ea from ops.events where event_type='candidate.lead.received' and event_id like 'DERIVED:CANDIDATE_RECONCILIATION:%';
 select count(*) into xa from ops.event_effects where effect_key like 'candidate_reconciliation_enqueued|%';
 select count(*) into ca from ops.domain_commands where command_type='candidate.upsert_proposal';
 if ea<>eb or xa<>xb or ca<>cb then raise exception 'candidate reconciliation idempotency failed events %->%, effects %->%, commands %->%',eb,ea,xb,xa,cb,ca; end if;
end $$;
