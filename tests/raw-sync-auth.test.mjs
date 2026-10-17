import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';

const source=readFileSync(new URL('../supabase/functions/raw-datahub-sync/index.ts',import.meta.url),'utf8').replace(/\r\n/g,'\n').replace(/^import .*;\n/m,'');
const js=stripTypeScriptTypes(source+'\nglobalThis.testHandler=handleRawSyncRequest;',{mode:'strip'});

function fixture(validToken){
  let handler;const calls=[];
  const context=vm.createContext({
    Deno:{env:{get(name){return name==='SUPABASE_SERVICE_ROLE_KEY'?'fixture-service-key':undefined;}},serve(fn){handler=fn;}},
    fetch:async(url,init={})=>{calls.push({url:String(url),init});return validToken==='rpc-error'?new Response('fixture unavailable',{status:503}):Response.json(validToken);},
    Response,URLSearchParams,TextEncoder,console,btoa,atob,
  });
  vm.runInContext(js,context);
  return{handler,calls};
}

function request({token,body}){
  let parsed=false;
  const headers=new Headers();if(token!==undefined)headers.set('x-myc-invoke-token',token);
  return{value:{method:'POST',headers,async json(){parsed=true;return body??{};}},wasParsed:()=>parsed};
}

test('missing and invalid invoke tokens reject health, replay, and default sync before body parse or Sheets access',async()=>{
  for(const mode of ['health','replayRawIds',undefined]){
    for(const token of [undefined,'bad-fixture-token']){
      const f=fixture(false),req=request({token,body:mode?{mode}:{}});
      const response=await f.handler(req.value);
      assert.equal(response.status,403,`${mode??'default'} token=${token?'invalid':'missing'}`);
      assert.equal(req.wasParsed(),false);assert.equal(f.calls.length,token?1:0);
      assert.ok(f.calls.every(c=>!c.url.includes('sheets.googleapis.com')));
      assert.deepEqual(await response.json(),{ok:false,error:'FORBIDDEN'});
      if(token)assert.match(f.calls[0].url,/\/rpc\/verify_shadow_import_token$/);
    }
  }
});

test('verifier RPC failure fails closed before body parsing or Sheets access',async()=>{
  const f=fixture('rpc-error'),req=request({token:'fixture-token',body:{}});
  const response=await f.handler(req.value);
  assert.equal(response.status,403);assert.equal(req.wasParsed(),false);assert.equal(f.calls.length,1);
});

test('verified invoke token is accepted and only then body parsing proceeds',async()=>{
  const f=fixture(true),req=request({token:'valid-fixture-token',body:{mode:'health'}});
  const response=await f.handler(req.value);
  assert.equal(req.wasParsed(),true);
  // Fixture deliberately has no Google credentials; reaching the normal handler returns its expected dependency error.
  assert.equal(response.status,503);
  assert.ok(f.calls.every(c=>!c.url.includes('sheets.googleapis.com')));
  assert.ok(f.calls.some(c=>c.url.includes('/rpc/verify_shadow_import_token')));
});
