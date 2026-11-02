import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT } from "npm:jose@6";

const reply = (status: number, body: Record<string, unknown>) => new Response(JSON.stringify(body), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply(405, { error: "method_not_allowed" });
  const bearer = /^Bearer\s+(\S+)$/i.exec(req.headers.get("Authorization") ?? "");
  const base = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!bearer || !base || !anon || !service) return reply(401, { error: "unauthorized" });
  const auth = createClient(base, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data, error } = await auth.auth.getClaims(bearer[1]);
  const who = data?.claims?.sub;
  if (error || typeof who !== "string" || !uuid.test(who) || data?.claims?.role !== "authenticated") return reply(401, { error: "unauthorized" });
  let body: { action?: unknown; call_id?: unknown };
  try { body = await req.json(); } catch { return reply(400, { error: "invalid_request" }); }
  const endpoint = Deno.env.get("LIVEKIT_URL"), apiKey = Deno.env.get("LIVEKIT_API_KEY"), secret = Deno.env.get("LIVEKIT_API_SECRET");
  let validURL = false;
  try { const u = new URL(endpoint ?? ""); validURL = u.protocol === "wss:" && !!u.hostname && !u.username && !u.password; } catch { /* not configured */ }
  const configured = validURL && !!apiKey && !!secret;
  const admin = createClient(base, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: settings, error: settingsError } = await admin.from("liya_call_config").select("enabled").eq("id", true).maybeSingle();
  if (settingsError) return reply(503, { error: "service_unavailable" });
  if (body.action === "status") return reply(200, { configured: configured && settings?.enabled === true });
  if (body.action !== "join" || typeof body.call_id !== "string" || !uuid.test(body.call_id)) return reply(400, { error: "invalid_request" });
  if (!configured || settings?.enabled !== true || !endpoint || !apiKey || !secret) return reply(503, { error: "calling_not_configured" });
  const { data: call, error: callError } = await admin.from("liya_calls")
    .select("id,caller_id,callee_id,kind,status,updated_at").eq("id", body.call_id).maybeSingle();
  if (callError) return reply(503, { error: "service_unavailable" });
  if (!call || call.status !== "accepted" || (call.caller_id !== who && call.callee_id !== who) ||
      Date.now() - Date.parse(call.updated_at) > 30 * 60 * 1000) return reply(403, { error: "call_unavailable" });
  const { data: blocks, error: blockError } = await admin.from("liya_blocks").select("owner_id")
    .or(`and(owner_id.eq.${call.caller_id},target_id.eq.${call.callee_id}),and(owner_id.eq.${call.callee_id},target_id.eq.${call.caller_id})`).limit(1);
  if (blockError) return reply(503, { error: "service_unavailable" });
  if (blocks?.length) return reply(403, { error: "call_unavailable" });
  const token = await new SignJWT({ video: { roomJoin: true, room: `liya-${call.id}`, canPublish: true,
      canPublishSources: call.kind === "video" ? ["microphone", "camera"] : ["microphone"], canSubscribe: true, canPublishData: false } })
    .setProtectedHeader({ alg: "HS256", typ: "JWT" }).setIssuer(apiKey).setSubject(who)
    .setIssuedAt().setNotBefore("0s").setExpirationTime("5m").sign(new TextEncoder().encode(secret));
  return reply(200, { url: endpoint, token });
});
