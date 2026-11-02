import { createClient } from "npm:@supabase/supabase-js@2";
import { SignJWT } from "npm:jose@6";

// Only a random capability created by the database for an ended call authorizes this worker.
const answer = (status: number, message: string) => new Response(JSON.stringify({ message }), {
  status, headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const capability = /^[0-9a-f]{64}$/;
Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return answer(405, "method not allowed");
  let body: { call_id?: unknown; capability?: unknown };
  try { body = await request.json(); } catch { return answer(400, "invalid request"); }
  if (typeof body.call_id !== "string" || !uuid.test(body.call_id) || typeof body.capability !== "string" || !capability.test(body.capability)) return answer(401, "unauthorized");
  const base = Deno.env.get("SUPABASE_URL"), service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const endpoint = Deno.env.get("LIVEKIT_URL"), key = Deno.env.get("LIVEKIT_API_KEY"), secret = Deno.env.get("LIVEKIT_API_SECRET");
  if (!base || !service || !endpoint || !key || !secret) return answer(503, "service unavailable");
  let host: URL;
  try { host = new URL(endpoint); } catch { return answer(503, "service unavailable"); }
  if (host.protocol !== "wss:" || host.username || host.password || !host.hostname) return answer(503, "service unavailable");
  const admin = createClient(base, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: job, error } = await admin.from("liya_call_cleanup_jobs").select("call_id,caller_id,callee_id,completed_at,capability")
    .eq("call_id", body.call_id).maybeSingle();
  if (error) return answer(503, "service unavailable");
  if (!job || typeof job.capability !== "string" || job.capability.length !== 64) return answer(401, "unauthorized");
  let difference = 0;
  for (let i=0;i<64;i++) difference |= job.capability.charCodeAt(i) ^ body.capability.charCodeAt(i);
  if (difference !== 0) return answer(401, "unauthorized");
  if (job.completed_at) return answer(200, "already completed");
  const room = `liya-${job.call_id}`;
  const grant = { roomAdmin: true, roomCreate: true, room };
  const token = await new SignJWT({ video: grant }).setProtectedHeader({ alg: "HS256", typ: "JWT" })
    .setIssuer(key).setIssuedAt().setExpirationTime("1m").sign(new TextEncoder().encode(secret));
  const url = `https://${host.host}/twirp/livekit.RoomService/`;
  const invoke = async (method: string, payload: Record<string, unknown>) => {
    const response = await fetch(url + method, { method: "POST", headers: { "Authorization": `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify(payload), signal: AbortSignal.timeout(8000) });
    return response.status;
  };
  try {
    // The explicit cutoff revokes even recently refreshed tokens in LiveKit Cloud.
    const cutoff = Math.floor(Date.now() / 1000) + 15;
    for (const identity of [job.caller_id, job.callee_id]) {
      const status = await invoke("RemoveParticipant", { room, identity, revoke_token_ts: String(cutoff) });
      if (status < 200 || status >= 300) return answer(503, "cleanup pending");
    }
    const deleted = await invoke("DeleteRoom", { room });
    if ((deleted < 200 || deleted >= 300) && deleted !== 404) return answer(503, "cleanup pending");
    const { error: completeError } = await admin.from("liya_call_cleanup_jobs")
      .update({ completed_at: new Date().toISOString() }).eq("call_id", job.call_id).is("completed_at", null);
    if (completeError) return answer(503, "cleanup pending");
    return answer(200, "completed");
  } catch { return answer(503, "cleanup pending"); }
});
