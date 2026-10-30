const {test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs');const path=require('node:path');
const host=process.env.FIRESTORE_EMULATOR_HOST;const project='demo-micomunidad-comment-edit';
if(host&&!/^127\.0\.0\.1:\d+$/.test(host))throw Error('Local emulator only');
test('only approved comment owners can update text, preserving identity and parent restrictions',{skip:!host},async t=>{
 const {initializeApp,deleteApp}=require('firebase-admin/app');const {getFirestore,Timestamp}=require('firebase-admin/firestore');
 const app=initializeApp({projectId:project},'comment-edit-local');const db=getFirestore(app);
 const base=`http://${host}/v1/projects/${project}/databases/(default)/documents`;
 t.after(async()=>{await fetch(`http://${host}/emulator/v1/projects/${project}/databases/(default)/documents`,{method:'DELETE'});await db.terminate();await deleteApp(app);});
 const rules=await fetch(`http://${host}/emulator/v1/projects/${project}:securityRules`,{method:'PUT',headers:{'Content-Type':'application/json'},body:JSON.stringify({rules:{files:[{name:'firestore.rules',content:fs.readFileSync(path.join(__dirname,'../../firestore.rules'),'utf8')}]}})});assert.equal(rules.status,200,await rules.text());
 function token(uid){const e=v=>Buffer.from(JSON.stringify(v)).toString('base64url'),now=Math.floor(Date.now()/1000);return `${e({alg:'none',typ:'JWT'})}.${e({sub:uid,user_id:uid,iss:`https://securetoken.google.com/${project}`,aud:project,iat:now,exp:now+3600,auth_time:now,firebase:{sign_in_provider:'password'}})}.`;}
 async function edit(doc,uid,patch={text:{stringValue:'Updated'}},stamp=true){const r=await fetch(base+':commit',{method:'POST',headers:{'Content-Type':'application/json',...(uid?{Authorization:`Bearer ${token(uid)}`}:{})},body:JSON.stringify({writes:[{update:{name:`projects/${project}/databases/(default)/documents/${doc}`,fields:patch},updateMask:{fieldPaths:Object.keys(patch)},...(stamp?{updateTransforms:[{fieldPath:'updatedAt',setToServerValue:'REQUEST_TIME'}]}:{})}]})});return {status:r.status,body:await r.json()};}
 for(const [uid,role,status] of [['owner','vecino','aprobado'],['other','vecino','aprobado'],['admin','admin','aprobado'],['pending','vecino','pendiente'],['withdrawn','vecino','retirado']])await db.doc('users/'+uid).set({role,approvalStatus:status,nombre:'Fictional'});
 for(const collection of ['projects','events','reports'])await t.test(collection,async()=>{
  const parent=db.doc(collection+'/parent');await parent.set({isTrashed:false,moderationStatus:'aprobado',status:'resuelto'});
  const ref=parent.collection('comments').doc('comment');const original={text:'Original',authorId:'owner',authorName:'Fictional',createdAt:Timestamp.fromMillis(1000)};await ref.set(original);
  for(const actor of [null,'other','admin','pending','withdrawn'])assert.equal((await edit(ref.path,actor)).status,403);
  assert.equal((await edit(ref.path,'owner')).status,200);
  let data=(await ref.get()).data();assert.equal(data.text,'Updated');assert.equal(data.authorId,'owner');assert.deepEqual(data.createdAt,original.createdAt);
  for(const patch of [{text:{stringValue:''}},{text:{stringValue:'x'.repeat(1001)}},{text:{stringValue:'Changed'},authorId:{stringValue:'admin'}},{text:{stringValue:'Changed'},authorName:{stringValue:'Other'}},{text:{stringValue:'Changed'},createdAt:{timestampValue:new Date().toISOString()}},{text:{stringValue:'Changed'},extra:{booleanValue:true}}])assert.equal((await edit(ref.path,'owner',patch)).status,403);
  assert.equal((await edit(ref.path,'owner',{text:{stringValue:'No timestamp'}},false)).status,403);
  await parent.update(collection==='projects'?{isTrashed:true}:collection==='reports'?{moderationStatus:'rechazado'}:{deletionInProgress:true});
  assert.equal((await edit(ref.path,'owner')).status,403);
  await parent.delete();assert.equal((await edit(ref.path,'owner')).status,403);
 });
 await db.doc('projects/admin-parent').set({isTrashed:false});await db.doc('projects/admin-parent/comments/own').set({text:'Original',authorId:'admin',authorName:'Fictional',createdAt:Timestamp.fromMillis(1000)});assert.equal((await edit('projects/admin-parent/comments/own','admin')).status,200);
});
