import { createClient } from "npm:@supabase/supabase-js@2";
const result = (status: number, body: Record<string,unknown>) => new Response(JSON.stringify(body), {status,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
Deno.serve(async request => {
 if(request.method!=="POST") return result(405,{error:"method_not_allowed"});
 const bearer=/^Bearer\s+(\S+)$/i.exec(request.headers.get("Authorization")??"");
 const url=Deno.env.get("SUPABASE_URL"), anon=Deno.env.get("SUPABASE_ANON_KEY"), service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
 if(!bearer||!url||!anon||!service) return result(401,{error:"unauthorized"});
 const auth=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:claims,error:authError}=await auth.auth.getClaims(bearer[1]);
 const who=claims?.claims?.sub;
 if(authError||typeof who!=="string"||!uuid.test(who)||claims?.claims?.role!=="authenticated") return result(401,{error:"unauthorized"});
 let body:{action?:unknown;token?:unknown;environment?:unknown;bundle_id?:unknown};
 try{body=await request.json();}catch{return result(400,{error:"invalid_request"});}
 const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
 const {data:settings,error:settingsError}=await admin.from("liya_voip_config").select("enabled").eq("id",true).maybeSingle();
 if(settingsError) return result(503,{error:"unavailable"});
 const bundle=Deno.env.get("APNS_BUNDLE_ID"),team=Deno.env.get("APNS_TEAM_ID"),key=Deno.env.get("APNS_KEY_ID"),privateKey=Deno.env.get("APNS_PRIVATE_KEY");
 const configured=settings?.enabled===true && !!bundle && !bundle.startsWith("example.") && !!team && !!key && !!privateKey;
 if(body.action==="status") return result(200,{configured,bundle_id:configured?bundle:null});
 if(body.action!=="register" && body.action!=="unregister") return result(400,{error:"invalid_request"});
 if(typeof body.token!=="string" || !/^[0-9a-f]{32,256}$/.test(body.token)) return result(400,{error:"invalid_request"});
 if(body.action==="unregister") {
  const digest=await crypto.subtle.digest("SHA-256",new TextEncoder().encode(body.token));
  const hash=Array.from(new Uint8Array(digest),b=>b.toString(16).padStart(2,"0")).join("");
  const {error}=await admin.from("liya_voip_devices").delete().eq("token_hash",hash).eq("owner_id",who);
  return error?result(503,{error:"unavailable"}):result(200,{ok:true});
 }
 if(!configured||typeof body.bundle_id!=="string"||body.bundle_id!==bundle || (body.environment!=="sandbox" && body.environment!=="production")) return result(503,{error:"not_configured"});
 const {error}=await admin.from("liya_voip_devices").upsert({token:body.token,owner_id:who,environment:body.environment,bundle_id:bundle,updated_at:new Date().toISOString()},{onConflict:"token"});
 return error?result(503,{error:"unavailable"}):result(200,{ok:true});
});
