begin;
alter table core.candidates drop constraint if exists candidates_candidate_id_check;
alter table core.candidates add constraint candidates_candidate_id_check check (candidate_id ~ '^WC-C-[0-9]{6}$');
commit;