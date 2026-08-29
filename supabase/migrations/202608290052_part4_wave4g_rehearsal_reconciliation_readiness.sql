create table if not exists ops.rehearsal_reconciliation_runs(
  rehearsal_reconcile_id uuid primary key default gen_random_uuid(),
  rehearsal_id uuid not null references ops.cutover_rehearsals(rehearsal_id) on delete cascade,
  final_session_id uuid not null references ops.shadow_import_sessions(session_id),
  delta_batch_id uuid not null references ops.delta_batches(delta_batch_id),
  status text not null default 'RUNNING' check(status in ('RUNNING','PASS','REVIEW_REQUIRED')),
  match_count integer not null default 0,
  archive_match_count integer not null default 0,
  source_only_count integer not null default 0,
  target_only_count integer not null default 0,
  mismatch_count integer not null default 0,
  invalid_count integer not null default 0,
  unsupported_count integer not null default 0,
  created_by text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz
);

create table if not exists ops.rehearsal_reconciliation_results(
  rehearsal_result_id uuid primary key default gen_random_uuid(),
  rehearsal_reconcile_id uuid not null references ops.rehearsal_reconciliation_runs(rehearsal_reconcile_id) on delete cascade,
  rehearsal_id uuid not null references ops.cutover_rehearsals(rehearsal_id) on delete cascade,
  entity_key text not null,
  source_pk text,
  result_type text not null check(result_type in ('MATCH','ARCHIVE_MATCH','SOURCE_ONLY','TARGET_ONLY','FIELD_MISMATCH','INVALID_SOURCE','UNSUPPORTED')),
  detail jsonb not null default '{}'::jsonb,
  review_required boolean not null default false,
  created_at timestamptz not null default now()
);

create table if not exists ops.migration_fk_rules(
  rule_key text primary key,
  child_entity_key text not null references ops.migration_entity_map(entity_key),
  child_json_key text not null,
  parent_entity_key text not null references ops.migration_entity_map(entity_key),
  required_when_present boolean not null default true,
  active boolean not null default true,
  notes text,
  created_at timestamptz not null default now()
);

insert into ops.migration_fk_rules(rule_key,child_entity_key,child_json_key,parent_entity_key,notes)
values
('job_client','Job','client_id','Client','Job belongs to Client'),
('candidate_partner','Candidate','partner_id','Partner','Candidate attribution partner when present'),
('placement_candidate','Placement','candidate_id','Candidate','Placement Candidate parent'),
('placement_job','Placement','job_id','Job','Placement Job parent'),
('followup_placement','FollowUp','placement_id','Placement','Follow-up Placement parent'),
('revenue_client','Revenue','client_id','Client','Revenue Client when present'),
('revenue_placement','Revenue','placement_id','Placement','Revenue Placement when present'),
('expense_placement','Expense','placement_id','Placement','Expense Placement when present'),
('commission_partner','Commission','partner_id','Partner','Commission Partner'),
('commission_placement','Commission','placement_id','Placement','Commission Placement when present'),
('consent_candidate','Consent','candidate_id','Candidate','Consent Candidate'),
('consent_evidence','Consent','evidence_id','Evidence','Consent Evidence'),
('evidence_file','Evidence','file_id','File Registry','Evidence File'),
('file_raw_input','File Registry','raw_input_id','Raw Input','File provenance Raw Input when present')
on conflict(rule_key) do update set child_entity_key=excluded.child_entity_key,child_json_key=excluded.child_json_key,parent_entity_key=excluded.parent_entity_key,required_when_present=excluded.required_when_present,active=true,notes=excluded.notes;

create table if not exists ops.cutover_check_catalog(
  check_key text primary key,
  category text not null,
  critical boolean not null default true,
  check_mode text not null check(check_mode in ('AUTO','MANUAL','CONDITIONAL_MANUAL')),
  description text not null,
  source_ref text not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

insert into ops.cutover_check_catalog(check_key,category,critical,check_mode,description,source_ref)
values
('one_writable_master_guard','CUTOVER',true,'AUTO','Google Sheets/Drive remains the only operational writer during TEST rehearsal.','Migration Playbook V1 §1'),
('write_freeze_rehearsed','CUTOVER',true,'AUTO','Write-freeze checkpoint was rehearsed and explicitly acknowledged as rehearsal-only.','Migration Playbook V1 §6'),
('final_backup_recorded','BACKUP',true,'AUTO','A final source backup reference is recorded before delta capture.','Migration Playbook V1 §6'),
('delta_rehearsal_reconciled','DELTA',true,'AUTO','Latest delta batch reconciles against the scratch rehearsal target with zero critical differences.','Migration Playbook V1 §6'),
('source_validation_clean','DATA',true,'AUTO','Final source snapshot has no invalid or unsupported rows.','Migration Playbook V1 §8'),
('duplicate_ids_zero','DATA',true,'AUTO','Duplicate source business IDs equal zero.','Migration Playbook V1 §8'),
('fk_orphan_zero','DATA',true,'AUTO','Mapped foreign-key orphan count equals zero.','Migration Playbook V1 §8'),
('source_removals_reviewed','DATA',true,'CONDITIONAL_MANUAL','Rows absent from final source are archive candidates and require review rather than silent delete.','Data Governance V2 + Migration Playbook V1'),
('file_checksum_mismatch_zero','FILES',true,'MANUAL','Copied files have zero checksum mismatch after object verification.','Migration Playbook V1 §5/§8'),
('finance_totals_reconcile','FINANCE',true,'MANUAL','Financial totals reconcile between source snapshot and target rehearsal evidence.','Migration Playbook V1 §2/§8'),
('journal_batches_balanced','FINANCE',true,'AUTO','All POSTED journal batches are balanced.','Migration Playbook V1 §8'),
('consent_history_intact','PRIVACY',true,'MANUAL','Consent history and evidence links remain intact.','Migration Playbook V1 §8'),
('rls_allow_deny_tests_pass','SECURITY',true,'MANUAL','RLS allow/deny acceptance tests pass for intended roles.','Migration Playbook V1 §2/§8'),
('part3_idempotency_tests_pass','EVENTS',true,'MANUAL','Part 3 replay/idempotency acceptance tests pass after migration rehearsal.','Migration Playbook V1 §2/§8')
on conflict(check_key) do update set category=excluded.category,critical=excluded.critical,check_mode=excluded.check_mode,description=excluded.description,source_ref=excluded.source_ref,active=true;

create table if not exists ops.cutover_check_results(
  check_result_id uuid primary key default gen_random_uuid(),
  rehearsal_id uuid not null references ops.cutover_rehearsals(rehearsal_id) on delete cascade,
  check_key text not null references ops.cutover_check_catalog(check_key),
  status text not null check(status in ('PASS','FAIL','NOT_READY','NOT_APPLICABLE')),
  observed_value jsonb not null default '{}'::jsonb,
  evidence_ref text,
  evaluated_by text not null,
  evaluated_at timestamptz not null default now(),
  unique(rehearsal_id,check_key)
);

create index if not exists rehearsal_recon_runs_rehearsal_idx on ops.rehearsal_reconciliation_runs(rehearsal_id);
create index if not exists rehearsal_recon_runs_final_session_idx on ops.rehearsal_reconciliation_runs(final_session_id);
create index if not exists rehearsal_recon_runs_delta_idx on ops.rehearsal_reconciliation_runs(delta_batch_id);
create index if not exists rehearsal_recon_results_run_idx on ops.rehearsal_reconciliation_results(rehearsal_reconcile_id);
create index if not exists rehearsal_recon_results_rehearsal_idx on ops.rehearsal_reconciliation_results(rehearsal_id);
create index if not exists migration_fk_rules_child_idx on ops.migration_fk_rules(child_entity_key);
create index if not exists migration_fk_rules_parent_idx on ops.migration_fk_rules(parent_entity_key);
create index if not exists cutover_check_results_rehearsal_idx on ops.cutover_check_results(rehearsal_id);

alter table ops.rehearsal_reconciliation_runs enable row level security;
alter table ops.rehearsal_reconciliation_results enable row level security;
alter table ops.migration_fk_rules enable row level security;
alter table ops.cutover_check_catalog enable row level security;
alter table ops.cutover_check_results enable row level security;

revoke all on ops.rehearsal_reconciliation_runs,ops.rehearsal_reconciliation_results,ops.migration_fk_rules,ops.cutover_check_catalog,ops.cutover_check_results from anon,authenticated;
grant select,insert,update,delete on ops.rehearsal_reconciliation_runs,ops.rehearsal_reconciliation_results,ops.cutover_check_results to service_role;
grant select on ops.migration_fk_rules,ops.cutover_check_catalog to service_role;
