#!/usr/bin/env node
// Disposable-clone-only contract test. All draft DDL, route/rule fixtures,
// gate toggles, alerts, queue attempts, and receipt markers are rolled back.

import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";

const TARGET="myc-restore-20261016-bootstrap";
const started=Date.now();
const quote=v=>"'"+String(v).replaceAll("'","''")+"'";
function run(cmd,args,input,timeout=30000) {
  const r=spawnSync(cmd,args,{input,encoding:"utf8",timeout,windowsHide:true,shell:false,maxBuffer:2*1024*1024});
  if(r.error) throw new Error(cmd+" failed: "+r.error.message);
  if(r.status!==0) throw new Error(cmd+" exited "+r.status+": "+String(r.stderr||"").trim().split(/\r?\n/).slice(-4).join(" ").slice(0,900));
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
const psql=s=>run("docker",args,s,90000);
const readJson=s=>JSON.parse(psql(s).split(/\r?\n/).filter(Boolean).at(-1));
function startPsql(input) {
  const child=spawn("docker",args,{windowsHide:true,shell:false,stdio:["pipe","pipe","pipe"]});
  let stdout="",stderr="",firstResolve,firstReject;
  const firstLine=new Promise((resolve,reject)=>{firstResolve=resolve;firstReject=reject;});
  child.stdout.setEncoding("utf8"); child.stderr.setEncoding("utf8");
  child.stdout.on("data",chunk=>{
    stdout+=chunk;
    for(const line of stdout.split(/\r?\n/)) {
      if(!line||line.startsWith("NOTICE:")||line.startsWith("WARNING:")) continue;
      try { firstResolve(JSON.parse(line)); return; } catch {}
    }
  });
  child.stderr.on("data",chunk=>{stderr+=chunk;});
  const done=new Promise((resolve,reject)=>child.on("close",code=>code===0?resolve(stdout):reject(new Error("concurrent psql failed: "+stderr.slice(-700)))));
  child.stdin.end(input);
  return {firstLine,done,kill:()=>child.kill()};
}
const initial=readJson("select jsonb_build_object("+
 "'database',current_database(),'major',current_setting('server_version_num')::int/10000,'socket',inet_server_addr() is null and inet_client_addr() is null,"+
 "'rows',(select count(*) from ops.shadow_import_rows),"+
 "'shadow_hash',coalesce((select sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text from ops.shadow_import_rows r),'0'),"+
 "'sessions',(select count(*) from ops.shadow_import_sessions),"+
 "'queue_count',(select count(*) from ops.alert_delivery_queue),"+
 "'queue_hash',coalesce((select md5(coalesce(string_agg(q.delivery_pk::text||':'||q.delivery_status||':'||q.attempt_count||':'||coalesce(q.last_attempt_at::text,'')||':'||coalesce(q.last_error,''),'|' order by q.delivery_pk),'')) from ops.alert_delivery_queue q),''),"+
 "'alert_count',(select count(*) from ops.alert_instances),"+
 "'alert_hash',coalesce((select md5(coalesce(string_agg(a.alert_pk::text||':'||a.status||':'||a.occurrence_count||':'||coalesce(a.metadata::text,''),'|' order by a.alert_pk),'')) from ops.alert_instances a),''),"+
 "'routes',(select count(*) from ops.alert_routes),"+
 "'founder_email_routes',(select count(*) from ops.alert_routes where environment='TEST' and owner_role='founder' and channel_type='EMAIL'),"+
 "'rules',(select count(*) from ops.alert_rule_catalog),"+
 "'flags',(select jsonb_build_array(config.setting_is_true('business_master_apply_enabled'),config.setting_is_true('migration_target_apply_enabled'),config.setting_is_true('production_cutover_approved'),config.setting_is_true('security_external_alert_delivery_enabled'))),"+
 "'cron3',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobname='meyou-connect-observability-refresh'),"+
 "'cron11',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobid=11 and jobname='myc_datahub_shadow_import_5min'),"+
 "'worker_functions',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname in ('claim_myc_capacity_emails','complete_myc_capacity_email'))"+
 ",'capacity_rules',(select count(*) from ops.alert_rule_catalog where source_signal_key in ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_CAPACITY_DELIVERY_TEST'))"+
 ",'active_capacity_alerts',(select count(*) from ops.alert_instances where environment='TEST' and signal_key in ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_CAPACITY_DELIVERY_TEST') and status in ('OPEN','ACKNOWLEDGED'))"+
 ")::text;");
assert.equal(initial.database,"postgres"); assert.equal(initial.major,17); assert.equal(initial.socket,true);
assert.equal(initial.founder_email_routes,0,"clone already has TEST founder EMAIL route; do not overwrite it");
assert.equal(initial.worker_functions,0,"worker contract already exists on clone");
assert.equal(initial.capacity_rules,0,"clone already has capacity test rule rows"); assert.equal(initial.active_capacity_alerts,0,"clone already has active capacity fixture alerts");
assert.deepEqual(initial.flags,[false,false,false,false]); assert.ok(initial.cron3?.active); assert.equal(initial.cron11?.active,false);

const capacitySql=readFileSync("docs/runbooks/sql/MYC_CAPACITY_OBSERVABILITY_REVIEW.sql","utf8");
const workerSql=readFileSync("docs/runbooks/sql/MYC_CAPACITY_EMAIL_WORKER_REVIEW.sql","utf8");
assert.match(workerSql,/destination_ref='MYC_FOUNDER_CONNECTED_GMAIL_SELF'/);
assert.match(workerSql,/for update of q skip locked/i);
assert.doesNotMatch(workerSql,/insert\s+into\s+ops\.(?:alert_routes|alert_rule_catalog)|security_external_alert_delivery_enabled.*(?:true|=\s*'true')/i);
const runId=randomUUID().replaceAll("-","").slice(0,12).toUpperCase();
const signals=[
 {key:"MYC_DATABASE_CAPACITY_WARNING_250MIB",severity:"SEV2",summary:"Database capacity warning test",meta:{database_bytes:262144000,threshold_bytes:262144000}},
 {key:"MYC_DATABASE_CAPACITY_STOP_400MIB",severity:"SEV1",summary:"Database capacity stop test",meta:{database_bytes:419430400,threshold_bytes:419430400}},
 {key:"MYC_SHADOW_CAPACITY_STOP_75MIB",severity:"SEV1",summary:"Shadow capacity stop test",meta:{shadow_relation_bytes:78643200,threshold_bytes:78643200}},
 {key:"MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED",severity:"SEV2",summary:"Capacity archive test",meta:{retained_samples:2016,sample_limit:2016}},
 {key:"MYC_CAPACITY_DELIVERY_TEST",severity:"SEV2",summary:"Capacity email transport test",meta:{test:true}}
];
const notAllowed="MYC_TEST_NONCAPACITY_"+runId;
const ruleSql=signals.map((s,i)=>"insert into ops.alert_rule_catalog(alert_rule_key,source_signal_key,severity,owner_role,auto_incident,description,source_ref) values("+
 quote("ALT-EMCAP-"+runId+"-"+i)+","+quote(s.key)+","+quote(s.severity)+",'founder',false,'Rollback-only capacity email fixture','MYC_CAPACITY_EMAIL_TEST');").join("\n")+
 "\ninsert into ops.alert_rule_catalog(alert_rule_key,source_signal_key,severity,owner_role,auto_incident,description,source_ref) values("+
 quote("ALT-EMCAP-"+runId+"-X")+","+quote(notAllowed)+",'SEV2','founder',false,'Rollback-only non-capacity fixture','MYC_CAPACITY_EMAIL_TEST');";
let sql="BEGIN READ WRITE;\n"+capacitySql+"\n"+workerSql+"\n";
sql+="DO $acl$ BEGIN "+
 "IF has_function_privilege('anon','ops.claim_myc_capacity_emails(integer)','EXECUTE') OR has_function_privilege('authenticated','ops.claim_myc_capacity_emails(integer)','EXECUTE') OR NOT has_function_privilege('service_role','ops.claim_myc_capacity_emails(integer)','EXECUTE') THEN RAISE EXCEPTION 'claim ACL'; END IF; "+
 "IF has_function_privilege('anon','ops.complete_myc_capacity_email(uuid,timestamptz,text,boolean,text)','EXECUTE') OR has_function_privilege('authenticated','ops.complete_myc_capacity_email(uuid,timestamptz,text,boolean,text)','EXECUTE') OR NOT has_function_privilege('service_role','ops.complete_myc_capacity_email(uuid,timestamptz,text,boolean,text)','EXECUTE') THEN RAISE EXCEPTION 'complete ACL'; END IF; "+
 "IF EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace JOIN pg_roles r ON r.oid=p.proowner WHERE n.nspname='ops' AND p.proname IN ('claim_myc_capacity_emails','complete_myc_capacity_email') AND (p.proowner::regrole::text<>'postgres' OR NOT p.prosecdef OR NOT r.rolbypassrls OR NOT (coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=\"\"']::text[]))) THEN RAISE EXCEPTION 'function owner/definer/search_path'; END IF; END $acl$;\n"+
 "CREATE TEMP TABLE email_fixture(alert_key text,signal_key text,alert_pk uuid,delivery_pk uuid); CREATE TEMP TABLE email_claims(delivery_pk uuid,claimed_at timestamptz,signal_key text,attempt_count integer,email_subject_tag text,summary text,capacity_metrics jsonb);\n"+
 ruleSql+"\n"+
 "INSERT INTO ops.alert_routes(environment,owner_role,channel_type,destination_ref,verified,verified_at,verified_by,active) VALUES('TEST','founder','EMAIL','MYC_FOUNDER_CONNECTED_GMAIL_SELF',true,now(),'rollback-test',true);\n";
for(const s of signals){
 sql+="SELECT ops.ingest_alert_signal('TEST',"+quote(s.key)+","+quote(s.key)+","+quote(s.severity)+","+quote(s.summary)+",1,'MYC_CAPACITY_EMAIL_TEST',"+quote(JSON.stringify(s.meta))+"::jsonb,now());\n";
 sql+="INSERT INTO email_fixture(alert_key,signal_key,alert_pk,delivery_pk) SELECT "+quote(s.key)+","+quote(s.key)+",a.alert_pk,q.delivery_pk FROM ops.alert_instances a JOIN ops.alert_delivery_queue q ON q.alert_pk=a.alert_pk JOIN ops.alert_routes r ON r.route_pk=q.route_pk WHERE a.environment='TEST' AND a.fingerprint="+quote(s.key)+" AND r.destination_ref='MYC_FOUNDER_CONNECTED_GMAIL_SELF';\n";
}
sql+="SELECT ops.ingest_alert_signal('TEST',"+quote(notAllowed)+","+quote(notAllowed)+",'SEV2','Non-capacity fixture',1,'MYC_CAPACITY_EMAIL_TEST','{}'::jsonb,now());\n"+
 "INSERT INTO email_fixture(alert_key,signal_key,alert_pk,delivery_pk) SELECT "+quote(notAllowed)+","+quote(notAllowed)+",a.alert_pk,q.delivery_pk FROM ops.alert_instances a JOIN ops.alert_delivery_queue q ON q.alert_pk=a.alert_pk JOIN ops.alert_routes r ON r.route_pk=q.route_pk WHERE a.environment='TEST' AND a.fingerprint="+quote(notAllowed)+" AND r.destination_ref='MYC_FOUNDER_CONNECTED_GMAIL_SELF';\n"+
 "DO $held$ BEGIN IF EXISTS(SELECT 1 FROM email_fixture f JOIN ops.alert_delivery_queue q USING(delivery_pk) WHERE q.delivery_status<>'HELD') THEN RAISE EXCEPTION 'gate-off fixture was not HELD'; END IF; IF EXISTS(SELECT 1 FROM ops.claim_myc_capacity_emails(5)) THEN RAISE EXCEPTION 'claim escaped false gate'; END IF; END $held$;\n"+
 "UPDATE config.system_settings SET setting_value='true'::jsonb,updated_at=now() WHERE setting_key='security_external_alert_delivery_enabled';\n";
for(const s of signals){sql+="SELECT ops.ingest_alert_signal('TEST',"+quote(s.key)+","+quote(s.key)+","+quote(s.severity)+","+quote(s.summary)+",1,'MYC_CAPACITY_EMAIL_TEST',"+quote(JSON.stringify(s.meta))+"::jsonb,now());\n";}
sql+="SELECT ops.ingest_alert_signal('TEST',"+quote(notAllowed)+","+quote(notAllowed)+",'SEV2','Non-capacity fixture',1,'MYC_CAPACITY_EMAIL_TEST','{}'::jsonb,now());\n"+
 "DO $ready$ BEGIN IF EXISTS(SELECT 1 FROM email_fixture f JOIN ops.alert_delivery_queue q USING(delivery_pk) WHERE q.delivery_status<>'READY') THEN RAISE EXCEPTION 'gate-on fixture did not become READY'; END IF; END $ready$;\n"+
 "INSERT INTO email_claims SELECT c.delivery_pk,c.claimed_at,c.signal_key,q.attempt_count,c.email_subject_tag,c.summary,c.capacity_metrics FROM ops.claim_myc_capacity_emails(5) c JOIN ops.alert_delivery_queue q USING(delivery_pk);\n"+
 "DO $claims$ DECLARE n integer; v record; BEGIN SELECT count(*) INTO n FROM email_claims; IF n<>5 OR EXISTS(SELECT 1 FROM email_claims WHERE signal_key="+quote(notAllowed)+") THEN RAISE EXCEPTION 'wrong claims returned'; END IF; IF EXISTS(SELECT 1 FROM email_claims c JOIN ops.alert_delivery_queue q USING(delivery_pk) WHERE q.attempt_count<>1 OR q.delivery_status<>'READY' OR c.signal_key NOT IN ('MYC_DATABASE_CAPACITY_WARNING_250MIB','MYC_DATABASE_CAPACITY_STOP_400MIB','MYC_SHADOW_CAPACITY_STOP_75MIB','MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED','MYC_CAPACITY_DELIVERY_TEST')) THEN RAISE EXCEPTION 'claim state'; END IF; IF EXISTS(SELECT 1 FROM ops.claim_myc_capacity_emails(5)) THEN RAISE EXCEPTION 'active leases claimed twice'; END IF; BEGIN PERFORM * FROM ops.claim_myc_capacity_emails(6); RAISE EXCEPTION 'limit greater than five accepted'; EXCEPTION WHEN OTHERS THEN IF position('INVALID_CLAIM_LIMIT' in sqlerrm)=0 THEN RAISE; END IF; END; SELECT * INTO v FROM email_claims ORDER BY signal_key LIMIT 1; IF v.signal_key IS NULL THEN RAISE EXCEPTION 'no claim'; END IF; END $claims$;\n"+
 "DO $payload$ DECLARE c record; BEGIN SELECT * INTO c FROM email_claims ORDER BY signal_key LIMIT 1; IF c.delivery_pk IS NULL OR c.email_subject_tag<>'MYC-CAPACITY-'||c.delivery_pk::text OR c.capacity_metrics IS NULL OR c.summary LIKE '%@%' OR c.capacity_metrics ? 'destination_ref' OR c.capacity_metrics ? 'source_pk' OR c.capacity_metrics ? 'raw_record' THEN RAISE EXCEPTION 'payload redaction/shape'; END IF; IF EXISTS(SELECT 1 FROM jsonb_each(c.capacity_metrics) e WHERE jsonb_typeof(e.value)<>'number') THEN RAISE EXCEPTION 'non-numeric metric'; END IF; END $payload$;\n"+
 "DO $completion$ DECLARE c record; r jsonb; v ops.alert_delivery_queue%rowtype; a ops.alert_instances%rowtype; BEGIN SELECT * INTO c FROM email_claims WHERE signal_key='MYC_DATABASE_CAPACITY_WARNING_250MIB'; BEGIN PERFORM ops.complete_myc_capacity_email(c.delivery_pk,c.claimed_at-interval '1 second',null,false,'NETWORK_TIMEOUT'); RAISE EXCEPTION 'stale ack accepted'; EXCEPTION WHEN OTHERS THEN IF position('STALE_OR_UNCLAIMED_DELIVERY' in sqlerrm)=0 THEN RAISE; END IF; END; BEGIN PERFORM ops.complete_myc_capacity_email(c.delivery_pk,c.claimed_at,null,true,null); RAISE EXCEPTION 'receipt-less SENT accepted'; EXCEPTION WHEN OTHERS THEN IF position('RECEIPT_REQUIRED_OR_INVALID' in sqlerrm)=0 THEN RAISE; END IF; END; BEGIN PERFORM ops.complete_myc_capacity_email(c.delivery_pk,c.claimed_at,null,false,'raw provider exception text'); RAISE EXCEPTION 'raw failure text accepted'; EXCEPTION WHEN OTHERS THEN IF position('INVALID_FAILURE_CLASS' in sqlerrm)=0 THEN RAISE; END IF; END; r:=ops.complete_myc_capacity_email(c.delivery_pk,c.claimed_at,null,false,'NETWORK_TIMEOUT'); SELECT * INTO v FROM ops.alert_delivery_queue WHERE delivery_pk=c.delivery_pk; IF r->>'delivery_status'<>'FAILED' OR v.last_error<>'NETWORK_TIMEOUT' OR v.attempt_count<>1 THEN RAISE EXCEPTION 'bounded failure update'; END IF; UPDATE ops.alert_delivery_queue SET last_attempt_at=now()-interval '16 minutes' WHERE delivery_pk=c.delivery_pk; SELECT * INTO c FROM ops.claim_myc_capacity_emails(1); IF c.delivery_pk IS NULL THEN RAISE EXCEPTION 'expired lease was not retryable'; END IF; r:=ops.complete_myc_capacity_email(c.delivery_pk,c.claimed_at,'SYNTHETIC-GMAIL-RECEIPT-001',true,null); SELECT * INTO v FROM ops.alert_delivery_queue WHERE delivery_pk=c.delivery_pk; SELECT * INTO a FROM ops.alert_instances WHERE alert_pk=v.alert_pk; IF r->>'delivery_status'<>'SENT' OR v.delivery_status<>'SENT' OR a.metadata#>>'{capacity_email_receipt,receipt_id}'<>'SYNTHETIC-GMAIL-RECEIPT-001' THEN RAISE EXCEPTION 'receipt-backed SENT'; END IF; r:=ops.complete_myc_capacity_email(c.delivery_pk,c.claimed_at,'SYNTHETIC-GMAIL-RECEIPT-001',true,null); IF r->>'idempotent'<>'true' OR r->>'delivery_status'<>'SENT' THEN RAISE EXCEPTION 'same receipt not idempotent'; END IF; BEGIN PERFORM ops.complete_myc_capacity_email(c.delivery_pk,c.claimed_at,'SYNTHETIC-GMAIL-RECEIPT-002',true,null); RAISE EXCEPTION 'conflicting receipt accepted'; EXCEPTION WHEN OTHERS THEN IF position('RECEIPT_CONFLICT' in sqlerrm)=0 THEN RAISE; END IF; END; END $completion$;\n"+
 "DO $retrycap$ DECLARE c record; r jsonb; v_id uuid; BEGIN SELECT * INTO c FROM email_claims WHERE signal_key='MYC_CAPACITY_METRICS_ARCHIVE_REQUIRED'; v_id:=c.delivery_pk; r:=ops.complete_myc_capacity_email(v_id,c.claimed_at,null,false,'RATE_LIMITED'); UPDATE ops.alert_delivery_queue SET last_attempt_at=now()-interval '16 minutes' WHERE delivery_pk=v_id; SELECT * INTO c FROM ops.claim_myc_capacity_emails(1); IF c.delivery_pk IS NULL OR c.delivery_pk<>v_id THEN RAISE EXCEPTION 'first retry not claimable'; END IF; r:=ops.complete_myc_capacity_email(v_id,c.claimed_at,null,false,'WORKER_ERROR'); UPDATE ops.alert_delivery_queue SET last_attempt_at=now()-interval '16 minutes' WHERE delivery_pk=v_id; SELECT * INTO c FROM ops.claim_myc_capacity_emails(1); IF c.delivery_pk IS NULL OR c.delivery_pk<>v_id THEN RAISE EXCEPTION 'third attempt not claimable'; END IF; r:=ops.complete_myc_capacity_email(v_id,c.claimed_at,null,false,'AUTH_UNAVAILABLE'); UPDATE ops.alert_delivery_queue SET last_attempt_at=now()-interval '16 minutes' WHERE delivery_pk=v_id; IF EXISTS(SELECT 1 FROM ops.claim_myc_capacity_emails(5) WHERE delivery_pk=v_id) THEN RAISE EXCEPTION 'attempt exhausted was claimed'; END IF; IF (SELECT delivery_status FROM ops.alert_delivery_queue WHERE delivery_pk=v_id)<>'FAILED' OR (SELECT attempt_count FROM ops.alert_delivery_queue WHERE delivery_pk=v_id)<>3 THEN RAISE EXCEPTION 'attempt exhaustion dropped/changed row'; END IF; END $retrycap$;\n"+
 "DO $preserve$ BEGIN IF EXISTS(SELECT 1 FROM email_fixture f JOIN ops.alert_delivery_queue q USING(delivery_pk) WHERE f.signal_key="+quote(notAllowed)+" AND (q.attempt_count<>0 OR q.delivery_status<>'READY')) THEN RAISE EXCEPTION 'non-capacity row was changed'; END IF; END $preserve$;\n"+
 "ROLLBACK; SELECT 'ROLLED_BACK';\n";
assert.match(psql(sql),/ROLLED_BACK/);

// A separate, narrow committed fixture is required for two PostgreSQL
// sessions to see the same claimable rows. Cleanup below is exact by run UUID.
const concurrencyId=randomUUID().toUpperCase();
const concurrentSignals=["MYC_DATABASE_CAPACITY_WARNING_250MIB","MYC_CAPACITY_DELIVERY_TEST"];
const ruleKeys=concurrentSignals.map((_,i)=>"ALT-ECON-"+concurrencyId.replaceAll("-","").slice(0,10)+"-"+i);
let setupAttempted=false,concurrencyPassed=false;
try {
  setupAttempted=true;
  const setup="BEGIN READ WRITE;\n"+workerSql+"\n"+
    "INSERT INTO ops.alert_routes(environment,owner_role,channel_type,destination_ref,verified,verified_at,verified_by,active) VALUES('TEST','founder','EMAIL','MYC_FOUNDER_CONNECTED_GMAIL_SELF',true,now(),"+quote("email-concurrency-"+concurrencyId)+",true);\n"+
    concurrentSignals.map((key,i)=>"INSERT INTO ops.alert_rule_catalog(alert_rule_key,source_signal_key,severity,owner_role,auto_incident,description,source_ref) VALUES("+quote(ruleKeys[i])+","+quote(key)+",'SEV2','founder',false,'Rollback cleanup concurrency fixture','MYC_CAPACITY_EMAIL_CONCURRENCY_TEST');").join("\n")+"\n"+
    "UPDATE config.system_settings SET setting_value='true'::jsonb,updated_at=now() WHERE setting_key='security_external_alert_delivery_enabled';\n"+
    concurrentSignals.map((key,i)=>"SELECT ops.ingest_alert_signal('TEST',"+quote(key)+","+quote(key)+",'SEV2',"+quote("Capacity email concurrency fixture "+i)+",1,'MYC_CAPACITY_EMAIL_CONCURRENCY_TEST',pg_catalog.jsonb_build_object('email_concurrency_run',"+quote(concurrencyId)+"),now());").join("\n")+"\n"+
    "COMMIT;\n"+
    "SELECT coalesce(jsonb_agg(jsonb_build_object('alert_pk',a.alert_pk,'delivery_pk',q.delivery_pk,'signal_key',a.signal_key) ORDER BY a.signal_key),'[]'::jsonb)::text FROM ops.alert_instances a JOIN ops.alert_delivery_queue q ON q.alert_pk=a.alert_pk WHERE a.metadata->>'email_concurrency_run'="+quote(concurrencyId)+";";
  const fixtures=JSON.parse(psql(setup).split(/\r?\n/).filter(Boolean).at(-1));
  assert.equal(fixtures.length,2); assert.deepEqual(fixtures.map(x=>x.signal_key).sort(),[...concurrentSignals].sort());
  const connA=startPsql("BEGIN; SET LOCAL ROLE service_role; SELECT pg_catalog.json_build_object('delivery_pk',delivery_pk,'claimed_at',claimed_at)::text FROM ops.claim_myc_capacity_emails(1); SELECT pg_catalog.pg_sleep(3); COMMIT;\n");
  let claimA;
  try {
    claimA=await connA.firstLine;
    const second=readJson("SET ROLE service_role; SELECT coalesce(pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object('delivery_pk',delivery_pk,'claimed_at',claimed_at)),'[]'::jsonb)::text FROM ops.claim_myc_capacity_emails(2); RESET ROLE;");
    const claimB=Array.isArray(second)?second:JSON.parse(String(second));
    await connA.done;
    assert.ok(claimA?.delivery_pk); assert.equal(claimB.length,1);
    assert.notEqual(claimB[0].delivery_pk,claimA.delivery_pk,"concurrent claims overlapped a locked delivery");
    assert.ok(fixtures.some(f=>f.delivery_pk===claimA.delivery_pk)); assert.ok(fixtures.some(f=>f.delivery_pk===claimB[0].delivery_pk));
    concurrencyPassed=true;
  } catch(error) {
    connA.kill(); await connA.done.catch(()=>{}); throw error;
  }
} finally {
  if(setupAttempted) {
    const restoreGate=initial.flags[3] ? "true" : "false";
    const cleanup="BEGIN READ WRITE;\n"+
      "UPDATE config.system_settings SET setting_value="+quote(restoreGate)+"::jsonb,updated_at=now() WHERE setting_key='security_external_alert_delivery_enabled';\n"+
      "DELETE FROM ops.alert_delivery_queue WHERE alert_pk IN (SELECT alert_pk FROM ops.alert_instances WHERE metadata->>'email_concurrency_run'="+quote(concurrencyId)+");\n"+
      "DELETE FROM ops.alert_occurrences WHERE alert_pk IN (SELECT alert_pk FROM ops.alert_instances WHERE metadata->>'email_concurrency_run'="+quote(concurrencyId)+");\n"+
      "DELETE FROM ops.alert_instances WHERE metadata->>'email_concurrency_run'="+quote(concurrencyId)+";\n"+
      ruleKeys.map(k=>"DELETE FROM ops.alert_rule_catalog WHERE alert_rule_key="+quote(k)+";").join("\n")+"\n"+
      "DELETE FROM ops.alert_routes WHERE environment='TEST' AND owner_role='founder' AND channel_type='EMAIL' AND destination_ref='MYC_FOUNDER_CONNECTED_GMAIL_SELF' AND verified_by="+quote("email-concurrency-"+concurrencyId)+";\n"+
      "DROP FUNCTION IF EXISTS ops.complete_myc_capacity_email(uuid,timestamptz,text,boolean,text); DROP FUNCTION IF EXISTS ops.claim_myc_capacity_emails(integer);\nCOMMIT;\n";
    psql(cleanup);
  }
}
assert.ok(concurrencyPassed);

const after=readJson("select jsonb_build_object("+
 "'rows',(select count(*) from ops.shadow_import_rows),"+
 "'shadow_hash',coalesce((select sum(('x'||substr(md5(to_jsonb(r)::text),1,16))::bit(64)::bigint)::text from ops.shadow_import_rows r),'0'),"+
 "'sessions',(select count(*) from ops.shadow_import_sessions),"+
 "'queue_count',(select count(*) from ops.alert_delivery_queue),"+
 "'queue_hash',coalesce((select md5(coalesce(string_agg(q.delivery_pk::text||':'||q.delivery_status||':'||q.attempt_count||':'||coalesce(q.last_attempt_at::text,'')||':'||coalesce(q.last_error,''),'|' order by q.delivery_pk),'')) from ops.alert_delivery_queue q),''),"+
 "'alert_count',(select count(*) from ops.alert_instances),"+
 "'alert_hash',coalesce((select md5(coalesce(string_agg(a.alert_pk::text||':'||a.status||':'||a.occurrence_count||':'||coalesce(a.metadata::text,''),'|' order by a.alert_pk),'')) from ops.alert_instances a),''),"+
 "'routes',(select count(*) from ops.alert_routes),"+
 "'rules',(select count(*) from ops.alert_rule_catalog),"+
 "'flags',(select jsonb_build_array(config.setting_is_true('business_master_apply_enabled'),config.setting_is_true('migration_target_apply_enabled'),config.setting_is_true('production_cutover_approved'),config.setting_is_true('security_external_alert_delivery_enabled'))),"+
 "'cron3',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobname='meyou-connect-observability-refresh'),"+
 "'cron11',(select jsonb_build_object('id',jobid,'name',jobname,'schedule',schedule,'command',command,'active',active) from cron.job where jobid=11 and jobname='myc_datahub_shadow_import_5min'),"+
 "'worker_functions',(select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='ops' and p.proname in ('claim_myc_capacity_emails','complete_myc_capacity_email'))"+
 ")::text;");
for(const k of ["rows","shadow_hash","sessions","queue_count","queue_hash","alert_count","alert_hash","routes","rules","worker_functions"]) assert.equal(after[k],initial[k],"rollback changed "+k);
assert.deepEqual(after.flags,initial.flags); assert.deepEqual(after.cron3,initial.cron3); assert.deepEqual(after.cron11,initial.cron11);
process.stdout.write(JSON.stringify({suite:"myc-capacity-email.integration",status:"PASS",target:{container:TARGET,networkMode,publishedPorts:false},rollback:true,checks:["service-only ACL and postgres owner/search_path","gate false blocks claim","exact founder EMAIL route + TEST capacity whitelist","numeric redacted payload","15-minute retry lease","stale ack rejected","bounded retry error classes and attempt cap","receipt-backed SENT and idempotent receipt ack","two-session FOR UPDATE SKIP LOCKED disjoint claims","non-capacity delivery untouched","post-cleanup DB/queue/alert/route/rule/gate/cron readback"],elapsedMs:Date.now()-started},null,2)+"\n");
