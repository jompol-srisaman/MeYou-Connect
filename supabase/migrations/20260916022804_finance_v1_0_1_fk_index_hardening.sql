create index if not exists payment_allocations_evidence_idx on finance.payment_allocations(evidence_id);
create index if not exists partner_adjustments_evidence_idx on finance.partner_adjustments(evidence_id);
create index if not exists partner_adjustment_applications_evidence_idx on finance.partner_adjustment_applications(evidence_id);
