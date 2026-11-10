import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { randomUUID } from 'node:crypto';
const workdir=process.env.LIYA_LOCAL_WORKDIR;
if (!workdir || process.env.LIYA_LOCAL_TESTS !== '1') throw new Error('Set LIYA_LOCAL_WORKDIR and LIYA_LOCAL_TESTS=1 for an isolated test project');
const config = JSON.parse(execFileSync('npx',['--no-install','supabase','status','--workdir',workdir,'-o','json'], {encoding:'utf8',env:process.env,stdio:['ignore','pipe','pipe']}));
const base=config.API_URL, anon=config.ANON_KEY, service=config.SERVICE_ROLE_KEY;
if (!base || !anon || !service) throw new Error('Local Supabase API credentials unavailable');
const apiURL = new URL(base);
if (apiURL.hostname !== '127.0.0.1' || apiURL.port !== '55321') throw new Error('Refusing a non-isolated Supabase API endpoint');
async function request(path, {method='GET',token=anon,body,prefer,apikey=anon}={}) {
  const headers={apikey,Authorization:`Bearer ${token}`};
  if (body !== undefined) headers['Content-Type']='application/json';
  if(prefer)headers.Prefer=prefer;
  const response=await fetch(base+path,{method,headers,body:body === undefined ? undefined: JSON.stringify(body)});
  const raw=await response.text(); let data; try {data=JSON.parse(raw)} catch {data=raw}
  return {status:response.status,data};
}
async function ok(path,options={}) {const r=await request(path,options); if(r.status<200 || r.status>=300) throw new Error(`${options.method||'GET'} ${path} failed (${r.status}): ${JSON.stringify(r.data).slice(0,400)}`); return r.data;}
async function rejected(path,options={}) {const r=await request(path,options); assert.ok(r.status===401||r.status===403 || (r.status===400 && /not.?found|object.?not.?found/i.test(JSON.stringify(r.data))),`Expected access denial, got ${r.status}: ${JSON.stringify(r.data)}`);}
function sql(query) {return execFileSync('docker',['exec','supabase_db_liya-supabase-integration','psql','-U','postgres','-d','postgres','-tA','-v','ON_ERROR_STOP=1','-c',query],{encoding:'utf8',stdio:['ignore','pipe','pipe']}).trim();}
const pw='LiyaTestOnly-8nF3c4@';
async function newUser(label){
 const email=`liya-${label}-${randomUUID()}@example.test`;
 const info=await ok('/auth/v1/admin/users',{method:'POST',token:service,apikey:service,body:{email,password:pw,email_confirm:true}});
 const session=await ok('/auth/v1/token?grant_type=password',{method:'POST',body:{email,password:pw}});
 assert.ok(info.id===session.user.id); return {id:info.id,token:session.access_token};
}
for(const id of ['liya-user-media','liya-example-media']) { const r=await request('/storage/v1/bucket',{method:'POST',token:service,apikey:service,body:{id,name:id,public:false}}); if (r.data?.code!=='BucketAlreadyExists' && r.status!==409 && (r.status<200||r.status>=300)) throw new Error(`bucket setup failed: ${r.status} ${JSON.stringify(r.data)}`); }
assert.equal(sql("select liya_social_private.set_curated_hidden('example-video-001',false,'local-reviewer')"),'t');
assert.equal(sql("select liya_social_private.set_curated_starter_hidden('example-video-001',0,false,'local-reviewer')"),'t');
const a=await newUser('a'), b=await newUser('b');
for(const [u,name] of [[a,'Alice'],[b,'Bob']]) {
 await ok('/rest/v1/liya_people?on_conflict=id',{method:'POST',token:u.token,prefer:'resolution=merge-duplicates,return=representation',body:{id:u.id,display_name:name,signature:'local test',avatar_path:null}});
 const pending=await ok('/rest/v1/rpc/liya_my_profile_submission',{method:'POST',token:u.token,body:{}});
 assert.equal(pending[0].display_name,name);
 assert.equal(sql(`select liya_social_private.review_content('profile','${u.id}',1,'approved','local-reviewer')`),'t');
}
await ok('/rest/v1/liya_people?on_conflict=id',{method:'POST',token:a.token,prefer:'resolution=merge-duplicates,return=representation',body:{id:a.id,display_name:'Alice revised',signature:'local test',avatar_path:null}});
assert.equal((await ok(`/rest/v1/liya_people?id=eq.${a.id}`,{token:b.token}))[0].display_name,'Alice');
assert.equal((await ok('/rest/v1/rpc/liya_my_profile_submission',{method:'POST',token:a.token,body:{}}))[0].display_name,'Alice revised');
assert.equal(sql(`select liya_social_private.review_content('profile','${a.id}',1,'approved','local-reviewer')`),'f');
assert.equal(sql(`select liya_social_private.review_content('profile','${a.id}',2,'approved','local-reviewer')`),'t');
assert.equal((await ok(`/rest/v1/liya_people?id=eq.${a.id}`,{token:b.token}))[0].display_name,'Alice revised');
const pid=randomUUID(), path=`${a.id}/social/${pid}/test.jpg`;
async function upload(bucket,file,who) {
 const r=await fetch(`${base}/storage/v1/object/${bucket}/${file}`,{method:'POST',headers:{apikey:who===service?service:anon,Authorization:`Bearer ${who}`,'content-type':'image/jpeg','x-upsert':'true'},body:Buffer.from('isolated test file')});
 if(!r.ok)throw new Error(`upload failed (${r.status}) ${await r.text()}`);
}
await upload('liya-user-media',path,a.token);
await ok('/rest/v1/liya_posts',{method:'POST',token:a.token,body:{id:pid,owner_id:a.id,body:'pending example',tags:[],media_paths:[path],media_kinds:['photo']}});
assert.equal((await ok(`/rest/v1/liya_posts?id=eq.${pid}`,{token:b.token})).length,0);
await rejected(`/storage/v1/object/sign/liya-user-media/${path}`,{method:'POST',token:b.token,body:{expiresIn:60}});
assert.equal(sql(`select liya_social_private.review_content('post','${pid}',1,'approved','local-reviewer')`),'t');
assert.equal((await ok(`/rest/v1/liya_posts?id=eq.${pid}`,{token:b.token})).length,1);
await ok(`/storage/v1/object/sign/liya-user-media/${path}`,{method:'POST',token:b.token,body:{expiresIn:60}});
const cid=randomUUID(); await ok('/rest/v1/liya_post_comments',{method:'POST',token:b.token,body:{id:cid,post_id:pid,owner_id:b.id,body:'comment test'}});
assert.equal((await ok(`/rest/v1/liya_post_comments?id=eq.${cid}`,{token:a.token})).length,0);
assert.equal(sql(`select liya_social_private.review_content('post_comment','${cid}',1,'approved','local-reviewer')`),'t');
assert.equal((await ok(`/rest/v1/liya_post_comments?id=eq.${cid}`,{token:a.token})).length,1);
const report=randomUUID(); await ok('/rest/v1/liya_post_comment_reports',{method:'POST',token:a.token,body:{id:report,reporter_id:a.id,comment_id:cid,post_id:pid,target_user:b.id,body_snapshot:'comment test',reason:'Harassment'}});
const own=await ok('/rest/v1/rpc/liya_my_report_status',{method:'POST',token:a.token,body:{}}); assert.ok(own.some(row=>row.report_id===report));
const other=await ok('/rest/v1/rpc/liya_my_report_status',{method:'POST',token:b.token,body:{}}); assert.ok(!other.some(row=>row.report_id===report));
await ok('/rest/v1/liya_follows',{method:'POST',token:a.token,body:{owner_id:a.id,target_id:b.id}});
await ok('/rest/v1/liya_follows',{method:'POST',token:b.token,body:{owner_id:b.id,target_id:a.id}});
const mid=randomUUID(); await ok('/rest/v1/liya_messages',{method:'POST',token:b.token,body:{id:mid,sender_id:b.id,recipient_id:a.id,body:'single private message'}});
assert.equal(sql(`select count(*) from liya_social_private.moderation_reports where kind='message' and report_id in (select id from public.liya_message_reports where message_id='${mid}')`),'0');
await ok('/rest/v1/liya_message_reports',{method:'POST',token:a.token,body:{id:randomUUID(),reporter_id:a.id,message_id:mid,target_user:b.id,body_snapshot:'single private message',media_paths:[],media_kinds:[],reason:'Harassment'}});
await rejected('/rest/v1/liya_message_reports',{method:'POST',token:a.token,body:{id:randomUUID(),reporter_id:a.id,message_id:mid,target_user:b.id,body_snapshot:'fake content',media_paths:[],media_kinds:[],reason:'Harassment'}});
await rejected('/rest/v1/liya_message_reports',{method:'POST',token:b.token,body:{id:randomUUID(),reporter_id:b.id,message_id:mid,target_user:a.id,body_snapshot:'single private message',media_paths:[],media_kinds:[],reason:'Harassment'}});
await upload('liya-example-media','video/example_video_001.mp4',service);
const signed=await ok('/storage/v1/object/sign/liya-example-media/video/example_video_001.mp4',{method:'POST',token:b.token,body:{expiresIn:60}}); assert.ok(signed.signedURL);
assert.equal(sql("select liya_social_private.set_curated_hidden('example-video-001',true,'local-reviewer')"),'t');
await rejected('/storage/v1/object/sign/liya-example-media/video/example_video_001.mp4',{method:'POST',token:b.token,body:{expiresIn:60}});
const earlier=await fetch(base+'/storage/v1'+signed.signedURL); assert.ok(earlier.ok,`Existing signed URL returned ${earlier.status}`);
assert.equal(sql("select liya_social_private.set_curated_starter_hidden('example-video-001',0,true,'local-reviewer')"),'t');
assert.equal((await ok('/rest/v1/rpc/liya_hidden_curated_starters',{method:'POST',token:b.token,body:{p_media_id:'example-video-001'}}))[0].position,0);
console.log('PASS: real local Auth, profile upserts and revision checks, PostgREST and Storage RLS, comment and private-message reports, curated-media restrictions and existing signed URL behavior');
