begin;
create index if not exists files_storage_profile_idx on docs.files(storage_profile_key);
create index if not exists consents_supersedes_idx on privacy.consents(supersedes_consent_id) where supersedes_consent_id is not null;
commit;
