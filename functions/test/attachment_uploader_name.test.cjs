const test=require('node:test'),assert=require('node:assert/strict');
const {createAttachmentUploaderNameLookup}=require('../attachment_uploader_name');
class HttpsError extends Error{constructor(code,message){super(message);this.code=code;}}
function fixture(collection='projects',kind='photos'){
 const rows=new Map([
 ['users/viewer',{role:'vecino',approvalStatus:'aprobado'}],
 ['users/uploader',{nombre:'Persona ficticia',dni:'00000000',email:'private@example.com'}],
 [`${collection}/content`,{isTrashed:false,moderationStatus:'aprobado',status:'resuelto',createdBy:'another'}],
 [`${collection}/content/${kind}/file`,{uploadedBy:'uploader'}],
 ]);const reads=[];const db={doc:(path)=>({get:async()=>{reads.push(path);return {exists:rows.has(path),data:()=>rows.get(path)};}})};
 return {rows,reads,call:createAttachmentUploaderNameLookup({firestore:db,HttpsError}),request:{auth:{uid:'viewer'},data:{collection,documentId:'content',kind,attachmentId:'file'}}};
}
for(const [c,k] of [['projects','photos'],['projects','minutes'],['events','photos'],['events','minutes'],['reports','photos']]){
 test(`${c}/${k}: only current uploader name, no private fields or chosen user`,async()=>{
 const f=fixture(c,k);assert.deepEqual(await f.call(f.request),{name:'Persona ficticia'});
 f.rows.get('users/uploader').nombre='Nombre actualizado';assert.deepEqual(await f.call(f.request),{name:'Nombre actualizado'});
 await assert.rejects(f.call({...f.request,data:{...f.request.data,uploadedBy:'victim'}}),e=>e.code==='invalid-argument');
 f.rows.get(`${c}/content/${k}/file`).uploadedBy='../victim';assert.deepEqual(await f.call(f.request),{name:null});
 assert(!f.reads.includes('users/victim'));
 });
}
test('denies anonymous, unapproved, withdrawn, deleted parent/attachment and invalid references',async()=>{
 const f=fixture();await assert.rejects(f.call({data:f.request.data}),e=>e.code==='unauthenticated');
 for(const patch of [{role:'other'},{approvalStatus:'pendiente'},{profileWithdrawalInProgress:true}]){
 const p=f.rows.get('users/viewer');f.rows.set('users/viewer',{...p,...patch});await assert.rejects(f.call(f.request),e=>e.code==='permission-denied');f.rows.set('users/viewer',p);}
 for(const patch of [{documentId:'../private'},{kind:'identity'},{collection:'users'},{attachmentId:'x/y'}])await assert.rejects(f.call({...f.request,data:{...f.request.data,...patch}}),e=>e.code==='invalid-argument');
 f.rows.delete('projects/content/photos/file');await assert.rejects(f.call(f.request),e=>e.code==='not-found');
 f.rows.delete('projects/content');await assert.rejects(f.call(f.request),e=>e.code==='permission-denied');
});
test('archived projects and unapproved reports restricted; admin and report owner preserve access',async()=>{
 const p=fixture();p.rows.get('projects/content').isTrashed=true;await assert.rejects(p.call(p.request),e=>e.code==='permission-denied');p.rows.get('users/viewer').role='admin';assert.deepEqual(await p.call(p.request),{name:'Persona ficticia'});
 const f=fixture('reports');f.rows.get('reports/content').moderationStatus='pendiente';await assert.rejects(f.call(f.request),e=>e.code==='permission-denied');f.rows.get('reports/content').createdBy='viewer';assert.deepEqual(await f.call(f.request),{name:'Persona ficticia'});
});
test('missing uploader and missing name never invent personal information',async()=>{
 const f=fixture();f.rows.delete('users/uploader');assert.deepEqual(await f.call(f.request),{name:null});f.rows.get('projects/content/photos/file').uploadedBy=null;assert.deepEqual(await f.call(f.request),{name:null});
});
