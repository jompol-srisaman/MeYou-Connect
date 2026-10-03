-- P0 READ GATE CLOSURE: minimal server-side read privilege for Official Operational Read Contract V1.
-- Scope: view only. No underlying Raw-table grants are changed.
-- Rollback: REVOKE SELECT ON ops.line_inbox_v FROM service_role;
revoke all on ops.line_inbox_v from public, anon, authenticated;
grant select on ops.line_inbox_v to service_role;
comment on view ops.line_inbox_v is 'Official Operational Read Contract V1 technical LINE inbox projection. Browser roles denied; approved server-side service_role reader permitted. Rollback by revoking SELECT from service_role.';
