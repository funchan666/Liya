import { createClient } from "npm:@supabase/supabase-js@2.55.0";
import { SignedDataVerifier, Environment } from "npm:@apple/app-store-server-library@3.1.0";
import { Buffer } from "node:buffer";

// Apple Root CA G3 from Apple's public PKI; trust only Apple signatures.
const root = Buffer.from("MIICQzCCAcmgAwIBAgIILcX8iNLFS5UwCgYIKoZIzj0EAwMwZzEbMBkGA1UEAwwSQXBwbGUgUm9vdCBDQSAtIEczMSYwJAYDVQQLDB1BcHBsZSBDZXJ0aWZpY2F0aW9uIEF1dGhvcml0eTETMBEGA1UECgwKQXBwbGUgSW5jLjELMAkGA1UEBhMCVVMwHhcNMTQwNDMwMTgxOTA2WhcNMzkwNDMwMTgxOTA2WjBnMRswGQYDVQQDDBJBcHBsZSBSb290IENBIC0gRzMxJjAkBgNVBAsMHUFwcGxlIENlcnRpZmljYXRpb24gQXV0aG9yaXR5MRMwEQYDVQQKDApBcHBsZSBJbmMuMQswCQYDVQQGEwJVUzB2MBAGByqGSM49AgEGBSuBBAAiA2IABJjpLz1AcqTtkyJygRMc3RCV8cWjTnHcFBbZDuWmBSp3ZHtfTjjTuxxEtX/1H7YyYl3J6YRbTzBPEVoA/VhYDKX1DyxNB0cTddqXl5dvMVztK517IDvYuVTZXpmkOlEKMaNCMEAwHQYDVR0OBBYEFLuw3qFYM4iapIqZ3r6966/ayySrMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgEGMAoGCCqGSM49BAMDA2gAMGUCMQCD6cHEFl4aXTQY2e3v9GwOAEZLuN+yRhHFD/3meoyhpmvOwgPUnPWTxnS4at+qIxUCMG1mihDK1A3UT82NQz60imOlM27jbdoXt2QfyFMm+YhidDkLF1vLUagM6BgD56KyKA==", "base64");
const bundle = "com.liyalumora.auroramuse";
const products = new Set(["ceyarlaxiuojqsbi", "gxaojqvpvmykrgif", "hzlqemvjatucwprd", "hqahzvljpcaltfnm", "npdkdztghlqpfxnr", "qwnbrlxesdvyampt", "czyghtwgjcswnuvl", "jemidcjpjteygrfy", "qmubwwcjusfbmlpw"]);
const reply = (status: number, code: string) => new Response(JSON.stringify({code}), {status,headers:{"Content-Type":"application/json","Cache-Control":"no-store"}});

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return reply(405,"method_not_allowed");
  // Keep the purchase path off until App Store Connect and end-to-end delivery are ready.
  if (Deno.env.get("LIYA_IAP_ENABLED") !== "true") return reply(503,"purchase_not_ready");
  const url=Deno.env.get("SUPABASE_URL"), anon=Deno.env.get("SUPABASE_ANON_KEY"), service=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !anon || !service) return reply(503,"purchase_not_configured");
  const token=/^Bearer\s+(\S+)$/i.exec(request.headers.get("Authorization") ?? "");
  if (!token) return reply(401,"unauthorized");
  const auth=createClient(url,anon,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data:userData,error:userError}=await auth.auth.getUser(token[1]);
  const owner=userData?.user?.id;
  if (userError || !owner) return reply(401,"unauthorized");
  let body: {action?: unknown; signed_transaction?: unknown; product_id?: unknown};
  try {
    const raw=await request.text();
    if (raw.length > 30000) return reply(413,"request_too_large");
    body=JSON.parse(raw);
  } catch { return reply(400,"invalid_request"); }
  if (body.action === "status") return reply(200,"ready");
  if (typeof body.signed_transaction !== "string" || body.signed_transaction.length > 24000 || typeof body.product_id !== "string" || !products.has(body.product_id)) return reply(400,"invalid_request");
  let verified;
  for (const environment of [Environment.PRODUCTION,Environment.SANDBOX]) {
    try {
      // Transaction verification in the pinned Apple library checks bundle and environment, not appAppleId.
      // Zero only satisfies its production constructor; never use this verifier for notifications or app transactions.
      const verifier=new SignedDataVerifier([root],true,environment,bundle,environment === Environment.PRODUCTION ? 0 : undefined);
      verified=await verifier.verifyAndDecodeTransaction(body.signed_transaction);
      break;
    } catch { /* Try the other Apple-signed environment; never trust the unverified payload. */ }
  }
  if (!verified || (verified.environment !== Environment.PRODUCTION && verified.environment !== Environment.SANDBOX)
      || verified.type !== "Consumable" || verified.inAppOwnershipType !== "PURCHASED" || verified.quantity !== 1
      || verified.revocationDate != null || (verified.revocationPercentage ?? 0) > 0
      || verified.bundleId !== bundle || verified.productId !== body.product_id
      || verified.appAccountToken?.toLowerCase() !== owner.toLowerCase()
      || !verified.transactionId || !/^[0-9]{1,30}$/.test(verified.transactionId)) return reply(422,"invalid_transaction");
  const admin=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await admin.rpc("liya_credit_apple_purchase",{
    p_owner:owner,p_environment:verified.environment,p_transaction_id:verified.transactionId,p_product_id:verified.productId
  });
  if (error || (data?.status !== "delivered" && data?.status !== "already_delivered")) return reply(503,"delivery_pending");
  return reply(200,"delivered");
});
