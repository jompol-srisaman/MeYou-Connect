import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { stripTypeScriptTypes } from 'node:module';
import { webcrypto } from 'node:crypto';
import vm from 'node:vm';

const path = new URL('../supabase/functions/datahub-shadow-import/index.ts', import.meta.url);
let source = readFileSync(path, 'utf8').replace(/^import .*;\r?\n/m, '');
// OAuth is external to the importer; fixtures never load production credentials.
source = source.replace(/async function googleAccessToken\(\) \{[\s\S]*?\nasync function gget/, 'async function googleAccessToken() { return "fixture-token"; }\nasync function gget');
const compiled = stripTypeScriptTypes(source + '\nglobalThis.fixtureENT = ENT;', {mode:'strip'});

function fixture(options = {}) {
  let handler, entity;
  const calls = [];
  const saved = new Map();
  const state = { name:'fixture-a', baseline:[], ...options };
  const context = vm.createContext({
    TextEncoder, Uint8Array, URLSearchParams, Request, Response, crypto:webcrypto, btoa, atob,
    console:{ warn() {} },
    Deno:{env:{get(k){return k==='SUPABASE_SERVICE_ROLE_KEY'?'fixture-key':undefined;}}, serve(f){handler=f;}},
    fetch:async(url, init={})=>{
      const u=String(url); const body=init.body?JSON.parse(init.body):null;
      calls.push({url:u,body});
      const res=(v, status=200)=>Response.json(v,{status});
      if(u.includes('/rpc/verify_shadow_import_token')) return res(true);
      if(u.includes('/rpc/get_shadow_import_baseline')) {
        if(state.baselineFailure) return res({message:'baseline unavailable'},503);
        return res(Object.hasOwn(state,'baselineResponse')?state.baselineResponse:{baseline_session_id:state.baselineSession??null,rows:state.baseline,entity_scope:body.p_entities});
      }
      if(u.includes('sheets.googleapis.com') && !u.includes('/values/')) return res({properties:{title:'fixture'},sheets:[{properties:{title:'01_Candidate'}}]});
      if(u.includes('/values/')) {
        const headers=Object.values(entity.fields).map(v=>v[0]);
        if(state.missingHeader) headers.shift();
        const row=Object.keys(entity.fields).map(k=>k==='candidate_id'?'MYC-C-000001':k==='nickname'?state.name:null);
        const sourceRows=Array.from({length:state.rows??1},(_,i)=>{const r=[...row];r[0]=state.duplicatePk?'MYC-C-000001':`MYC-C-${String(i+1).padStart(6,'0')}`;if(i>0)r[1]=`fixture-row-${i+1}`;return r;});
        return res({values:[headers,...(state.reverseRows?sourceRows.reverse():sourceRows)]});
      }
      if(u.includes('/shadow_import_sessions?') && u.includes('source_revision')) {
        if(state.historyFailure) return res({},503);
        const revision=new URL(u).searchParams.get('source_revision').slice(3);
        return res(saved.has(revision)?[{session_id:saved.get(revision),status:state.existingStatus??'VALIDATED'}]:[]);
      }
      if(u.includes('/rpc/open_shadow_import_session')) {
        if(state.openError) return res({message:state.openError},409);
        state.staged=[];
        const id=`fixture-session-${saved.size+1}`;saved.set(body.p_source_revision,id);return res(id);
      }
      if(u.includes('/shadow_import_sessions?')) return res([{metadata:{guard_applied:state.noGuard?undefined:'v4',database_bytes:100000000}}]);
      if(u.includes('/rpc/stage_shadow_row')) { (state.staged??=[]).push(body); return res('fixture-row'); }
      if(u.includes('/rpc/validate_shadow_session')) {
        const sess=[...saved.values()].at(-1);
        state.baseline=(state.staged??[]).map(x=>({entity_key:x.p_entity_key,source_pk:x.p_source_pk,source_row_number:x.p_source_row_number,normalized_record:x.p_normalized_record}));
        state.baselineSession=sess;
        return res({invalid:state.invalid??0,skipped:0,valid:1});
      }
      if(u.includes('/shadow_import_rows?')) return res([]);
      throw Error(`Unexpected fixture request: ${u}`);
    },
  });
  vm.runInContext(compiled,context);entity=context.fixtureENT.Candidate;
  return {state,calls,saved, async run(body={mode:'import',entities:['Candidate'],dryRun:false}) {
    const response=await handler(new Request('https://fixture.invalid',{method:'POST',headers:{'x-myc-invoke-token':'fixture'},body:JSON.stringify(body)}));
    return {status:response.status, body:await response.json()};
  }};
}
const writes=f=>f.calls.filter(c=>c.url.includes('/rpc/')&&!c.url.includes('verify_shadow_import_token')&&!c.url.includes('get_shadow_import_baseline'));

test('default import is dry-run with no writes',async()=>{const f=fixture();const r=await f.run({mode:'import',entities:['Candidate']});assert.equal(r.body.dryRun,true);assert.equal(writes(f).length,0);});
test('same source over 288 five-minute ticks creates only one snapshot',async()=>{const f=fixture();for(let i=0;i<288;i++)assert.equal((await f.run()).body.ok,true);assert.equal(f.saved.size,1);assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,1);});
test('changed source creates a distinct content hash',async()=>{const f=fixture();await f.run();f.state.name='fixture-b';await f.run();assert.equal(f.saved.size,2);assert.ok([...f.saved.keys()].every(v=>/^sha256:[0-9a-f]{64}$/.test(v)));});
test('duplicate entity names do not duplicate staged rows',async()=>{const f=fixture();await f.run({mode:'import',entities:['Candidate','Candidate'],dryRun:false});assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,1);});
test('unknown entity rejects before writes',async()=>{const f=fixture();assert.equal((await f.run({mode:'import',entities:['TYPO'],dryRun:false})).status,400);assert.equal(writes(f).length,0);});
test('missing source schema blocks all writes',async()=>{const f=fixture({missingHeader:true});assert.equal((await f.run()).status,409);assert.equal(writes(f).length,0);});
test('history read error fails closed',async()=>{const f=fixture({historyFailure:true});assert.equal((await f.run()).status,503);assert.equal(writes(f).length,0);});
test('over-budget snapshot fails before any writes',async()=>{const f=fixture({rows:1001});assert.equal((await f.run()).status,503);assert.equal(writes(f).length,0);});
test('unpatched database cannot stage any rows',async()=>{const f=fixture({noGuard:true});const r=await f.run();assert.equal(r.status,503);assert.match(r.body.error,/GUARD_NOT_INSTALLED/);assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,0);});
test('database capacity and retention stops propagate without staging',async()=>{for(const error of ['SHADOW_CAPACITY_STOP','SHADOW_RETENTION_ARCHIVE_REQUIRED']){const f=fixture({openError:error});assert.equal((await f.run()).status,503);assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,0);}});
test('concurrent duplicate is handled without staging',async()=>{const f=fixture({openError:'SHADOW_SNAPSHOT_ALREADY_EXISTS'});assert.equal((await f.run()).body.skipped,'CONCURRENT_DUPLICATE');assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,0);});
test('incomplete prior snapshot requires review',async()=>{const f=fixture();await f.run();f.state.existingStatus='STAGED';assert.equal((await f.run()).status,409);assert.equal(f.saved.size,1);});
test('invalid validation is not reported as success',async()=>{const f=fixture({invalid:1});assert.equal((await f.run()).body.ok,false);});
test('matching latest baseline skips with no write calls',async()=>{const f=fixture();await f.run();f.calls.length=0;const r=await f.run();assert.equal(r.body.skipped,'UNCHANGED_SOURCE');assert.equal(writes(f).length,0);});
test('one changed row stages only that row',async()=>{const f=fixture({rows:2});await f.run();f.calls.length=0;f.state.name='changed';const r=await f.run();assert.equal(r.body.ok,true);assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,1);});
test('new row stages only the new row',async()=>{const f=fixture();await f.run();f.calls.length=0;f.state.rows=2;const r=await f.run();assert.equal(r.body.ok,true);assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,1);});
test('removed source row requires review without writes',async()=>{const f=fixture({rows:2});await f.run();f.calls.length=0;f.state.rows=1;const r=await f.run();assert.equal(r.body.error,'SOURCE_DELETION_REQUIRES_REVIEW');assert.equal(writes(f).length,0);});
test('duplicate source primary keys reject before writes',async()=>{const f=fixture({duplicatePk:true,rows:2});const r=await f.run();assert.equal(r.body.error,'DUPLICATE_SOURCE_PK');assert.equal(writes(f).length,0);});
test('baseline read failure fails closed',async()=>{const f=fixture({baselineFailure:true});assert.equal((await f.run()).status,503);assert.equal(writes(f).length,0);});
test('row position changes are treated as changed rows',async()=>{const f=fixture({rows:2});await f.run();f.state.reverseRows=true;f.calls.length=0;const r=await f.run();assert.equal(r.body.ok,true);assert.equal(f.calls.filter(c=>c.url.includes('/rpc/stage_shadow_row')).length,2);});
test('canonical object key order does not create a delta',async()=>{const f=fixture();await f.run();f.calls.length=0;const old=f.state.baseline[0];f.state.baseline=[{...old,normalized_record:Object.fromEntries(Object.entries(old.normalized_record).reverse())}];const r=await f.run();assert.equal(r.body.skipped,'UNCHANGED_SOURCE');assert.equal(writes(f).length,0);});
test('malformed baseline shape fails closed',async()=>{for(const baselineResponse of [null,{}, {baseline_session_id:null,rows:null,entity_scope:['Candidate']}]){const f=fixture({baselineResponse});const r=await f.run();assert.equal(r.body.error,'SHADOW_BASELINE_INVALID');assert.equal(writes(f).length,0);}});
test('baseline entity scope and row entities must match request',async()=>{for(const baselineResponse of [{baseline_session_id:null,rows:[],entity_scope:[]},{baseline_session_id:null,rows:[{entity_key:'Client',source_pk:'x',source_row_number:2,normalized_record:{client_id:'x'}}],entity_scope:['Candidate']}]){const f=fixture({baselineResponse});const r=await f.run();assert.equal(r.body.error,'SHADOW_BASELINE_INVALID');assert.equal(writes(f).length,0);}});
test('duplicate or malformed baseline row fails closed',async()=>{const row={entity_key:'Candidate',source_pk:'MYC-C-000001',source_row_number:2,normalized_record:{candidate_id:'MYC-C-000001'}};for(const rows of [[row,row],[{...row,source_row_number:0}],[{...row,normalized_record:{candidate_id:'other'}}]]){const f=fixture({baselineResponse:{baseline_session_id:null,rows,entity_scope:['Candidate']}});const r=await f.run();assert.equal(r.body.error,'SHADOW_BASELINE_INVALID');assert.equal(writes(f).length,0);}});
test('oversized baseline fails closed',async()=>{const f=fixture({baselineResponse:{baseline_session_id:null,rows:Array.from({length:1001},(_,i)=>({entity_key:'Candidate',source_pk:`p${i}`,source_row_number:i+2,normalized_record:{candidate_id:`p${i}`}})),entity_scope:['Candidate']}});const r=await f.run();assert.equal(r.body.error,'SHADOW_BASELINE_INVALID');assert.equal(writes(f).length,0);});
test('baseline over two mebibytes fails closed',async()=>{const rows=Array.from({length:900},(_,i)=>({entity_key:'Candidate',source_pk:`p${i}`,source_row_number:i+2,normalized_record:{candidate_id:`p${i}`,nickname:'x'.repeat(3000)}}));const f=fixture({baselineResponse:{baseline_session_id:'fixture-baseline',rows,entity_scope:['Candidate']}});const r=await f.run();assert.equal(r.body.error,'SHADOW_BASELINE_INVALID');assert.equal(writes(f).length,0);});
test('null initial baseline with exact entity scope is valid',async()=>{const f=fixture({baselineResponse:{baseline_session_id:null,rows:[],entity_scope:['Candidate']}});const r=await f.run({mode:'import',entities:['Candidate'],dryRun:true});assert.equal(r.body.dryRun,true);assert.equal(r.body.input_rows,1);});
