revoke execute on function authz.current_roles() from public,anon,authenticated;
revoke execute on function authz.current_capabilities() from public,anon,authenticated;
revoke execute on function authz.has_role(text) from public,anon,authenticated;
revoke execute on function authz.has_any_role(text[]) from public,anon,authenticated;
revoke execute on function authz.has_capability(text) from public,anon,authenticated;
revoke execute on function authz.require_capability(text) from public,anon,authenticated;
grant execute on function authz.current_roles(),authz.current_capabilities(),authz.has_role(text),authz.has_any_role(text[]),authz.has_capability(text),authz.require_capability(text) to authenticated,service_role;

revoke execute on function authz.ensure_profile_for_new_user() from public,anon,authenticated;
grant execute on function authz.ensure_profile_for_new_user() to service_role;

revoke execute on function config.setting_is_true(text) from public,anon,authenticated;
grant execute on function config.setting_is_true(text) to service_role;