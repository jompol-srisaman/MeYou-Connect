do $$
declare t text;
begin
 foreach t in array array['security_environments','credential_requirements','credential_bindings','secret_scan_runs','secret_scan_findings','credential_rotation_events'] loop
   execute format('drop policy if exists %I on ops.%I','p5e_explicit_deny_client',t);
   execute format('create policy %I on ops.%I as restrictive for all to anon, authenticated using (false) with check (false)','p5e_explicit_deny_client',t);
 end loop;
end $$;