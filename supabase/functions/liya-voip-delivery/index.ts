import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@6";
const response=(status:number,message:string)=>new Response(JSON.stringify({message}),{status,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
Deno.serve(async request=>{
 if(request.method!=="POST") return response(405,"method not allowed");
 let body:{call_id?:unknown;capability?:unknown};try{body=await request.json();}catch{return response(400,"invalid request");}
 if(typeof body.call_id!=="string"||!uuid.test(body.call_id)||typeof body.capability!=="string"||!/^[0-9a-f]{64}$/.test(body.capability)) return response(401,"unauthorized");
 const url=Deno.env.get("SUPABASE_URL"),service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"),bundle=Deno.env.get("APNS_BUNDLE_ID"),team=Deno.env.get("APNS_TEAM_ID"),keyID=Deno.env.get("APNS_KEY_ID"),pem=Deno.env.get("APNS_PRIVATE_KEY");
 if(!url||!service||!bundle||!team||!keyID||!pem||bundle.startsWith("example.")) return response(503,"not configured");
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:settings,error:se}=await admin.from("liya_voip_config").select("enabled").eq("id",true).maybeSingle();
 if(se||!settings?.enabled) return response(503,"not configured");
 const {data:job,error:je}=await admin.from("liya_voip_jobs").select("call_id,delivered_at,capability").eq("call_id",body.call_id).maybeSingle();
 if(je) return response(503,"unavailable");
 if(!job||typeof job.capability!=="string"||job.capability.length!==64) return response(401,"unauthorized");
 let difference=0;for(let i=0;i<64;i++) difference|=job.capability.charCodeAt(i)^body.capability.charCodeAt(i);
 if(difference!==0) return response(401,"unauthorized");
 if(job.delivered_at) return response(200,"already sent");
 const {data:call,error:ce}=await admin.from("liya_calls").select("id,caller_id,callee_id,kind,status,expires_at").eq("id",job.call_id).maybeSingle();
 if(ce) return response(503,"unavailable");
 if(!call||call.status!=="ringing"||Date.parse(call.expires_at)<=Date.now()) return response(200,"expired");
 const {data:blocks,error:be}=await admin.from("liya_blocks").select("owner_id").or(`and(owner_id.eq.${call.caller_id},target_id.eq.${call.callee_id}),and(owner_id.eq.${call.callee_id},target_id.eq.${call.caller_id})`).limit(1);
 if(be) return response(503,"unavailable"); if(blocks?.length) return response(200,"blocked");
 const {data:devices,error:de}=await admin.from("liya_voip_devices").select("token,token_hash,environment").eq("owner_id",call.callee_id).eq("bundle_id",bundle).order("updated_at",{ascending:false}).limit(10);
 if(de) return response(503,"unavailable");
 if(!devices?.length) return response(200,"no registered devices");
 try{
  const signing=await importPKCS8(pem,"ES256");
  const jwt=await new SignJWT({}).setProtectedHeader({alg:"ES256",kid:keyID}).setIssuer(team).setIssuedAt().sign(signing);
  const outcomes=await Promise.all(devices.map(async device=>{
   const host=device.environment==="sandbox"?"api.sandbox.push.apple.com":"api.push.apple.com";
   try {
    const r=await fetch(`https://${host}/3/device/${device.token}`,{method:"POST",headers:{authorization:`bearer ${jwt}`,'apns-topic':`${bundle}.voip`,'apns-push-type':'voip','apns-priority':'10','apns-expiration':'0','content-type':'application/json'},body:JSON.stringify({aps:{},call_id:call.id,video:call.kind==="video"}),signal:AbortSignal.timeout(6000)});
    if(r.status===200) return "sent";
    if(r.status===410) { await admin.from("liya_voip_devices").delete().eq("token_hash",device.token_hash).eq("owner_id",call.callee_id); return "invalid"; }
    return "retry";
   } catch { return "retry"; }
  }));
  const sent=outcomes.includes("sent"), retry=outcomes.includes("retry");
  if(sent || !retry) {
   const {error}=await admin.from("liya_voip_jobs").update({delivered_at:new Date().toISOString()}).eq("call_id",call.id).is("delivered_at",null);
   if(error) return response(503,"unavailable");
  }
  return sent?response(200,"sent"):response(503,"not sent");
 }catch{return response(503,"unavailable");}
});
