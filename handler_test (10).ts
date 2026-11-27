import { assertEquals } from "jsr:@std/assert@1";
import { makeDeps, post, USER_ID } from "../_shared/testing.ts";
import { makeHandler } from "./handler.ts";

const env = { REVENUECAT_WEBHOOK_AUTH: "secret-value" };
const auth = { Authorization: "secret-value" };
const event = (over: Record<string, unknown> = {}) => ({
  event: {
    type: "INITIAL_PURCHASE", app_user_id: USER_ID, product_id: "gt_premium_yearly", store: "APP_STORE",
    expiration_at_ms: Date.UTC(2027, 0, 1), original_transaction_id: "tx_1", id: "evt_1", ...over,
  },
});

Deno.test("revenuecat: rejects missing or wrong authorization", async () => {
  const hz = makeDeps({ env });
  const h = makeHandler(hz.deps);
  assertEquals((await h(post(event(), {}))).status, 401);
  assertEquals((await h(post(event(), { Authorization: "wrong" }))).status, 401);
  assertEquals((await h(post(event(), { Authorization: "secret-valuX" }))).status, 401);
  assertEquals(hz.adminCalls.length, 0);
});

Deno.test("revenuecat: a server without a configured secret rejects everything", async () => {
  const hz = makeDeps({ env: {} });
  assertEquals((await makeHandler(hz.deps)(post(event(), { Authorization: "" }))).status, 401);
});

Deno.test("revenuecat: only POST is accepted", async () => {
  const res = await makeHandler(makeDeps({ env }).deps)(new Request("http://x", { method: "GET" }));
  assertEquals(res.status, 405);
});

Deno.test("revenuecat: a purchase is written to subscriptions", async () => {
  const hz = makeDeps({ env });
  const res = await makeHandler(hz.deps)(post(event(), auth));
  assertEquals(res.status, 200);
  const call = hz.adminCalls[0];
  assertEquals(call.table, "subscriptions");
  // deno-lint-ignore no-explicit-any
  const { row, options } = call.payload as any;
  assertEquals(row, {
    user_id: USER_ID, plan: "yearly", status: "active", provider: "apple",
    provider_ref: "tx_1", current_period_end: "2027-01-01T00:00:00.000Z",
  });
  assertEquals(options, { onConflict: "user_id,provider_ref" });
});

Deno.test("revenuecat: event types map to the right status and store", async () => {
  const cases: [string, string][] = [
    ["RENEWAL", "active"], ["CANCELLATION", "canceled"], ["EXPIRATION", "expired"],
    ["BILLING_ISSUE", "past_due"], ["UNCANCELLATION", "active"],
  ];
  for (const [type, status] of cases) {
    const hz = makeDeps({ env });
    await makeHandler(hz.deps)(post(event({ type }), auth));
    // deno-lint-ignore no-explicit-any
    assertEquals((hz.adminCalls[0].payload as any).row.status, status, type);
  }
  const play = makeDeps({ env });
  await makeHandler(play.deps)(post(event({ store: "PLAY_STORE", product_id: "gt_premium_monthly" }), auth));
  // deno-lint-ignore no-explicit-any
  const row = (play.adminCalls[0].payload as any).row;
  assertEquals([row.provider, row.plan], ["google", "monthly"]);
});

Deno.test("revenuecat: anonymous users and unknown events are ignored", async () => {
  const anon = makeDeps({ env });
  assertEquals(await (await makeHandler(anon.deps)(post(event({ app_user_id: "$RCAnonymousID:abc" }), auth))).text(), "ignored");
  const unknown = makeDeps({ env });
  assertEquals(await (await makeHandler(unknown.deps)(post(event({ type: "TEST" }), auth))).text(), "ignored");
  assertEquals(anon.adminCalls.length + unknown.adminCalls.length, 0);
});

Deno.test("revenuecat: a database error returns 500 so RevenueCat retries", async () => {
  const hz = makeDeps({ env, upsertError: true });
  assertEquals((await makeHandler(hz.deps)(post(event(), auth))).status, 500);
});
