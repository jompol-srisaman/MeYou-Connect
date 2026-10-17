#!/usr/bin/env node
// Synthetic capacity classifier + service/API contract harness. It applies the
// SQL review draft and fixtures only inside one rollback transaction on the
// pinned network-none clone. Synthetic bytes never claim physical guard PASS.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawnSync } from "node:child_process";

const TARGET="myc-restore-20261016-bootstrap";
const WARNING=262144000, DBSTOP=419430400, SHADOWSTOP=78643200;
const started=Date.now(), checks=[];
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
function run(cmd,args,input,timeout=30000) {
  const r=spawnSync(cmd,args,{input,encoding:"utf8",timeout,windowsHide:true,shell:false,maxBuffer:2*1024*1024});
  if(r.error) throw new Error(cmd+" failed: "+r.error.message);
  if(r.status!==0) throw new Error(cmd+" exited "+r.status+": "+String(r.stderr||"").trim().split(/\r?\n/).slice(-3).join(" ").slice(0,700));
  return String(r.stdout||"").trim();
}
if(process.env.MYC_TEST_CONTAINER!==undefined) assert.equal(process.env.MYC_TEST_CONTAINER,TARGET);
const context=run("docker",["context","show"]);
const endpoint=run("docker",["context","inspect",context,"--format","{{.Endpoints.docker.Host}}"]);
assert.match(endpoint,/^(npipe:|unix:|tcp:\/\/(127\.0\.0\.1|localhost)(:|\/|$))/);
const inspect=run("docker",["inspect","--format","{{.Name}}|{{.HostConfig.NetworkMode}}|{{json .NetworkSettings.Ports}}",TARGET]);
const [name,networkMode,ports]=inspect.split("|");
assert.equal(name,"/"+TARGET); assert.equal(networkMode,"none"); assert.ok(ports==="null"||ports==="{}");
const args=["exec","-i",TARGET,"psql","-X","-qAt","-v","ON_ERROR_STOP=1","-U","supabase_admin","-d","postgres","-h","/tmp"];
const psql=s=>run("docker",args,s,60000);
const readJson=s=>JSON.parse(psql(s).split(/\r?\n/).filter(Boolean).at(-1));
const before=readJson("select jsonb_build_object("+
 "'database',current_database(),'major',current_setting('server_version_num')::int/10000,"+
 "'socket',inet_server_addr() is null and inet_client_addr() is null,"+
 "'db_bytes',pg_database_size(current_database()),'shadow_bytes',pg_total_relation_size('ops.shadow_import_rows'::regclass),"+
 "'rows',(select count(*) from ops.shadow_import_rows),"+
 "'fingerprint',coalesce((select sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text from ops.shadow_import_rows r),'0'),"+
 "'sessions',(select count(*) from ops.shadow_import_sessions),"+
 "'flags',(select jsonb_build_array(config.setting_is_true('business_master_apply_enabled'),config.setting_is_true('migration_target_apply_enabled'),config.setting_is_true('production_cutover_approved'),config.setting_is_true('security_external_alert_delivery_enabled'))),"+
 "'cron3',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobname='meyou-connect-observability-refresh'),"+
 "'cron11',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobid=11 and jobname='myc_datahub_shadow_import_5min'),"+
 "'refresh',(select jsonb_build_object('oid',p.oid::text,'owner',p.proowner::regrole::text,'acl',coalesce(p.proacl::text,''),'definer',p.prosecdef,'config',coalesce(p.proconfig::text,'')) from pg_proc p where p.oid='ops.refresh_observability_signals(text)'::regprocedure),"+
 "'helpers',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname in ('capacity_classify','capacity_guard_metrics','emit_capacity_alert_if_due','record_capacity_recovery','refresh_capacity_guard_alerts','capture_capacity_guard_snapshot')),"+
 "'capacity_alerts',(select count(*) from ops.alert_instances where fingerprint in ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_DATABASE_CAPACITY_STOP_400MIB','MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED'))"+
 ")::text;");
assert.equal(before.database,"postgres"); assert.equal(before.major,17); assert.equal(before.socket,true);
assert.equal(before.rows,36818); assert.equal(before.sessions,3028); assert.equal(before.helpers,0); assert.equal(before.capacity_alerts,0);
assert.ok(before.cron3?.active); assert.equal(before.cron11?.active,false);
assert.deepEqual(before.flags,[false,false,false,false]);
assert.ok(before.db_bytes<DBSTOP); assert.ok(before.shadow_bytes<SHADOWSTOP);
checks.push({name:"clone_identity_baseline",status:"PASS",databaseBytes:before.db_bytes,shadowBytes:before.shadow_bytes,rows:before.rows,sessions:before.sessions});

const review=readFileSync("docs/runbooks/sql/MYC_CAPACITY_OBSERVABILITY_REVIEW.sql","utf8");
assert.match(review,/create or replace function ops\.refresh_observability_signals\(p_environment text default 'TEST'\)/i);
assert.match(review,/ops\.refresh_capacity_guard_alerts\(p_environment\)/);
assert.doesNotMatch(review,/\b(?:truncate|drop|delete\s+from|vacuum|cron\.schedule|cron\.unschedule)\b/i);
const expected=before.refresh,cron3=JSON.stringify(before.cron3),cron11=JSON.stringify(before.cron11);
const warningKey="MYC_DATABASE_CAPACITY_WARNING_250MIB",stopKey="MYC_DATABASE_CAPACITY_STOP_400MIB";
const founder="60000000-0000-0000-0000-000000000001",contentUser="60000000-0000-0000-0000-000000000002";
let sql="BEGIN READ WRITE;\n"+review+"\n";
sql+="DO $class$ DECLARE r jsonb; BEGIN "+
"r:=ops.capacity_classify("+ (WARNING-1)+","+(SHADOWSTOP-1)+"); IF r->>'database_state'<>'OK' OR r->>'shadow_state'<>'OK' THEN RAISE EXCEPTION 'below boundary'; END IF; "+
"r:=ops.capacity_classify("+WARNING+","+(SHADOWSTOP-1)+"); IF r->>'database_state'<>'WARN' THEN RAISE EXCEPTION '250 boundary'; END IF; "+
"r:=ops.capacity_classify("+(DBSTOP-1)+","+(SHADOWSTOP-1)+"); IF r->>'database_state'<>'WARN' THEN RAISE EXCEPTION 'below 400 boundary'; END IF; "+
"r:=ops.capacity_classify("+DBSTOP+","+(SHADOWSTOP-1)+"); IF r->>'database_state'<>'STOP' THEN RAISE EXCEPTION '400 boundary'; END IF; "+
"r:=ops.capacity_classify("+(WARNING-1)+","+SHADOWSTOP+"); IF r->>'shadow_state'<>'STOP' THEN RAISE EXCEPTION '75 boundary'; END IF; "+
"r:=ops.capacity_classify(null,null); IF r->>'database_state'<>'UNKNOWN' OR r->>'shadow_state'<>'UNKNOWN' THEN RAISE EXCEPTION 'missing metric'; END IF; END $class$;\n";
sql+="DO $acl$ DECLARE p record; m jsonb; BEGIN "+
"IF has_function_privilege('anon','ops.capacity_guard_metrics()','EXECUTE') OR has_function_privilege('authenticated','ops.capacity_guard_metrics()','EXECUTE') OR NOT has_function_privilege('service_role','ops.capacity_guard_metrics()','EXECUTE') THEN RAISE EXCEPTION 'metrics ACL'; END IF; "+
"IF has_function_privilege('anon','api.capacity_guard_health()','EXECUTE') OR NOT has_function_privilege('authenticated','api.capacity_guard_health()','EXECUTE') OR NOT has_function_privilege('service_role','api.capacity_guard_health()','EXECUTE') THEN RAISE EXCEPTION 'API ACL'; END IF; "+
"IF has_function_privilege('authenticated','ops.refresh_capacity_guard_alerts(text)','EXECUTE') OR NOT has_function_privilege('service_role','ops.refresh_capacity_guard_alerts(text)','EXECUTE') OR has_function_privilege('authenticated','ops.capture_capacity_guard_snapshot(text)','EXECUTE') OR NOT has_function_privilege('service_role','ops.capture_capacity_guard_snapshot(text)','EXECUTE') THEN RAISE EXCEPTION 'producer ACL'; END IF; "+
"SELECT proc.* INTO p FROM pg_proc proc WHERE proc.oid='ops.refresh_observability_signals(text)'::regprocedure; "+
"IF p.oid::text<>"+quote(expected.oid)+" OR p.proowner::regrole::text<>"+quote(expected.owner)+" OR coalesce(p.proacl::text,'')<>"+quote(expected.acl)+" OR p.prosecdef IS DISTINCT FROM "+String(expected.definer)+" OR coalesce(p.proconfig::text,'')<>"+quote(expected.config)+" THEN RAISE EXCEPTION 'refresh identity/ACL changed'; END IF; "+
"IF pg_get_functiondef(p.oid) NOT LIKE '%ops.refresh_capacity_guard_alerts%' OR pg_get_functiondef(p.oid) NOT LIKE '%ops.alert_candidates_v%' OR pg_get_functiondef(p.oid) NOT LIKE '%ops.security_events%' THEN RAISE EXCEPTION 'refresh body changed'; END IF; "+
"IF EXISTS(SELECT 1 FROM pg_proc proc JOIN pg_namespace ns ON ns.oid=proc.pronamespace WHERE (ns.nspname='ops' AND proc.proname IN ('capacity_classify','capacity_guard_metrics','emit_capacity_alert_if_due','record_capacity_recovery','refresh_capacity_guard_alerts','capture_capacity_guard_snapshot') OR ns.nspname='api' AND proc.proname='capacity_guard_health') AND (proc.proowner::regrole::text<>'postgres' OR NOT proc.prosecdef OR NOT (coalesce(proc.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=\"\"']::text[]))) THEN RAISE EXCEPTION 'helper owner/definer/search_path mismatch'; END IF; "+
"IF (SELECT jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) FROM cron.job WHERE jobname='meyou-connect-observability-refresh') IS DISTINCT FROM "+quote(cron3)+"::jsonb OR (SELECT jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) FROM cron.job WHERE jobid=11 and jobname='myc_datahub_shadow_import_5min') IS DISTINCT FROM "+quote(cron11)+"::jsonb THEN RAISE EXCEPTION 'cron changed'; END IF; "+
"m:=ops.capacity_guard_metrics(); IF m->>'database_bytes' IS NULL OR m->>'shadow_relation_bytes' IS NULL OR m->>'database_warning_bytes'<>'262144000' OR m->>'database_stop_bytes'<>'419430400' OR m->>'shadow_stop_bytes'<>'78643200' OR m ? 'source_pk' OR m ? 'session_id' OR m ? 'destination_ref' THEN RAISE EXCEPTION 'metrics/privacy'; END IF; END $acl$;\n";
sql+="DO $route$ BEGIN IF EXISTS(SELECT 1 FROM ops.alert_routes WHERE environment='TEST' AND owner_role='automation_worker' AND channel_type='DB_ONLY') THEN RAISE EXCEPTION 'synthetic DB_ONLY route key already exists'; END IF; END $route$; "+
"INSERT INTO ops.alert_routes(environment,owner_role,channel_type,destination_ref,verified,verified_at,verified_by,active) VALUES('TEST','automation_worker','DB_ONLY','synthetic-capacity-observability',true,now(),'capacity-observability-test',true);\n"+
"INSERT INTO auth.users(id,aud,role,email,created_at,updated_at,is_sso_user,is_anonymous) VALUES "+
"("+quote(founder)+",'authenticated','authenticated','capacity-founder@example.invalid',now(),now(),false,false),"+
"("+quote(contentUser)+",'authenticated','authenticated','capacity-content@example.invalid',now(),now(),false,false); "+
"SELECT authz.assign_role("+quote(founder)+",'founder','capacity-test','synthetic',null); "+
"SELECT authz.assign_role("+quote(contentUser)+",'content_studio','capacity-test','synthetic',null); "+
"SELECT set_config('request.jwt.claim.sub',"+quote(founder)+",true); SET LOCAL ROLE authenticated; "+
"DO $founder$ DECLARE m jsonb; BEGIN m:=api.capacity_guard_health(); IF m->>'database_bytes' IS NULL OR m ? 'destination_ref' THEN RAISE EXCEPTION 'founder API privacy'; END IF; BEGIN PERFORM ops.capacity_guard_metrics(); RAISE EXCEPTION 'helper unexpectedly public'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $founder$; "+
"SELECT set_config('request.jwt.claim.sub',"+quote(contentUser)+",true); "+
"DO $content$ BEGIN BEGIN PERFORM api.capacity_guard_health(); RAISE EXCEPTION 'content read succeeded'; EXCEPTION WHEN OTHERS THEN IF position('ACCESS_DENIED' in sqlerrm)=0 THEN RAISE; END IF; END; END $content$; "+
"RESET ROLE; SET LOCAL ROLE anon; SELECT set_config('request.jwt.claim.sub','',true); "+
"DO $anon$ BEGIN BEGIN PERFORM api.capacity_guard_health(); RAISE EXCEPTION 'anon read succeeded'; EXCEPTION WHEN insufficient_privilege THEN NULL; END; END $anon$; RESET ROLE;\n";
sql+="DO $signals$ DECLARE n integer; a ops.alert_instances%rowtype; i ops.incidents%rowtype; s text; v_unknown jsonb; w ops.alert_instances%rowtype; x ops.alert_instances%rowtype; BEGIN "+
"IF NOT ops.emit_capacity_alert_if_due('TEST',"+quote(warningKey)+",'SEV2','Synthetic throttle',jsonb_build_object('database_bytes',"+WARNING+",'threshold_bytes',"+WARNING+")) THEN RAISE EXCEPTION 'new signal suppressed'; END IF; "+
"IF ops.emit_capacity_alert_if_due('TEST',"+quote(warningKey)+",'SEV2','Synthetic repeat',jsonb_build_object('database_bytes',"+WARNING+",'threshold_bytes',"+WARNING+")) THEN RAISE EXCEPTION 'six-hour throttle failed'; END IF; "+
"UPDATE ops.alert_instances SET last_seen_at=now()-interval '6 hours 1 second' WHERE environment='TEST' AND fingerprint="+quote(warningKey)+"; "+
"IF NOT ops.emit_capacity_alert_if_due('TEST',"+quote(warningKey)+",'SEV2','Synthetic reminder',jsonb_build_object('database_bytes',"+WARNING+",'threshold_bytes',"+WARNING+")) THEN RAISE EXCEPTION 'reminder missing'; END IF; "+
"SELECT * INTO a FROM ops.alert_instances WHERE environment='TEST' AND fingerprint="+quote(warningKey)+"; IF a.occurrence_count<>2 OR a.metadata ? 'source_pk' OR a.metadata ? 'raw_record' THEN RAISE EXCEPTION 'dedupe/privacy'; END IF; "+
"IF (SELECT delivery_status FROM ops.alert_delivery_queue WHERE alert_pk=a.alert_pk)<>'HELD' THEN RAISE EXCEPTION 'external delivery was not held'; END IF; "+
"PERFORM ops.ingest_alert_signal('TEST',"+quote(stopKey)+","+quote(stopKey)+",'SEV1','Synthetic stop',1,'MYC_CAPACITY_GUARD',jsonb_build_object('database_bytes',"+DBSTOP+",'threshold_bytes',"+DBSTOP+"),now()); "+
"SELECT * INTO a FROM ops.alert_instances WHERE environment='TEST' AND fingerprint="+quote(stopKey)+"; SELECT * INTO i FROM ops.incidents WHERE alert_pk=a.alert_pk AND status<>'CLOSED'; "+
"IF i.incident_pk IS NULL THEN RAISE EXCEPTION 'SEV1 incident missing'; END IF; "+
"CREATE OR REPLACE FUNCTION ops.capacity_guard_metrics() RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path='' AS $$ SELECT jsonb_build_object('database_state','UNKNOWN','shadow_state','UNKNOWN','database_bytes',null,'shadow_relation_bytes',null) $$; ALTER FUNCTION ops.capacity_guard_metrics() OWNER TO postgres; "+
"SELECT * INTO w FROM ops.alert_instances WHERE environment='TEST' AND fingerprint="+quote(warningKey)+"; SELECT * INTO x FROM ops.alert_instances WHERE environment='TEST' AND fingerprint="+quote(stopKey)+"; v_unknown:=ops.refresh_capacity_guard_alerts('TEST'); IF v_unknown->>'database_state'<>'UNKNOWN' OR v_unknown->>'shadow_state'<>'UNKNOWN' OR (v_unknown->>'capacity_recoveries_recorded')::int<>0 THEN RAISE EXCEPTION 'UNKNOWN falsely claimed recovery'; END IF; IF (SELECT status FROM ops.alert_instances WHERE alert_pk=w.alert_pk) NOT IN ('OPEN','ACKNOWLEDGED') OR (SELECT status FROM ops.alert_instances WHERE alert_pk=x.alert_pk) NOT IN ('OPEN','ACKNOWLEDGED') OR (SELECT metadata->>'capacity_recovered_at' FROM ops.alert_instances WHERE alert_pk=x.alert_pk) IS NOT NULL OR EXISTS(SELECT 1 FROM ops.alert_occurrences WHERE alert_pk IN (w.alert_pk,x.alert_pk) AND metadata->>'transition'='CAPACITY_RECOVERED') THEN RAISE EXCEPTION 'UNKNOWN resolved active warning/SEV1 or asserted recovery'; END IF; "+
"n:=ops.record_capacity_recovery('TEST',"+quote(warningKey)+",'BELOW_250MIB',true); SELECT * INTO a FROM ops.alert_instances WHERE environment='TEST' AND fingerprint="+quote(warningKey)+"; IF n<>1 OR a.status<>'RESOLVED' OR a.resolved_by<>'SYSTEM_CAPACITY_GUARD' OR NOT EXISTS(SELECT 1 FROM ops.alert_occurrences WHERE alert_pk=a.alert_pk AND metadata->>'transition'='CAPACITY_RECOVERED') OR (SELECT delivery_status FROM ops.alert_delivery_queue WHERE alert_pk=a.alert_pk)<>'CANCELLED' THEN RAISE EXCEPTION 'warning recovery audit'; END IF; "+
"SELECT * INTO a FROM ops.alert_instances WHERE environment='TEST' AND fingerprint="+quote(stopKey)+"; n:=ops.record_capacity_recovery('TEST',"+quote(stopKey)+",'BELOW_400MIB',false); "+
"SELECT status INTO s FROM ops.incidents WHERE incident_pk=i.incident_pk; IF n<>1 OR s='CLOSED' OR s IS NULL OR (SELECT status FROM ops.alert_instances WHERE alert_pk=a.alert_pk)<>'OPEN' OR (SELECT delivery_status FROM ops.alert_delivery_queue WHERE alert_pk=a.alert_pk)<>'CANCELLED' THEN RAISE EXCEPTION 'stop recovery mismatch n=% incident=% alert=% queue=%',n,s,(SELECT status FROM ops.alert_instances WHERE alert_pk=a.alert_pk),(SELECT delivery_status FROM ops.alert_delivery_queue WHERE alert_pk=a.alert_pk); END IF; END $signals$;\n";
sql+=review+"\n";
sql+="DO $refresh$ DECLARE r jsonb; BEGIN r:=ops.refresh_observability_signals('TEST'); IF NOT (r ? 'alert_candidates_scanned') OR NOT (r ? 'security_events_scanned') OR NOT (r ? 'capacity_guard') OR NOT (r ? 'capacity_history') OR r->'capacity_guard'->>'database_bytes' IS NULL OR (r->'capacity_guard'->>'capacity_alerts_emitted')::int<>0 THEN RAISE EXCEPTION 'refresh integration failed'; END IF; END $refresh$;\n"+
"DO $history$ DECLARE r jsonb; n integer; BEGIN r:=ops.capture_capacity_guard_snapshot('TEST'); IF (r->>'captured')::boolean OR (r->>'history_full')::boolean THEN RAISE EXCEPTION '15-minute sample throttle failed'; END IF; "+
"SELECT count(*) INTO n FROM ops.recovery_monitor_snapshots WHERE environment='TEST' AND details->>'capture_source'='MYC_CAPACITY_GUARD'; "+
"INSERT INTO ops.recovery_monitor_snapshots(environment,captured_at,overall_status,details) SELECT 'TEST',now()-interval '22 days'+(g||' seconds')::interval,'NOT_READY',jsonb_build_object('monitor_only',true,'capture_source','MYC_CAPACITY_GUARD','does_not_evaluate_recovery',true,'metrics',jsonb_build_object('database_bytes',1,'shadow_relation_bytes',1)) FROM generate_series(1,2016-n) g; "+
"r:=ops.capture_capacity_guard_snapshot('TEST'); IF (r->>'captured')::boolean OR NOT (r->>'history_full')::boolean OR (r->>'retained_samples')::int<>2016 OR NOT (r->>'archive_alert_emitted')::boolean THEN RAISE EXCEPTION 'sample cap/archive alert failed'; END IF; "+
"IF (SELECT count(*) FROM ops.recovery_monitor_snapshots WHERE environment='TEST' AND details->>'capture_source'='MYC_CAPACITY_GUARD')<>2016 THEN RAISE EXCEPTION 'history cap exceeded'; END IF; "+
"IF (SELECT overall_status FROM ops.recovery_monitor_snapshots WHERE environment='TEST' AND details->>'capture_source'='MYC_CAPACITY_GUARD' ORDER BY captured_at DESC LIMIT 1)<>'NOT_READY' THEN RAISE EXCEPTION 'capacity sample claimed recovery PASS'; END IF; END $history$;\nROLLBACK; SELECT 'ROLLED_BACK';\n";
const result=psql(sql);
assert.match(result,/ROLLED_BACK/);
checks.push({name:"synthetic_boundaries_acl_throttle_recovery_refresh",status:"PASS",cases:["250MiB-1","250MiB","400MiB-1","400MiB","75MiB-1","75MiB"],note:"Synthetic byte classification only; not physical guard proof"});

const after=readJson("select jsonb_build_object("+
 "'rows',(select count(*) from ops.shadow_import_rows),"+
 "'fingerprint',coalesce((select sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text from ops.shadow_import_rows r),'0'),"+
 "'sessions',(select count(*) from ops.shadow_import_sessions),"+
 "'cron3',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobname='meyou-connect-observability-refresh'),"+
 "'cron11',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobid=11 and jobname='myc_datahub_shadow_import_5min'),"+
 "'alerts',(select count(*) from ops.alert_instances where fingerprint in ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_DATABASE_CAPACITY_STOP_400MIB','MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED')),"+
 "'helpers',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname in ('capacity_classify','capacity_guard_metrics','emit_capacity_alert_if_due','record_capacity_recovery','refresh_capacity_guard_alerts','capture_capacity_guard_snapshot')),"+
 "'flags',(select jsonb_build_array(config.setting_is_true('business_master_apply_enabled'),config.setting_is_true('migration_target_apply_enabled'),config.setting_is_true('production_cutover_approved'),config.setting_is_true('security_external_alert_delivery_enabled')))"+
 ")::text;");
assert.equal(after.rows,before.rows); assert.equal(after.fingerprint,before.fingerprint); assert.equal(after.sessions,before.sessions);
assert.deepEqual(after.cron3,before.cron3); assert.deepEqual(after.cron11,before.cron11);
assert.equal(after.alerts,before.capacity_alerts); assert.equal(after.helpers,0); assert.deepEqual(after.flags,[false,false,false,false]);
checks.push({name:"rollback_preserves_source_guards_crons_and_flags",status:"PASS",shadowRows:after.rows,shadowFingerprint:after.fingerprint,sessions:after.sessions,syntheticAlerts:0,cron3Unchanged:true,cron11Inactive:true});

process.stdout.write(JSON.stringify({
  suite:"myc-capacity-observability.integration",status:"PASS",
  target:{container:TARGET,networkMode,publishedPorts:false},
  baseline:{databaseBytes:before.db_bytes,shadowBytes:before.shadow_bytes,shadowRows:before.rows,sessions:before.sessions},
  thresholds:{warningBytes:WARNING,databaseStopBytes:DBSTOP,shadowStopBytes:SHADOWSTOP},
  elapsedMs:Date.now()-started,checks
},null,2)+"\n");
