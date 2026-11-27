// Run with: npm test   (Node 22.6 or newer)
import { test } from "node:test";
import assert from "node:assert/strict";
import { corsHeaders, decide, MAX_BODY } from "../src/policy.ts";
import worker, { type Env } from "../src/index.ts";

const FUNCS = ["coach", "voice-analyze", "simulator", "blueprint", "exercise-evaluate", "create-checkout"];

test("policy: functions must be on the allowlist; webhooks and unknown names are hidden", () => {
  assert.deepEqual(decide("POST", "/functions/v1/coach", FUNCS), { ok: true, bucket: "ai", maxBody: MAX_BODY.ai });
  assert.deepEqual(decide("POST", "/functions/v1/create-checkout", FUNCS), { ok: true, bucket: "api", maxBody: MAX_BODY.api });
  for (const name of ["stripe-webhook", "revenuecat-webhook", "nope", "coach/extra", "Coach"]) {
    const d = decide("POST", `/functions/v1/${name}`, FUNCS);
    assert.equal(d.ok, false, name);
  }
});

test("policy: auth endpoints are rate limited in their own bucket and admin is blocked", () => {
  assert.equal((decide("POST", "/auth/v1/token", FUNCS) as { bucket: string }).bucket, "auth");
  assert.equal((decide("POST", "/auth/v1/signup", FUNCS) as { bucket: string }).bucket, "auth");
  assert.equal((decide("GET", "/auth/v1/user", FUNCS) as { bucket: string }).bucket, "api");
  assert.deepEqual(decide("GET", "/auth/v1/admin/users", FUNCS), { ok: false, status: 403, error: "Forbidden" });
});

test("policy: storage uploads get a bigger body limit, other storage calls do not", () => {
  assert.deepEqual(decide("POST", "/storage/v1/object/voice/u/a.wav", FUNCS), { ok: true, bucket: "upload", maxBody: MAX_BODY.upload });
  assert.deepEqual(decide("GET", "/storage/v1/object/voice/u/a.wav", FUNCS), { ok: true, bucket: "api", maxBody: MAX_BODY.api });
});

test("policy: unknown prefixes, odd methods and traversal are rejected", () => {
  assert.equal(decide("GET", "/", FUNCS).ok, false);
  assert.equal(decide("GET", "/realtime/v1/websocket", FUNCS).ok, false);
  assert.equal((decide("TRACE", "/rest/v1/lines", FUNCS) as { status: number }).status, 405);
  assert.equal((decide("GET", "/rest/v1/%2e%2e/auth", FUNCS) as { status: number }).status, 400);
  assert.equal((decide("GET", "/rest//v1/lines", FUNCS) as { status: number }).status, 400);
});

test("cors: no origin passes, allowed origin is echoed, others are refused", () => {
  assert.deepEqual(corsHeaders(null, ["https://app.example.com"]), {});
  const h = corsHeaders("https://app.example.com", ["https://app.example.com"])!;
  assert.equal(h["Access-Control-Allow-Origin"], "https://app.example.com");
  assert.equal(h["Vary"], "Origin");
  assert.equal(corsHeaders("https://evil.example", ["https://app.example.com"]), null);
});

// ---- gateway behaviour with a fake upstream and fake rate limiter ----
const baseEnv = (over: Partial<Env> = {}): Env => ({
  UPSTREAM: "https://proj.supabase.co",
  ALLOWED_ORIGINS: "https://app.example.com",
  ALLOWED_FUNCTIONS: FUNCS.join(","),
  ...over,
});

function mockUpstream(handler: (req: Request) => Response | Promise<Response>) {
  const seen: Request[] = [];
  const original = globalThis.fetch;
  globalThis.fetch = (async (input: Request | string | URL) => {
    const req = input instanceof Request ? input : new Request(input);
    seen.push(req);
    return handler(req);
  }) as typeof fetch;
  return { seen, restore: () => { globalThis.fetch = original; } };
}

test("gateway: forwards path, query, body and auth headers to Supabase", async () => {
  const up = mockUpstream(() => new Response(JSON.stringify({ ok: true }), { status: 200 }));
  try {
    const res = await worker.fetch(
      new Request("https://api.example.com/functions/v1/coach?x=1", {
        method: "POST",
        headers: { Authorization: "Bearer jwt", apikey: "anon", "Content-Type": "application/json", Origin: "https://app.example.com" },
        body: JSON.stringify({ message: "hi" }),
      }),
      baseEnv(),
    );
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("Access-Control-Allow-Origin"), "https://app.example.com");
    assert.equal(res.headers.get("Cache-Control"), "no-store");
    assert.equal(res.headers.get("X-Content-Type-Options"), "nosniff");
    const sent = up.seen[0];
    assert.equal(sent.url, "https://proj.supabase.co/functions/v1/coach?x=1");
    assert.equal(sent.headers.get("Authorization"), "Bearer jwt");
    assert.equal(sent.headers.get("apikey"), "anon");
    assert.equal(sent.headers.get("origin"), null);
    assert.deepEqual(await sent.json(), { message: "hi" });
  } finally { up.restore(); }
});

test("gateway: mobile apps (no Origin) work without CORS headers", async () => {
  const up = mockUpstream(() => new Response("[]", { status: 200 }));
  try {
    const res = await worker.fetch(new Request("https://api.example.com/rest/v1/lines?select=*", { headers: { apikey: "anon" } }), baseEnv());
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("Access-Control-Allow-Origin"), null);
  } finally { up.restore(); }
});

test("gateway: browser origins that are not allowed get 403 and nothing is forwarded", async () => {
  const up = mockUpstream(() => new Response("x"));
  try {
    const res = await worker.fetch(new Request("https://api.example.com/rest/v1/lines", { headers: { Origin: "https://evil.example" } }), baseEnv());
    assert.equal(res.status, 403);
    assert.equal(up.seen.length, 0);
  } finally { up.restore(); }
});

test("gateway: preflight is answered by the worker", async () => {
  const up = mockUpstream(() => new Response("x"));
  try {
    const res = await worker.fetch(new Request("https://api.example.com/functions/v1/coach", { method: "OPTIONS", headers: { Origin: "https://app.example.com" } }), baseEnv());
    assert.equal(res.status, 204);
    assert.match(res.headers.get("Access-Control-Allow-Headers") ?? "", /authorization/);
    assert.equal(up.seen.length, 0);
  } finally { up.restore(); }
});

test("gateway: hidden functions, admin endpoints and oversized bodies never reach Supabase", async () => {
  const up = mockUpstream(() => new Response("x"));
  try {
    const call = (path: string, init: RequestInit = {}) => worker.fetch(new Request(`https://api.example.com${path}`, init), baseEnv());
    assert.equal((await call("/functions/v1/stripe-webhook", { method: "POST", body: "{}" })).status, 404);
    assert.equal((await call("/auth/v1/admin/users")).status, 403);
    const big = await call("/functions/v1/coach", { method: "POST", headers: { "Content-Length": String(70 * 1024) }, body: "x" });
    assert.equal(big.status, 413);
    assert.equal(up.seen.length, 0);
  } finally { up.restore(); }
});

test("gateway: rate limited requests get 429 with Retry-After and are not forwarded", async () => {
  const up = mockUpstream(() => new Response("x"));
  const keys: string[] = [];
  const limiter = { limit: async ({ key }: { key: string }) => { keys.push(key); return { success: false }; } };
  try {
    const res = await worker.fetch(
      new Request("https://api.example.com/functions/v1/simulator", { method: "POST", headers: { "CF-Connecting-IP": "1.2.3.4" }, body: "{}" }),
      baseEnv({ RATE_LIMIT_AI: limiter }),
    );
    assert.equal(res.status, 429);
    assert.equal(res.headers.get("Retry-After"), "60");
    assert.deepEqual(keys, ["ai:1.2.3.4"]);
    assert.equal(up.seen.length, 0);
  } finally { up.restore(); }
});

test("gateway: OAuth redirects are passed through unchanged", async () => {
  const up = mockUpstream(() => new Response(null, { status: 302, headers: { Location: "https://accounts.google.com/o/oauth2/auth?x=1" } }));
  try {
    const res = await worker.fetch(new Request("https://api.example.com/auth/v1/authorize?provider=google", { redirect: "manual" }), baseEnv());
    assert.equal(res.status, 302);
    assert.equal(res.headers.get("Location"), "https://accounts.google.com/o/oauth2/auth?x=1");
  } finally { up.restore(); }
});

test("gateway: an unreachable upstream returns 502", async () => {
  const up = mockUpstream(() => { throw new Error("down"); });
  try {
    const res = await worker.fetch(new Request("https://api.example.com/rest/v1/lines"), baseEnv());
    assert.equal(res.status, 502);
  } finally { up.restore(); }
});

test("gateway: /healthz answers without touching Supabase", async () => {
  const up = mockUpstream(() => new Response("x"));
  try {
    const res = await worker.fetch(new Request("https://api.example.com/healthz"), baseEnv());
    assert.equal(res.status, 200);
    assert.equal(up.seen.length, 0);
  } finally { up.restore(); }
});
