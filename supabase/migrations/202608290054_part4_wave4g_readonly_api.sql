create or replace function api.migration_cutover_readiness(p_rehearsal_id uuid default null)
returns table(
  rehearsal_id uuid,
  rehearsal_name text,
  rehearsal_status text,
  source_system text,
  baseline_source_revision text,
  final_source_revision text,
  freeze_acknowledged boolean,
  final_backup_recorded boolean,
  critical_total bigint,
  critical_pass bigint,
  critical_not_pass bigint,
  check_statuses jsonb,
  updated_at timestamptz
)
language plpgsql security definer set search_path=''
as $$
begin
  perform authz.require_capability('migration_reconcile_read');
  return query
  select v.rehearsal_id,v.rehearsal_name,v.status,v.source_system,v.baseline_source_revision,v.final_source_revision,
         v.freeze_acknowledged,v.final_backup_recorded,v.critical_total,v.critical_pass,v.critical_not_pass,v.check_statuses,v.updated_at
  from ops.cutover_readiness_v v
  where p_rehearsal_id is null or v.rehearsal_id=p_rehearsal_id
  order by v.updated_at desc;
end;$$;

create or replace function api.migration_delta_plan(p_rehearsal_id uuid)
returns table(
  batch_version integer,
  batch_status text,
  entity_key text,
  source_pk text,
  change_type text,
  review_required boolean,
  validation_issues jsonb
)
language plpgsql security definer set search_path=''
as $$
begin
  perform authz.require_capability('migration_reconcile_read');
  return query
  select b.batch_version,b.status,d.entity_key,d.source_pk,d.change_type,d.review_required,d.validation_issues
  from ops.delta_batches b join ops.delta_rows d on d.delta_batch_id=b.delta_batch_id
  where b.rehearsal_id=p_rehearsal_id
  order by b.batch_version,d.entity_key,d.source_pk nulls last;
end;$$;

create or replace function api.migration_cutover_checks(p_rehearsal_id uuid)
returns table(
  check_key text,
  category text,
  critical boolean,
  check_mode text,
  description text,
  status text,
  observed_value jsonb,
  evidence_ref text,
  evaluated_by text,
  evaluated_at timestamptz
)
language plpgsql security definer set search_path=''
as $$
begin
  perform authz.require_capability('migration_reconcile_read');
  return query
  select c.check_key,c.category,c.critical,c.check_mode,c.description,coalesce(r.status,'NOT_READY'),coalesce(r.observed_value,'{}'::jsonb),r.evidence_ref,r.evaluated_by,r.evaluated_at
  from ops.cutover_check_catalog c
  left join ops.cutover_check_results r on r.check_key=c.check_key and r.rehearsal_id=p_rehearsal_id
  where c.active=true
  order by c.critical desc,c.category,c.check_key;
end;$$;

revoke all on function api.migration_cutover_readiness(uuid) from public,anon;
revoke all on function api.migration_delta_plan(uuid) from public,anon;
revoke all on function api.migration_cutover_checks(uuid) from public,anon;
grant execute on function api.migration_cutover_readiness(uuid) to authenticated,service_role;
grant execute on function api.migration_delta_plan(uuid) to authenticated,service_role;
grant execute on function api.migration_cutover_checks(uuid) to authenticated,service_role;
