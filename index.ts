// Starts a Stripe Checkout session for web users (cards, Apple Pay and Google Pay are offered
// automatically by Checkout when enabled in the Stripe dashboard).
// Secrets: STRIPE_SECRET_KEY, STRIPE_PRICE_MONTHLY, STRIPE_PRICE_QUARTERLY, STRIPE_PRICE_YEARLY, APP_URL.
// Note: digital subscriptions inside the iOS and Android apps must use in-app purchase, not this function.

import Stripe from "npm:stripe@16.12.0";
import { createClient } from "npm:@supabase/supabase-js@2.45.0";

const cors = {
  "Access-Control-Allow-Origin": Deno.env.get("APP_URL") ?? "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2024-06-20" });

const PRICES: Record<string, string | undefined> = {
  monthly: Deno.env.get("STRIPE_PRICE_MONTHLY"),
  quarterly: Deno.env.get("STRIPE_PRICE_QUARTERLY"),
  yearly: Deno.env.get("STRIPE_PRICE_YEARLY"),
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Unauthorized" }, 401);
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } },
  );
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return json({ error: "Unauthorized" }, 401);

  let plan = "";
  try {
    plan = String((await req.json()).plan ?? "");
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }
  const price = PRICES[plan];
  if (!price) return json({ error: "Unknown plan" }, 400);

  const appUrl = Deno.env.get("APP_URL") ?? "";
  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    line_items: [{ price, quantity: 1 }],
    client_reference_id: data.user.id,
    customer_email: data.user.email ?? undefined,
    allow_promotion_codes: true,
    subscription_data: {
      metadata: { user_id: data.user.id, plan },
    },
    success_url: `${appUrl}/?checkout=success`,
    cancel_url: `${appUrl}/?checkout=cancel`,
  });

  return json({ url: session.url });
});
