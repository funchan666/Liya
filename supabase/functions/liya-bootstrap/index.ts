import { createClient } from "npm:@supabase/supabase-js@2";

const json = (body: unknown, status: number) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ code: 405, message: "Method not allowed" }, 405);
  const authorization = request.headers.get("Authorization") ?? "";
  const match = /^Bearer\s+(\S+)$/i.exec(authorization);
  if (!match) return json({ code: 401, message: "Authentication required" }, 401);

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_ANON_KEY");
  if (!url || !key) return json({ code: 500, message: "Service configuration unavailable" }, 500);
  const client = createClient(url, key, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await client.auth.getUser(match[1]);
  if (error || !data.user) return json({ code: 401, message: "Invalid session" }, 401);

  const { error: profileError } = await client.from("liya_profiles")
    .upsert({ id: data.user.id }, { onConflict: "id", ignoreDuplicates: true });
  if (profileError) return json({ code: 500, message: "Could not initialize profile" }, 500);
  return json({ code: 0, message: "ok", data: {} }, 200);
});
