-- P0 runtime privilege smoke: prove approved server role can execute the projection while browser roles remain denied.
set local role service_role;
select count(*) from ops.line_inbox_v;
reset role;

do $$
begin
  if not has_table_privilege('service_role','ops.line_inbox_v','select') then
    raise exception 'LINE_INBOX_SERVICE_ROLE_SELECT_MISSING';
  end if;
  if has_table_privilege('anon','ops.line_inbox_v','select') then
    raise exception 'LINE_INBOX_ANON_EXPOSURE';
  end if;
  if has_table_privilege('authenticated','ops.line_inbox_v','select') then
    raise exception 'LINE_INBOX_AUTHENTICATED_EXPOSURE';
  end if;
end $$;
