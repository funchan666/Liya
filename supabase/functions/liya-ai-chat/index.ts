import { createClient } from "npm:@supabase/supabase-js@2";

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const model = "openai/gpt-oss-20b";
const systemPrompt = `You are Liya AI, an empathetic AI conversation companion. Be warm, natural, concise and respond in the user's language. Do not pretend to be a human, claim a relationship with the user, or diagnose or offer treatment. If someone may be at imminent risk of harm, encourage contacting local emergency services and a trusted person immediately. Do not give instructions for self-harm. Support the user's real-world connections and respect their autonomy.`;
const respond = (status: number, code: string, retryAfter?: string) => new Response(JSON.stringify({ code }), {
  status,
  headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...(retryAfter ? { "Retry-After": retryAfter } : {}) },
});

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return respond(405, "method_not_allowed");
  const bearer = /^Bearer\s+(\S+)$/i.exec(request.headers.get("Authorization") ?? "");
  const url = Deno.env.get("SUPABASE_URL"), anon = Deno.env.get("SUPABASE_ANON_KEY");
  const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"), apiKey = Deno.env.get("GROQ_API_KEY");
  if (!bearer || !url || !anon || !service) return respond(401, "unauthorized");
  // This remains closed until the published privacy disclosure and per-user consent are in place.
  if (!apiKey || Deno.env.get("LIYA_AI_CONSENT_READY") !== "true") return respond(503, "ai_not_configured");
  const auth = createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: userData, error: userError } = await auth.auth.getUser(bearer[1]);
  const owner = userData?.user?.id;
  if (userError || !owner || !uuid.test(owner) || userData.user.role !== "authenticated") return respond(401, "unauthorized");
  const admin = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: consent, error: consentError } = await admin.from("liya_ai_consents")
    .select("granted,consent_version").eq("owner_id", owner).maybeSingle();
  if (consentError) return respond(503, "service_unavailable");
  if (!consent?.granted || consent.consent_version !== "groq-v1") return respond(403, "consent_required");

  let body: { request_id?: unknown; text?: unknown };
  try {
    const raw = await request.text();
    if (raw.length > 12000) return respond(413, "message_too_large");
    body = JSON.parse(raw);
  } catch { return respond(400, "invalid_request"); }
  if (!body || typeof body.request_id !== "string" || !uuid.test(body.request_id) || typeof body.text !== "string") return respond(400, "invalid_request");
  const text = body.text.trim();
  if (text.length < 1 || [...text].length > 2000) return respond(400, "invalid_request");
  const requestID = body.request_id;
  const lease = crypto.randomUUID();
  const params = { p_owner: owner, p_request: requestID, p_lease: lease };
  const { data: claim, error: claimError } = await admin.rpc("liya_ai_claim", { ...params, p_body: text });
  if (claimError || !claim || typeof claim.status !== "string") return respond(503, "service_unavailable");
  if (claim.status === "completed") return respond(200, "completed");
  if (claim.status === "busy") return respond(409, "request_in_progress");
  if (claim.status === "rate_limited") return respond(429, "rate_limited", "60");
  if (claim.status !== "claimed") return respond(400, "invalid_request");

  let finished = false;
  try {
    const { data: rows, error: historyError } = await admin.from("liya_ai_messages")
      .select("role,body").eq("owner_id", owner).order("created_at", { ascending: false })
      .order("id", { ascending: false }).limit(16);
    if (historyError) return respond(503, "history_unavailable");
    let remaining = 12000;
    const context: { role: string; content: string }[] = [];
    for (const row of rows ?? []) {
      if ((row.role !== "user" && row.role !== "assistant") || typeof row.body !== "string" || row.body.length > remaining) break;
      context.push({ role: row.role, content: row.body });
      remaining -= row.body.length;
    }
    context.reverse();
    const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": "Bearer " + apiKey },
      body: JSON.stringify({ model, messages: [{ role: "system", content: systemPrompt }, ...context, { role: "user", content: text }], max_completion_tokens: 1024, reasoning_effort: "low", temperature: 0.7 }),
      signal: AbortSignal.timeout(30000),
    });
    if (!response.ok) {
      if (response.status === 429) {
        const retry = response.headers.get("Retry-After");
        return respond(429, "rate_limited", retry && /^\d{1,5}$/.test(retry) ? retry : "60");
      }
      if (response.status === 401 || response.status === 403) return respond(503, "provider_unavailable");
      return respond(502, "provider_unavailable");
    }
    const result = await response.json();
    const choice = result?.choices?.[0];
    const answer = typeof choice?.message?.content === "string" ? choice.message.content.trim() : "";
    if (choice?.finish_reason !== "stop" || !answer || [...answer].length > 3000) return respond(502, "invalid_reply");
    const { data: saved, error: saveError } = await admin.rpc("liya_ai_finish", { ...params, p_reply: answer });
    if (saveError || saved !== true) return respond(503, "save_failed");
    finished = true;
    return respond(200, "completed");
  } catch {
    return respond(503, "provider_unavailable");
  } finally {
    if (!finished) await admin.rpc("liya_ai_fail", params);
  }
});
