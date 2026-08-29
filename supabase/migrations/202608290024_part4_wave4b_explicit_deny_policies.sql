begin;

do $$
declare r record;
begin
  for r in
    select * from (values
      ('private','candidate_contacts'),('private','client_contacts'),('private','partner_contacts'),
      ('privacy','consents'),
      ('docs','storage_profiles'),('docs','files'),('docs','evidence'),('docs','evidence_links')
    ) as t(schema_name,table_name)
  loop
    execute format('drop policy if exists deny_client_direct on %I.%I',r.schema_name,r.table_name);
    execute format('create policy deny_client_direct on %I.%I as restrictive for all to anon, authenticated using (false) with check (false)',r.schema_name,r.table_name);
  end loop;
end $$;

commit;
