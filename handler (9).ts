// RevenueCat -> Supabase. Keeps `subscriptions` in sync for App Store and Google Play purchases.
// Configure in RevenueCat: Webhooks -> URL of this function, Authorization header value = REVENUECAT_WEBHOOK_AUTH.
// Secrets: REVENUECAT_WEBHOOK_AUTH. SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided automatically.
// The app logs in to RevenueCat with the Supabase user id, so app_user_id is the user's UUID.

import type { Deps } from "../_shared/deps.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Product ids as created in App Store Connect and Google Play.
const PRODUCT_PLAN: Record<string, string> = {
  gt_premium_monthly: "monthly",
  gt_premium_quarterly: "quarterly",
  gt_premium_yearly: "yearly",
};

const STATUS: Record<string, string> = {
  INITIAL_PURCHASE: "active",
  RENEWAL: "active",
  PRODUCT_CHANGE: "active",
  UNCANCELLATION: "active",
  NON_RENEWING_PURCHASE: "active",
  CANCELLATION: "canceled", // still premium until current_period_end
  BILLING_ISSUE: "past_due",
  EXPIRATION: "expired",
};

function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export const makeHandler = (d: Pick<Deps, "admin" | "env">) => async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const expected = d.env("REVENUECAT_WEBHOOK_AUTH") ?? "";
  const given = req.headers.get("Authorization") ?? "";
  if (!expected || !safeEqual(given, expected)) return new Response("Unauthorized", { status: 401 });

  let payload: { event?: Record<string, unknown> };
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad request", { status: 400 });
  }
  const ev = payload.event;
  if (!ev) return new Response("ok");

  const status = STATUS[String(ev.type)];
  const userId = String(ev.app_user_id ?? ev.original_app_user_id ?? "");
  // Ignore event types we do not track and anonymous RevenueCat ids.
  if (!status || !UUID.test(userId)) return new Response("ignored");

  const store = String(ev.store ?? "");
  const provider = store === "APP_STORE" || store === "MAC_APP_STORE"
    ? "apple"
    : store === "PLAY_STORE"
    ? "google"
    : "stripe";
  const plan = PRODUCT_PLAN[String(ev.product_id)] ?? "monthly";
  const providerRef = String(ev.original_transaction_id ?? ev.transaction_id ?? ev.id);
  const end = typeof ev.expiration_at_ms === "number"
    ? new Date(ev.expiration_at_ms)
    : new Date();

  const { error } = await d.admin().from("subscriptions").upsert({
    user_id: userId,
    plan,
    status,
    provider,
    provider_ref: providerRef,
    current_period_end: end.toISOString(),
  }, { onConflict: "user_id,provider_ref" });

  if (error) {
    console.error("subscription upsert failed", error.message);
    return new Response("error", { status: 500 }); // RevenueCat retries
  }
  return new Response("ok");
};
