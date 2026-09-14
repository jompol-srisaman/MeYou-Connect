-- Allow database owner/admin test path to evaluate the service-role-only compatibility view without broadening client access.
grant execute on function ops.file_intelligence_route_v1(text,text) to postgres;
