begin;

-- Part 4B: PII split + Consent history + provider-neutral File/Evidence abstraction.

create schema if not exists private;
create schema if not exists privacy;
create schema if not exists docs;

insert into config.system_settings(setting_key,setting_value,description,source_ref,updated_at)
values
 ('postgres_private_write_enabled','false'::jsonb,'PII writes remain disabled until controlled apply-layer acceptance passes.','Part4B',now()),
 ('postgres_docs_write_enabled','false'::jsonb,'PostgreSQL File/Evidence writes remain disabled until controlled apply-layer acceptance passes.','Part4B',now()),
 ('postgres_consent_write_enabled','false'::jsonb,'PostgreSQL consent writes remain disabled until controlled apply-layer acceptance passes.','Part4B',now()),
 ('supabase_storage_external_access_enabled','false'::jsonb,'Storage buckets remain private and no external direct access is enabled in TEST.','Part4B',now())
on conflict (setting_key) do update set setting_value=excluded.setting_value,description=excluded.description,source_ref=excluded.source_ref,updated_at=excluded.updated_at;

create or replace function config.setting_is_true(p_setting_key text)
returns boolean language sql stable security definer set search_path=''
as $$ select coalesce((select setting_value='true'::jsonb from config.system_settings where setting_key=p_setting_key),false); $$;

create table if not exists private.candidate_contacts (
 candidate_id text primary key references core.candidates(candidate_id) on delete restrict,
 full_name text, phone text, line_id text, email text, date_of_birth date, national_id text,
 current_address text, emergency_contact_name text, emergency_contact_phone text, notes text,
 source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists private.client_contacts (
 client_id text primary key references core.clients(client_id) on delete restrict,
 contact_name text, contact_role text, phone text, line_id text, email text,
 billing_contact_name text, billing_phone text, billing_email text, notes text,
 source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create table if not exists private.partner_contacts (
 partner_id text primary key references core.partners(partner_id) on delete restrict,
 contact_name text, contact_role text, phone text, line_id text, email text,
 payout_contact_name text, payout_phone text, notes text,
 source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

create index if not exists candidate_contacts_raw_idx on private.candidate_contacts(source_raw_input_id);
create index if not exists client_contacts_raw_idx on private.client_contacts(source_raw_input_id);
create index if not exists partner_contacts_raw_idx on private.partner_contacts(source_raw_input_id);

create table if not exists docs.storage_profiles (
 storage_profile_key text primary key,
 desired_visibility text not null check (desired_visibility in ('PRIVATE','PUBLIC')),
 content_scope text not null, default_provider text not null, object_key_pattern text not null,
 delete_policy text not null, provision_in_supabase boolean not null default false,
 current_public boolean not null default false,
 activation_state text not null default 'LOCKED' check (activation_state in ('LOCKED','PRIVATE_ACTIVE','PUBLIC_ACTIVE','EXTERNAL_TARGET')),
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

insert into docs.storage_profiles(storage_profile_key,desired_visibility,content_scope,default_provider,object_key_pattern,delete_policy,provision_in_supabase,current_public,activation_state,notes)
values
 ('raw-inbox-private','PRIVATE','Raw mirrored uploads','SUPABASE_STORAGE','raw/<raw_id>/<file_id>/<sha>_<name>','Retention review',true,false,'PRIVATE_ACTIVE','May contain unclassified sensitive data'),
 ('evidence-private','PRIVATE','Slips/contracts/consent/start confirmations','SUPABASE_STORAGE','<domain>/<business_id>/<file_id>/<sha>_<name>','Archive-first / controlled',true,false,'PRIVATE_ACTIVE','Never overwrite evidence object'),
 ('business-private','PRIVATE','Rate/deal/internal reference','SUPABASE_STORAGE','business/<entity>/<file_id>/<sha>_<name>','Controlled',true,false,'PRIVATE_ACTIVE','Internal business reference'),
 ('content-public','PUBLIC','Approved public content only','SUPABASE_STORAGE_OR_R2','content/<content_id>/<file_id>/<name>','Versioned by new file ID',true,false,'LOCKED','Desired PUBLIC, but forced private until Production/public-access approval'),
 ('backup-private','PRIVATE','Exports/migration packages','R2_OR_SEPARATE_BACKUP','backup/<date>/<package>','Retention plan',false,false,'EXTERNAL_TARGET','Independent backup target; not provisioned as Supabase bucket here')
on conflict (storage_profile_key) do update set desired_visibility=excluded.desired_visibility,content_scope=excluded.content_scope,default_provider=excluded.default_provider,object_key_pattern=excluded.object_key_pattern,delete_policy=excluded.delete_policy,provision_in_supabase=excluded.provision_in_supabase,current_public=false,activation_state=excluded.activation_state,notes=excluded.notes,updated_at=now();

insert into storage.buckets(id,name,public)
values ('raw-inbox-private','raw-inbox-private',false),('evidence-private','evidence-private',false),('business-private','business-private',false),('content-public','content-public',false)
on conflict (id) do update set public=false;

create table if not exists docs.files (
 file_id text primary key check (file_id ~ '^WC-FILE-[0-9]{6}$'),
 raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
 provider text not null check (provider in ('GOOGLE_DRIVE','SUPABASE_STORAGE','CLOUDFLARE_R2','OTHER')),
 storage_profile_key text references docs.storage_profiles(storage_profile_key) on delete restrict,
 bucket text, object_key text, provider_file_ref text, legacy_drive_file_id text, source_url text,
 original_filename text, stored_filename text, mime_type text,
 size_bytes bigint check (size_bytes is null or size_bytes>=0),
 checksum_sha256 text check (checksum_sha256 is null or checksum_sha256 ~ '^[0-9A-Fa-f]{64}$'),
 visibility text not null default 'PRIVATE' check (visibility in ('PRIVATE','PUBLIC')),
 sensitivity text not null default 'INTERNAL' check (sensitivity in ('PUBLIC','INTERNAL','CONFIDENTIAL','PII','FINANCE','LEGAL')),
 storage_status text not null default 'SOURCE_ONLY' check (storage_status in ('SOURCE_ONLY','MIRRORED','SOURCE_NOT_MIRRORED','STORED','ARCHIVED','FAILED')),
 search_tags text[] not null default '{}', description text, created_by text not null default 'system',
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check ((provider in ('SUPABASE_STORAGE','CLOUDFLARE_R2') and bucket is not null and object_key is not null) or provider in ('GOOGLE_DRIVE','OTHER')),
 check (storage_status<>'SOURCE_NOT_MIRRORED' or source_url is not null or provider_file_ref is not null or legacy_drive_file_id is not null)
);
create unique index if not exists files_provider_object_uq on docs.files(provider,bucket,object_key) where bucket is not null and object_key is not null;
create index if not exists files_raw_input_idx on docs.files(raw_input_id);
create index if not exists files_checksum_idx on docs.files(checksum_sha256) where checksum_sha256 is not null;
create index if not exists files_legacy_drive_idx on docs.files(legacy_drive_file_id) where legacy_drive_file_id is not null;

create table if not exists docs.evidence (
 evidence_id text primary key check (evidence_id ~ '^WC-EV-[0-9]{6}$'),
 file_id text not null references docs.files(file_id) on delete restrict,
 evidence_type text not null,
 evidence_class text not null default 'BUSINESS_EVIDENCE' check (evidence_class in ('TRANSACTION_EVIDENCE','BUSINESS_EVIDENCE','OPERATIONAL_EVIDENCE','CONSENT_EVIDENCE','REFERENCE')),
 evidence_date timestamptz,
 verification_status text not null default 'UNVERIFIED' check (verification_status in ('UNVERIFIED','VERIFIED','REJECTED','CONFLICT')),
 verified_by text, verified_at timestamptz, source_authority text, notes text,
 created_by text not null default 'system', created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 check ((verification_status='VERIFIED' and verified_by is not null and verified_at is not null) or verification_status<>'VERIFIED')
);
create index if not exists evidence_file_idx on docs.evidence(file_id);
create index if not exists evidence_type_idx on docs.evidence(evidence_type,verification_status);

create table if not exists docs.evidence_links (
 evidence_id text not null references docs.evidence(evidence_id) on delete restrict,
 entity_type text not null, entity_id text not null, link_role text not null default 'SUPPORTS',
 created_by text not null default 'system', created_at timestamptz not null default now(),
 primary key(evidence_id,entity_type,entity_id,link_role), check (btrim(entity_type)<>'' and btrim(entity_id)<>'' and btrim(link_role)<>'')
);
create index if not exists evidence_links_entity_idx on docs.evidence_links(entity_type,entity_id);

create or replace function docs.prevent_file_object_identity_change() returns trigger language plpgsql security definer set search_path=''
as $$ begin if old.storage_status in ('MIRRORED','STORED','ARCHIVED') and (new.provider is distinct from old.provider or new.bucket is distinct from old.bucket or new.object_key is distinct from old.object_key or new.checksum_sha256 is distinct from old.checksum_sha256) then raise exception 'stored evidence object identity is immutable; create a new File Registry ID/version instead'; end if; new.updated_at:=now(); return new; end; $$;
drop trigger if exists trg_files_object_identity_immutable on docs.files;
create trigger trg_files_object_identity_immutable before update on docs.files for each row execute function docs.prevent_file_object_identity_change();

create table if not exists privacy.consents (
 consent_id text primary key check (consent_id ~ '^WC-CN-[0-9]{6}$'),
 candidate_id text not null references core.candidates(candidate_id) on delete restrict,
 purpose_code text not null, decision text not null check (decision in ('GRANTED','WITHDRAWN','DECLINED')),
 effective_at timestamptz not null, evidence_id text not null references docs.evidence(evidence_id) on delete restrict,
 source_raw_input_id text references ops.raw_inputs(raw_input_id) on delete restrict,
 supersedes_consent_id text references privacy.consents(consent_id) on delete restrict,
 notes text, created_by text not null default 'system', created_at timestamptz not null default now(), check (btrim(purpose_code)<>'')
);
create index if not exists consents_candidate_purpose_idx on privacy.consents(candidate_id,purpose_code,effective_at desc,created_at desc);
create index if not exists consents_evidence_idx on privacy.consents(evidence_id);
create index if not exists consents_raw_idx on privacy.consents(source_raw_input_id);

create or replace function privacy.validate_consent_history() returns trigger language plpgsql security definer set search_path=''
as $$ declare v_prev privacy.consents; begin if new.decision='WITHDRAWN' and new.supersedes_consent_id is null then raise exception 'withdrawal must supersede an earlier consent record'; end if; if new.supersedes_consent_id is not null then select * into v_prev from privacy.consents where consent_id=new.supersedes_consent_id; if not found then raise exception 'superseded consent not found'; end if; if v_prev.candidate_id<>new.candidate_id or v_prev.purpose_code<>new.purpose_code then raise exception 'consent history must stay within the same candidate and purpose'; end if; if new.effective_at<v_prev.effective_at then raise exception 'new consent history event cannot predate the record it supersedes'; end if; end if; return new; end; $$;
drop trigger if exists trg_validate_consent_history on privacy.consents;
create trigger trg_validate_consent_history before insert on privacy.consents for each row execute function privacy.validate_consent_history();

create or replace view privacy.current_consents_v with (security_invoker=true) as
select consent_id,candidate_id,purpose_code,decision,effective_at,evidence_id,source_raw_input_id,created_at
from (select c.*,row_number() over(partition by candidate_id,purpose_code order by effective_at desc,created_at desc,consent_id desc) rn from privacy.consents c) x where rn=1;

create or replace function docs.register_file_metadata(p_raw_input_id text,p_provider text,p_storage_profile_key text,p_bucket text default null,p_object_key text default null,p_provider_file_ref text default null,p_legacy_drive_file_id text default null,p_source_url text default null,p_original_filename text default null,p_stored_filename text default null,p_mime_type text default null,p_size_bytes bigint default null,p_checksum_sha256 text default null,p_storage_status text default 'SOURCE_ONLY',p_sensitivity text default 'INTERNAL',p_search_tags text[] default '{}',p_description text default null,p_created_by text default 'system') returns text language plpgsql security definer set search_path=''
as $$ declare v_alloc jsonb;v_file_id text;v_visibility text; begin if not config.setting_is_true('postgres_docs_write_enabled') then raise exception 'postgres docs write gate is disabled'; end if; if p_raw_input_id is null or not exists(select 1 from ops.raw_inputs where raw_input_id=p_raw_input_id) then raise exception 'valid raw_input_id required'; end if; select desired_visibility into v_visibility from docs.storage_profiles where storage_profile_key=p_storage_profile_key; if not found then raise exception 'unknown storage profile: %',p_storage_profile_key; end if; if v_visibility='PUBLIC' and not config.setting_is_true('supabase_storage_external_access_enabled') then v_visibility:='PRIVATE'; end if; v_alloc:=config.allocate_business_id('File Registry',p_created_by,jsonb_build_object('source','Part4B docs.register_file_metadata')); v_file_id:=v_alloc->>'allocated_id'; insert into docs.files(file_id,raw_input_id,provider,storage_profile_key,bucket,object_key,provider_file_ref,legacy_drive_file_id,source_url,original_filename,stored_filename,mime_type,size_bytes,checksum_sha256,visibility,sensitivity,storage_status,search_tags,description,created_by) values(v_file_id,p_raw_input_id,upper(p_provider),p_storage_profile_key,p_bucket,p_object_key,p_provider_file_ref,p_legacy_drive_file_id,p_source_url,p_original_filename,p_stored_filename,p_mime_type,p_size_bytes,p_checksum_sha256,v_visibility,upper(p_sensitivity),upper(p_storage_status),coalesce(p_search_tags,'{}'),p_description,p_created_by); return v_file_id; end; $$;

create or replace function docs.register_evidence_record(p_file_id text,p_evidence_type text,p_evidence_class text default 'BUSINESS_EVIDENCE',p_evidence_date timestamptz default null,p_source_authority text default null,p_notes text default null,p_created_by text default 'system') returns text language plpgsql security definer set search_path=''
as $$ declare v_alloc jsonb;v_evidence_id text; begin if not config.setting_is_true('postgres_docs_write_enabled') then raise exception 'postgres docs write gate is disabled'; end if; if not exists(select 1 from docs.files where file_id=p_file_id) then raise exception 'unknown file_id: %',p_file_id; end if; v_alloc:=config.allocate_business_id('Evidence',p_created_by,jsonb_build_object('source','Part4B docs.register_evidence_record')); v_evidence_id:=v_alloc->>'allocated_id'; insert into docs.evidence(evidence_id,file_id,evidence_type,evidence_class,evidence_date,source_authority,notes,created_by) values(v_evidence_id,p_file_id,p_evidence_type,upper(p_evidence_class),p_evidence_date,p_source_authority,p_notes,p_created_by); return v_evidence_id; end; $$;

create or replace function docs.link_evidence(p_evidence_id text,p_entity_type text,p_entity_id text,p_link_role text default 'SUPPORTS',p_created_by text default 'system') returns void language plpgsql security definer set search_path=''
as $$ begin if not config.setting_is_true('postgres_docs_write_enabled') then raise exception 'postgres docs write gate is disabled'; end if; if not exists(select 1 from docs.evidence where evidence_id=p_evidence_id) then raise exception 'unknown evidence_id'; end if; insert into docs.evidence_links(evidence_id,entity_type,entity_id,link_role,created_by) values(p_evidence_id,p_entity_type,p_entity_id,p_link_role,p_created_by) on conflict do nothing; end; $$;

create or replace function privacy.record_consent(p_candidate_id text,p_purpose_code text,p_decision text,p_effective_at timestamptz,p_evidence_id text,p_source_raw_input_id text default null,p_supersedes_consent_id text default null,p_notes text default null,p_created_by text default 'system') returns text language plpgsql security definer set search_path=''
as $$ declare v_alloc jsonb;v_consent_id text; begin if not config.setting_is_true('postgres_consent_write_enabled') then raise exception 'postgres consent write gate is disabled'; end if; if not exists(select 1 from core.candidates where candidate_id=p_candidate_id) then raise exception 'unknown candidate_id'; end if; if not exists(select 1 from docs.evidence where evidence_id=p_evidence_id) then raise exception 'evidence-backed consent required'; end if; v_alloc:=config.allocate_business_id('Consent',p_created_by,jsonb_build_object('source','Part4B privacy.record_consent')); v_consent_id:=v_alloc->>'allocated_id'; insert into privacy.consents(consent_id,candidate_id,purpose_code,decision,effective_at,evidence_id,source_raw_input_id,supersedes_consent_id,notes,created_by) values(v_consent_id,p_candidate_id,p_purpose_code,upper(p_decision),p_effective_at,p_evidence_id,p_source_raw_input_id,p_supersedes_consent_id,p_notes,p_created_by); return v_consent_id; end; $$;

alter table private.candidate_contacts enable row level security;
alter table private.client_contacts enable row level security;
alter table private.partner_contacts enable row level security;
alter table docs.storage_profiles enable row level security;
alter table docs.files enable row level security;
alter table docs.evidence enable row level security;
alter table docs.evidence_links enable row level security;
alter table privacy.consents enable row level security;

revoke all on schema private from public,anon,authenticated;
revoke all on schema privacy from public,anon,authenticated;
revoke all on schema docs from public,anon,authenticated;
revoke all on all tables in schema private from public,anon,authenticated;
revoke all on all tables in schema privacy from public,anon,authenticated;
revoke all on all tables in schema docs from public,anon,authenticated;
revoke execute on all functions in schema private from public,anon,authenticated;
revoke execute on all functions in schema privacy from public,anon,authenticated;
revoke execute on all functions in schema docs from public,anon,authenticated;

grant usage on schema private,privacy,docs to service_role;
grant select,insert,update,delete on all tables in schema private to service_role;
grant select,insert,update,delete on all tables in schema privacy to service_role;
grant select,insert,update,delete on all tables in schema docs to service_role;
grant execute on function docs.register_file_metadata(text,text,text,text,text,text,text,text,text,text,text,bigint,text,text,text,text[],text,text) to service_role;
grant execute on function docs.register_evidence_record(text,text,text,timestamptz,text,text,text) to service_role;
grant execute on function docs.link_evidence(text,text,text,text,text) to service_role;
grant execute on function privacy.record_consent(text,text,text,timestamptz,text,text,text,text,text) to service_role;

commit;
