// Stripe -> Supabase. Keeps `subscriptions` in sync for web purchases.
// Secrets: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET.
// Stripe dashboard: add an endpoint for this function with events
//   customer.subscription.created, customer.subscription.updated, customer.subscription.deleted
// and set the endpoint API version to 2024-06-20 (the version this code is written for).
// Deploy with: supabase functions deploy stripe-webhook --no-verify-jwt

import Stripe from "npm:stripe@16.12.0";
import { createClient } from "npm:@supabase/supabase-js@2.45.0";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2024-06-20" });
const cryptoProvider = Stripe.createSubtleCryptoProvider();
const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const signature = req.headers.get("Stripe-Signature");
  if (!signature) return new Response("Missing signature", { status: 400 });
  const body = await req.text();

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      body,
      signature,
      Deno.env.get("STRIPE_WEBHOOK_SECRET")!,
      undefined,
      cryptoProvider,
    );
  } catch (err) {
    console.error("signature verification failed", (err as Error).message);
    return new Response("Invalid signature", { status: 400 });
  }

  if (event.type.startsWith("customer.subscription.")) {
    const sub = event.data.object as Stripe.Subscription;
    const userId = sub.metadata?.user_id;
    const plan = sub.metadata?.plan;
    if (!userId || !["monthly", "quarterly", "yearly"].includes(plan ?? "")) {
      return new Response("ignored");
    }
    const status = event.type === "customer.subscription.deleted" ? "canceled" : sub.status;

    const { error } = await admin.from("subscriptions").upsert({
      user_id: userId,
      plan,
      status,
      provider: "stripe",
      provider_ref: sub.id,
      current_period_end: new Date(sub.current_period_end * 1000).toISOString(),
    }, { onConflict: "user_id,provider_ref" });

    if (error) {
      console.error("subscription upsert failed", error.message);
      return new Response("error", { status: 500 }); // Stripe retries
    }
  }
  return new Response("ok");
});
