const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const host=process.env.FIRESTORE_EMULATOR_HOST;const project='demo-micomunidad-project-dates';
if(host&&!/^127\.0\.0\.1:\d+$/.test(host))throw Error('Local emulator only');
test('optional project dates preserve legacy data and enforce admin/types/order',{skip:!host},async t=>{
 const {initializeApp,deleteApp}=require('firebase-admin/app');const {getFirestore,Timestamp}=require('firebase-admin/firestore');
 const app=initializeApp({projectId:project},'project-dates-local');const db=getFirestore(app);
 const base=`http://${host}/v1/projects/${project}/databases/(default)/documents`;
 t.after(async()=>{await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,{method:'DELETE'});await db.terminate();await deleteApp(app);});
 const rules=await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({rules:{files:[{name:'firestore.rules',content:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}]}})});assert.equal(rules.status,200,await rules.text());
 function token(uid){const e=v=>Buffer.from(JSON.stringify(v)).toString('base64url'),now=Math.floor(Date.now()/1000);return `${e({alg:'none',typ:'JWT'})}.${e({sub:uid,user_id:uid,iss:`https://securetoken.google.com/${project}`,aud:project,iat:now,exp:now+3600,auth_time:now,firebase:{sign_in_provider:'password'}})}.`;}
 async function edit(doc,uid,patch={text:{stringValue:'Updated'}},stamp=true){const r=await fetch(base+':commit',{method:'POST',headers:{'Content-Type':'application/json',...(uid?{Authorization:`Bearer ${token(uid)}`}:{})},body:JSON.stringify({writes:[{update:{name:`projects/${project}/databases/(default)/documents/${doc}`,fields:patch},updateMask:{fieldPaths:Object.keys(patch)},...(stamp?{updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}:{})}]})});return {status:r.status,body:await r.json()};}

 await db.doc('users/admin').set({role:'admin',approvalStatus:'aprobado'});
 await db.doc('users/neighbor').set({role:'vecino',approvalStatus:'aprobado'});
 const start={timestampValue:'2026-11-01T05:00:00Z'},end={timestampValue:'2026-11-30T05:00:00Z'};
 const baseFields={title:{stringValue:'Fictional'},description:{stringValue:'Description'},location:{stringValue:''},progress:{integerValue:'0'},status:{stringValue:'pendiente'},isTrashed:{booleanValue:false},createdBy:{stringValue:'admin'}};
 async function commit(id,fields,create=false,actor='admin',removed=[]){
  const r=await fetch(base+':commit',{method:'POST',headers:{'Content-Type':'application/json',Authorization:`Bearer ${token(actor)}`},body:JSON.stringify({writes:[{update:{name:`projects/${project}/databases/(default)/documents/projects/${id}`,fields},updateMask:{fieldPaths:[...Object.keys(fields),...removed]},updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'},...(create?[{fieldPath:'createdAt',setToServerValue:'REQUEST_TIME'}]:[])]}]})});return {status:r.status,body:await r.json()};
 }
 for(const [id,dates] of [['legacy',{}],['start',{startDate:start}],['end',{expectedEndDate:end}],['both',{startDate:start,expectedEndDate:end}],['equal',{startDate:start,expectedEndDate:start}]])await t.test('create '+id,async()=>assert.equal((await commit(id,{...baseFields,...dates},true)).status,200));
 await t.test('invalid ordering, types, role and unrelated fields denied',async()=>{
  for(const fields of [{startDate:end,expectedEndDate:start},{startDate:{stringValue:'2026-11-01'}},{expectedEndDate:{integerValue:'1'}},{unknownDate:start}])assert.equal((await commit('bad',{...baseFields,...fields},true)).status,403);
  assert.equal((await commit('neighbor',{...baseFields,createdBy:{stringValue:'neighbor'},startDate:start},true,'neighbor')).status,403);
 });
 await t.test('legacy edits, date corrections and removal remain possible',async()=>{
  assert.equal((await commit('legacy',{startDate:start,expectedEndDate:end})).status,200);
  assert.equal((await commit('legacy',{startDate:end,expectedEndDate:start})).status,403);
  assert.equal((await commit('legacy',{},false,'admin',['startDate','expectedEndDate'])).status,200);
  assert.equal((await commit('legacy',{progress:{integerValue:'50'}})).status,200);
  const data=(await db.doc('projects/legacy').get()).data();assert(!Object.hasOwn(data,'startDate'));assert.equal(data.progress,50);
 });
});
