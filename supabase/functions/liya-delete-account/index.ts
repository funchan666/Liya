import { createClient } from "npm:@supabase/supabase-js@2";

const response = (code: number, message: string, data: unknown = {}) =>
  new Response(JSON.stringify({ code, message, data }), {
    status: code === 0 ? 200 : code,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" },
  });
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return response(405, "Method not allowed");
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get("Authorization") ?? "");
  if (!match) return response(401, "Authentication required");
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anonKey || !serviceKey) return response(500, "Service configuration unavailable");
  let body: unknown;
  try { body = await request.json(); } catch { return response(400, "Invalid request"); }
  const requestID = (body && typeof body === "object" && "request_id" in body)
    ? (body as { request_id?: unknown }).request_id : null;
  if (typeof requestID !== "string" || !uuid.test(requestID)) return response(400, "Invalid request");
  const auth = createClient(url, anonKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const { data: claims, error: claimsError } = await auth.auth.getClaims(match[1]);
  const userID = claims?.claims?.sub;
  if (claimsError || typeof userID !== "string" || !uuid.test(userID) || claims?.claims?.role !== "authenticated") {
    return response(401, "Invalid session");
  }
  const admin = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const hashBytes = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${userID.toLowerCase()}:${requestID.toLowerCase()}`));
  const hash = Array.from(new Uint8Array(hashBytes), (value) => value.toString(16).padStart(2, "0")).join("");
  try {
    const { data: receipt, error: receiptError } = await admin.from("liya_deletion_receipts").select("status").eq("request_hash", hash).maybeSingle();
    if (receiptError) throw receiptError;
    const { data: userResult, error: userError } = await admin.auth.admin.getUserById(userID);
    if (userError && userError.status !== 404) throw userError;
    if (!userResult?.user) {
      if (!receipt) return response(401, "Account unavailable");
      const { error } = await admin.from("liya_deletion_receipts").update({ status: "deleted", updated_at: new Date().toISOString() }).eq("request_hash", hash);
      if (error) throw error;
      return response(0, "Account deleted", { status: "deleted" });
    }
    if (receipt?.status === "deleted") return response(409, "Deletion state needs attention");
    if (!receipt) {
      const { error } = await admin.from("liya_deletion_receipts").insert({ request_hash: hash, status: "pending" });
      if (error && error.code !== "23505") throw error;
    }
    // Only paths in the authenticated user's directory are eligible.
    const storage = admin.storage.from("liya-user-media");
    const queue = [userID.toLowerCase()];
    const files: string[] = [];
    for (let position = 0; position < queue.length; position++) {
      if (queue.length > 50000 || files.length > 50000) throw new Error("Account media inventory is too large");
      const folder = queue[position];
      for (let offset = 0;; offset += 1000) {
        const { data, error } = await storage.list(folder, { limit: 1000, offset, sortBy: { column: "name", order: "asc" } });
        if (error) throw error;
        const entries = data ?? [];
        for (const entry of entries) {
          if (!entry.name || entry.name === "." || entry.name === ".." || entry.name.includes("/")) throw new Error("Invalid media path");
          const path = `${folder}/${entry.name}`;
          if (entry.id === null) queue.push(path); else files.push(path);
        }
        if (entries.length < 1000) break;
      }
    }
    for (let start = 0; start < files.length; start += 100) {
      const { error } = await storage.remove(files.slice(start, start + 100));
      if (error) throw error;
    }
    const { error: deleteError } = await admin.auth.admin.deleteUser(userID);
    if (deleteError) throw deleteError;
    const { error: completeError } = await admin.from("liya_deletion_receipts").update({ status: "deleted", updated_at: new Date().toISOString() }).eq("request_hash", hash);
    if (completeError) throw completeError;
    // Retain only pseudonymous receipt hashes for recovery, and prune old receipts opportunistically.
    await admin.from("liya_deletion_receipts").delete().eq("status", "deleted").lt("updated_at", new Date(Date.now() - 30 * 86400000).toISOString());
    return response(0, "Account deleted", { status: "deleted" });
  } catch {
    return response(503, "Deletion could not be confirmed. Retry the same request.");
  }
});
