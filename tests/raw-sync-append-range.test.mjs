import test from 'node:test';
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFileSync} from 'node:fs';
import {stripTypeScriptTypes} from 'node:module';
const source=readFileSync(new URL('../supabase/functions/raw-datahub-sync/index.ts',import.meta.url),'utf8').replace(/^import .*;\n/m,'');
const js=stripTypeScriptTypes(source+'\nglobalThis.testRange=verifyAppendRange;globalThis.testAppend=appendSheetRows;', {mode:'strip'});
function fixture(range){let url;const ctx=vm.createContext({Deno:{env:{get(){}},serve(){}},fetch:async(u)=>{url=String(u);return Response.json({updates:{updatedRange:range}});},Response,URLSearchParams,TextEncoder,console,btoa,atob});vm.runInContext(js,ctx);return{ctx,getUrl:()=>url};}
test('canonical range accepted with exact dimensions',()=>{fixture().ctx.testRange("'19_Raw_Input_Log'!A5001:X5204",204,24);});
test('misplaced L:AI rejects despite relative read-back equality',()=>{assert.throws(()=>fixture().ctx.testRange("'19_Raw_Input_Log'!L4556:AI4759",204,24),/MISALIGNED/);});
test('wrong row count, width, tab and missing range reject',()=>{for(const range of ["19_Raw_Input_Log!A5001:W5204","19_Raw_Input_Log!A5001:X5203","Other!A5001:X5204",""]){assert.throws(()=>fixture().ctx.testRange(range,204,24));}});
test('append explicitly anchors header and refuses shifted provider response',async()=>{const f=fixture("'19_Raw_Input_Log'!L4556:AI4556");await assert.rejects(()=>f.ctx.testAppend('fixture-token',[Array(24).fill('')]),/MISALIGNED/);assert.match(decodeURIComponent(f.getUrl()),/19_Raw_Input_Log!A1:X1/);});
test('append returns verified canonical range',async()=>{const f=fixture("'19_Raw_Input_Log'!A5001:X5001");assert.equal(await f.ctx.testAppend('fixture-token',[Array(24).fill('')]),"'19_Raw_Input_Log'!A5001:X5001");});
