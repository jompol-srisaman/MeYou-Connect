begin;
create index if not exists user_roles_role_key_idx on authz.user_roles(role_key);
create index if not exists role_assignment_audit_role_key_idx on authz.role_assignment_audit(role_key);

drop policy if exists user_profiles_self_read on authz.user_profiles;
create policy user_profiles_self_read on authz.user_profiles for select to authenticated using (auth_user_id=(select auth.uid()));

drop policy if exists user_roles_self_read on authz.user_roles;
create policy user_roles_self_read on authz.user_roles for select to authenticated using (auth_user_id=(select auth.uid()));
commit;