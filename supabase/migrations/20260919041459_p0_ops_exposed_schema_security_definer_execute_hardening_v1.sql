-- `ops` is exposed to Data API for approved server-side surfaces.
-- SECURITY DEFINER parser/router RPCs remain service-role only.
revoke execute on function ops.parse_line_candidate_raw_base_v1(text) from public,anon,authenticated;
revoke execute on function ops.parse_line_candidate_raw_v1(text) from public,anon,authenticated;
revoke execute on function ops.route_line_raw_event_v1(uuid) from public,anon,authenticated;
revoke execute on function ops.run_line_candidate_ingestion_tick(timestamptz,integer,text) from public,anon,authenticated;
grant execute on function ops.parse_line_candidate_raw_base_v1(text) to service_role;
grant execute on function ops.parse_line_candidate_raw_v1(text) to service_role;
grant execute on function ops.route_line_raw_event_v1(uuid) to service_role;
grant execute on function ops.run_line_candidate_ingestion_tick(timestamptz,integer,text) to service_role;
