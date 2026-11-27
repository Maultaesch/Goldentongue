// Run with: npm test   (Node 22.6 or newer)
import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { cookie, isPublicPath, parseCookies, safeNext, sameOrigin } from "../functions/_lib/guard.ts";
import { clearSessionCache } from "../functions/_lib/session.ts";
import { ai, checkout, config, deleteAccount, gate, login, logout, me, signup } from "../functions/_lib/handlers.ts";
import type { Env } from "../functions/_lib/supa.ts";

const SUPA = "https://proj.supabase.co";
const ORIGIN = "https://members.example.com";
const env: Env = { SUPABASE_URL: SUPA, SUPABASE_ANON_KEY: "anon", OPENAI_API_KEY: "sk-test", TURNSTILE_SITE_KEY: "site-key" };

// ---------- fake Supabase + OpenAI ----------
interface World {
  validTokens: Record<string, { id: string; email: string }>;
  refreshTokens: Record<string, { access: string; refresh: string; user: { id: string; email: string } }>;
  adults: Record<string, boolean>;
  rpc: Record<string, unknown>;
  premiumBy: Record<string, boolean>; // access token -> has an active membership (admins are premium too)
  adminBy: Record<string, boolean>;
  checkoutUrl: string | null;
  deleteOk: boolean;
  passwords: Record<string, { password: string; access: string; refresh: string; id: string; confirmed?: boolean }>;
  signupResult: { status: number; body: Record<string, unknown> };
  flagged: boolean;
  completion: unknown;
  calls: { url: string; init?: RequestInit; body?: any }[];
}
let w: World;
const original = globalThis.fetch;
const freshWorld = (): World => ({
  validTokens: {
    good: { id: "u1", email: "a@x.com" }, good2: { id: "u1", email: "a@x.com" }, minor: { id: "u2", email: "m@x.com" },
    free: { id: "u3", email: "f@x.com" }, adm: { id: "u4", email: "admin@x.com" },
  },
  refreshTokens: { "rt-good": { access: "good2", refresh: "rt2", user: { id: "u1", email: "a@x.com" } } },
  adults: { u1: true, u2: false, u3: true, u4: true },
  rpc: { consume_ai_request: true },
  premiumBy: { good: true, good2: true, minor: true, adm: true, free: false },
  adminBy: { adm: true },
  checkoutUrl: "https://checkout.stripe.com/c/pay_123",
  deleteOk: true,
  passwords: {
    "a@x.com": { password: "secret123", access: "good", refresh: "rt-good", id: "u1" },
    "f@x.com": { password: "secret123", access: "free", refresh: "rt-free", id: "u3" },
  },
  signupResult: { status: 200, body: { id: "new" } },
  flagged: false,
  completion: { choices: [{ message: { content: JSON.stringify({ ok: true, n: 5 }) } }] },
  calls: [],
});
const J = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { "Content-Type": "application/json" } });

beforeEach(() => {
  clearSessionCache();
  w = freshWorld();
  globalThis.fetch = (async (input: Request | string | URL, init?: RequestInit) => {
    const url = String(input instanceof Request ? input.url : input);
    const body = init?.body ? JSON.parse(String(init.body)) : undefined;
    w.calls.push({ url, init, body });
    const bearer = (init?.headers as Record<string, string> | undefined)?.Authorization?.replace("Bearer ", "");
    if (url === `${SUPA}/auth/v1/user`) {
      const u = bearer ? w.validTokens[bearer] : undefined;
      return u ? J(u) : J({ msg: "bad jwt" }, 401);
    }
    if (url.startsWith(`${SUPA}/rest/v1/profiles`)) {
      const id = new URL(url).searchParams.get("id")!.replace("eq.", "");
      return J([{ adult_confirmed: w.adults[id] === true }]);
    }
    if (url.startsWith(`${SUPA}/rest/v1/rpc/`)) {
      const name = url.split("/").pop()!;
      if (name === "is_premium_self") return J(w.premiumBy[bearer ?? ""] === true);
      if (name === "is_admin_self") return J(w.adminBy[bearer ?? ""] === true);
      return name in w.rpc ? J(w.rpc[name]) : J({}, 404);
    }
    if (url === `${SUPA}/functions/v1/delete-account`) {
      if (!bearer || !w.validTokens[bearer]) return J({ msg: "bad jwt" }, 401);
      return w.deleteOk ? J({ ok: true }) : J({ error: "x" }, 502);
    }
    if (url === `${SUPA}/functions/v1/create-checkout`) {
      if (!bearer || !w.validTokens[bearer]) return J({ msg: "bad jwt" }, 401);
      return w.checkoutUrl ? J({ url: w.checkoutUrl }) : J({ error: "x" }, 500);
    }
    if (url === `${SUPA}/auth/v1/token?grant_type=refresh_token`) {
      const r = w.refreshTokens[body.refresh_token];
      return r ? J({ access_token: r.access, refresh_token: r.refresh, expires_in: 3600, user: r.user }) : J({}, 400);
    }
    if (url === `${SUPA}/auth/v1/token?grant_type=password`) {
      const p = w.passwords[body.email];
      if (!p || p.password !== body.password) return J({ error_code: "invalid_credentials", msg: "Invalid login credentials" }, 400);
      if (p.confirmed === false) return J({ error_code: "email_not_confirmed", msg: "Email not confirmed" }, 400);
      return J({ access_token: p.access, refresh_token: p.refresh, expires_in: 3600, user: { id: p.id } });
    }
    if (url === `${SUPA}/auth/v1/signup`) return J(w.signupResult.body, w.signupResult.status);
    if (url === `${SUPA}/auth/v1/logout`) return new Response(null, { status: 204 });
    if (url === "https://api.openai.com/v1/moderations") return J({ results: [{ flagged: w.flagged }] });
    if (url === "https://api.openai.com/v1/chat/completions") return J(w.completion);
    return J({}, 404);
  }) as typeof fetch;
});
test("cleanup", () => { globalThis.fetch = original; });

const page = (path: string, cookies = "", accept = "text/html") =>
  new Request(`${ORIGIN}${path}`, { headers: { Accept: accept, ...(cookies ? { Cookie: cookies } : {}) } });
const post = (path: string, body: unknown, headers: Record<string, string> = {}) =>
  new Request(`${ORIGIN}${path}`, { method: "POST", headers: { "Content-Type": "application/json", Origin: ORIGIN, ...headers }, body: JSON.stringify(body) });
const next = async () => new Response("<html>secret members content</html>", { status: 200, headers: { "Content-Type": "text/html" } });
const setCookies = (r: Response) => r.headers.getSetCookie();

// ---------- pure helpers ----------
test("guard: public paths are only the login page, its API and static basics", () => {
  for (const p of ["/login", "/login.html", "/upgrade", "/upgrade.html", "/delete-account", "/delete-account.html", "/manifest.json", "/favicon.png", "/icons/Icon-192.png", "/api/login", "/api/signup", "/api/logout", "/api/config"]) assert.equal(isPublicPath(p), true, p);
  for (const p of ["/", "/index.html", "/api/ai", "/api/me", "/icons/../index.html", "/anything", "/app.html"]) assert.equal(isPublicPath(p), false, p);
});

test("guard: sameOrigin needs a matching Origin header", () => {
  assert.equal(sameOrigin(post("/api/login", {})), true);
  assert.equal(sameOrigin(post("/api/login", {}, { Origin: "https://evil.example" })), false);
  assert.equal(sameOrigin(new Request(`${ORIGIN}/api/login`, { method: "POST" })), false);
});

test("guard: safeNext blocks open redirects", () => {
  assert.equal(safeNext("/practice?x=1"), "/practice?x=1");
  for (const bad of [null, "", "https://evil.example", "//evil.example", "/\\evil", "/api/ai"]) assert.equal(safeNext(bad), "/", String(bad));
});

test("guard: cookies are HttpOnly, Secure, SameSite=Lax and round trip", () => {
  const c = cookie("gt_at", "a.b c", 60);
  assert.match(c, /HttpOnly/); assert.match(c, /Secure/); assert.match(c, /SameSite=Lax/);
  assert.deepEqual(parseCookies("gt_at=a.b%20c; x=1"), { gt_at: "a.b c", x: "1" });
});

// ---------- gate ----------
test("gate: public paths pass without a session", async () => {
  const res = await gate(page("/login"), env, next);
  assert.equal(res.status, 200);
  assert.equal(w.calls.length, 0);
});

test("gate: visitors without a session are sent to the login page and never see the content", async () => {
  const res = await gate(page("/"), env, next);
  assert.equal(res.status, 302);
  assert.equal(res.headers.get("Location"), "/login?next=%2F");
  const api = await gate(page("/api/ai", "", "application/json"), env, next);
  assert.equal(api.status, 401);
  assert.equal((await gate(page("/index.html"), env, next)).status, 302);
});

test("gate: a valid session sees the content, marked private", async () => {
  const res = await gate(page("/", "gt_at=good"), env, next);
  assert.equal(res.status, 200);
  assert.match(await res.text(), /secret members content/);
  assert.equal(res.headers.get("Cache-Control"), "private, no-store");
});

test("gate: an expired access token is renewed with the refresh token and new cookies are set", async () => {
  const res = await gate(page("/", "gt_at=expired; gt_rt=rt-good"), env, next);
  assert.equal(res.status, 200);
  const cookies = setCookies(res);
  assert.equal(cookies.length, 2);
  assert.ok(cookies.some((c) => c.startsWith("gt_at=good2")));
  assert.ok(cookies.some((c) => c.startsWith("gt_rt=rt2")));
});

test("gate: invalid tokens, unknown refresh tokens and minors are denied", async () => {
  assert.equal((await gate(page("/", "gt_at=forged; gt_rt=nope"), env, next)).status, 302);
  assert.equal((await gate(page("/", "gt_at=minor"), env, next)).status, 302);
});

test("gate: the session is validated once per minute, not on every request", async () => {
  await gate(page("/", "gt_at=good"), env, next);
  const first = w.calls.length;
  await gate(page("/x", "gt_at=good"), env, next);
  assert.equal(w.calls.length, first);
});

// ---------- login / signup / logout ----------
test("login: cross-site requests are refused", async () => {
  const res = await login(post("/api/login", { email: "a@x.com", password: "secret123" }, { Origin: "https://evil.example" }), env);
  assert.equal(res.status, 403);
  assert.equal(w.calls.length, 0);
});

test("login: wrong password gives 401 and no cookies", async () => {
  const res = await login(post("/api/login", { email: "a@x.com", password: "nope" }), env);
  assert.equal(res.status, 401);
  assert.equal(setCookies(res).length, 0);
  assert.equal((await login(post("/api/login", { email: "not-an-email", password: "x" }), env)).status, 400);
});

test("login: success sets the session cookies and forwards the captcha token", async () => {
  const res = await login(post("/api/login", { email: " A@X.com ", password: "secret123", captcha: "tok" }), env);
  assert.equal(res.status, 200);
  const cookies = setCookies(res);
  assert.ok(cookies.some((c) => c.startsWith("gt_at=good") && c.includes("HttpOnly")));
  assert.ok(cookies.some((c) => c.startsWith("gt_rt=rt-good")));
  const sent = w.calls.find((c) => c.url.includes("grant_type=password"))!;
  assert.equal(sent.body.email, "a@x.com");
  assert.deepEqual(sent.body.gotrue_meta_security, { captcha_token: "tok" });
});

test("login: unconfirmed email and minors are explained and get no session", async () => {
  w.passwords["u@x.com"] = { password: "secret123", access: "good", refresh: "r", id: "u1", confirmed: false };
  const un = await login(post("/api/login", { email: "u@x.com", password: "secret123" }), env);
  assert.equal(un.status, 403);
  assert.match((await un.json()).error, /confirm your email/);
  w.passwords["m@x.com"] = { password: "secret123", access: "minor", refresh: "r2", id: "u2" };
  const minor = await login(post("/api/login", { email: "m@x.com", password: "secret123" }), env);
  assert.equal(minor.status, 403);
  assert.equal(setCookies(minor).length, 0);
});

test("signup: needs the adult confirmation and a decent password", async () => {
  assert.equal((await signup(post("/api/signup", { email: "n@x.com", password: "longenough1" }), env)).status, 400);
  assert.equal((await signup(post("/api/signup", { email: "n@x.com", password: "short", adult: true }), env)).status, 400);
  assert.equal((await signup(post("/api/signup", { email: "n@x.com", password: "longenough1", adult: true }, { Origin: "https://evil.example" }), env)).status, 403);
});

test("signup: sends the adult flag and the captcha token; email confirmation means no session yet", async () => {
  const res = await signup(post("/api/signup", { email: "n@x.com", password: "longenough1", adult: true, captcha: "tok" }), env);
  assert.deepEqual(await res.json(), { ok: true, confirm: true });
  assert.equal(setCookies(res).length, 0);
  const sent = w.calls.find((c) => c.url.endsWith("/auth/v1/signup"))!;
  assert.deepEqual(sent.body.data, { adult_confirmed: true });
  assert.deepEqual(sent.body.gotrue_meta_security, { captcha_token: "tok" });
});

test("signup: with email confirmation off the member is signed in right away", async () => {
  w.signupResult = { status: 200, body: { access_token: "good", refresh_token: "rt-good", expires_in: 3600 } };
  const res = await signup(post("/api/signup", { email: "n@x.com", password: "longenough1", adult: true }), env);
  assert.deepEqual(await res.json(), { ok: true, confirm: false });
  assert.equal(setCookies(res).length, 2);
});

test("signup: a failed captcha is reported clearly", async () => {
  w.signupResult = { status: 400, body: { error_code: "captcha_failed", msg: "captcha verification process failed" } };
  const res = await signup(post("/api/signup", { email: "n@x.com", password: "longenough1", adult: true, captcha: "bad" }), env);
  assert.equal(res.status, 400);
  assert.match((await res.json()).error, /Security check/);
});

test("logout: clears both cookies and tells Supabase", async () => {
  const res = await logout(post("/api/logout", {}, { Cookie: "gt_at=good" }), env);
  assert.equal(res.status, 200);
  assert.ok(setCookies(res).every((c) => c.includes("Max-Age=0")));
  assert.ok(w.calls.some((c) => c.url.endsWith("/auth/v1/logout")));
  assert.equal((await logout(post("/api/logout", {}, { Origin: "https://evil.example" }), env)).status, 403);
});

test("config: exposes only the public Turnstile site key", async () => {
  assert.deepEqual(await config(env).json(), { turnstileSiteKey: "site-key", privacyUrl: "", termsUrl: "", supportEmail: "" });
  const withLinks = await config({ ...env, PRIVACY_URL: "https://x.com/p", TERMS_URL: "https://x.com/t" }).json();
  assert.deepEqual([withLinks.privacyUrl, withLinks.termsUrl], ["https://x.com/p", "https://x.com/t"]);
});

// ---------- me ----------
test("me: reports email, admin and premium from the database; admins count as premium", async () => {
  assert.deepEqual(await (await me(page("/api/me", "gt_at=good"), env)).json(), { email: "a@x.com", admin: false, premium: true });
  assert.deepEqual(await (await me(page("/api/me", "gt_at=free"), env)).json(), { email: "f@x.com", admin: false, premium: false });
  assert.deepEqual(await (await me(page("/api/me", "gt_at=adm"), env)).json(), { email: "admin@x.com", admin: true, premium: true });
  assert.equal((await me(page("/api/me"), env)).status, 401);
});

// ---------- ai ----------
const aiReq = (prompt: unknown, headers: Record<string, string> = {}) => post("/api/ai", { prompt }, { Cookie: "gt_at=good", ...headers });
const longPrompt = 'Return ONLY JSON: {"x":1} for this practice answer.';

test("ai: members only, same origin only, and it needs a key", async () => {
  assert.equal((await ai(post("/api/ai", { prompt: longPrompt }), env)).status, 401);
  assert.equal((await ai(aiReq(longPrompt, { Origin: "https://evil.example" }), env)).status, 403);
  assert.equal((await ai(aiReq(longPrompt), { ...env, OPENAI_API_KEY: undefined })).status, 503);
});

test("ai: validates the prompt size", async () => {
  assert.equal((await ai(aiReq("short"), env)).status, 400);
  assert.equal((await ai(aiReq("x".repeat(8001)), env)).status, 400);
  assert.equal((await ai(aiReq(42), env)).status, 400);
});

test("ai: flagged prompts are refused before the limit is used or the model is called", async () => {
  w.flagged = true;
  const res = await ai(aiReq(longPrompt), env);
  assert.equal(res.status, 422);
  assert.ok(!w.calls.some((c) => c.url.includes("consume_ai_request") || c.url.includes("chat/completions")));
});

test("ai: the free limit is enforced by the database and stops the model call", async () => {
  w.rpc.consume_ai_request = false;
  const res = await ai(aiReq(longPrompt), { ...env, AI_FREE_DAILY_LIMIT: "7" });
  assert.equal(res.status, 429);
  assert.ok(!w.calls.some((c) => c.url.includes("chat/completions")));
  const rpcCall = w.calls.find((c) => c.url.endsWith("consume_ai_request"))!;
  assert.deepEqual(rpcCall.body, { p_free_limit: 7, p_member_limit: 300 });
  assert.equal((rpcCall.init!.headers as Record<string, string>).Authorization, "Bearer good"); // the member's own token
});

test("ai: success returns the parsed JSON object and uses JSON mode", async () => {
  const res = await ai(aiReq(longPrompt), env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { data: { ok: true, n: 5 } });
  const sent = w.calls.find((c) => c.url.includes("chat/completions"))!;
  assert.deepEqual(sent.body.response_format, { type: "json_object" });
  assert.equal(sent.body.messages[1].content, longPrompt);
});

test("ai: unusable model output returns 502", async () => {
  w.completion = { choices: [{ message: { content: "not json" } }] };
  assert.equal((await ai(aiReq(longPrompt), env)).status, 502);
  w.completion = { choices: [{ message: { content: "123" } }] };
  assert.equal((await ai(aiReq(longPrompt), env)).status, 502);
});

// ---------- premium gate: only paying members and admins ----------
test("premium gate: a logged-in member without a membership is sent to the upgrade page and never sees the app", async () => {
  const html = await gate(page("/", "gt_at=free"), env, next);
  assert.equal(html.status, 302);
  assert.equal(html.headers.get("Location"), "/upgrade");
  const api = await gate(page("/api/ai", "gt_at=free", "application/json"), env, next);
  assert.equal(api.status, 402);
  assert.deepEqual(await api.json(), { error: "premium" });
  assert.equal((await gate(page("/index.html", "gt_at=free"), env, next)).status, 302);
});

test("premium gate: the return from Stripe keeps its checkout status on the way to the upgrade page", async () => {
  const ok = await gate(page("/?checkout=success", "gt_at=free"), env, next);
  assert.equal(ok.headers.get("Location"), "/upgrade?checkout=success");
  const cancel = await gate(page("/?checkout=cancel", "gt_at=free"), env, next);
  assert.equal(cancel.headers.get("Location"), "/upgrade?checkout=cancel");
  const odd = await gate(page("/?checkout=<script>", "gt_at=free"), env, next);
  assert.equal(odd.headers.get("Location"), "/upgrade");
});

test("premium gate: paying members and admins get in", async () => {
  assert.equal((await gate(page("/", "gt_at=good"), env, next)).status, 200);
  assert.equal((await gate(page("/", "gt_at=adm"), env, next)).status, 200);
});

test("premium gate: account endpoints (status and checkout) stay open for members without a membership", async () => {
  let called = 0;
  const probe = async () => { called++; return new Response("ok"); };
  assert.equal((await gate(page("/api/me", "gt_at=free", "application/json"), env, probe)).status, 200);
  assert.equal((await gate(post("/api/checkout", { plan: "monthly" }, { Cookie: "gt_at=free" }), env, probe)).status, 200);
  assert.equal(called, 2);
  assert.equal((await gate(post("/api/delete-account", { confirm: "DELETE" }, { Cookie: "gt_at=free" }), env, probe)).status, 200);
  assert.equal(called, 3);
});

test("premium gate: anonymous visitors still go to the login page, not the upgrade page", async () => {
  assert.equal((await gate(page("/"), env, next)).headers.get("Location"), "/login?next=%2F");
});

test("premium gate: REQUIRE_PREMIUM=false lets every confirmed member in", async () => {
  assert.equal((await gate(page("/", "gt_at=free"), { ...env, REQUIRE_PREMIUM: "false" }, next)).status, 200);
});

test("premium gate: a member who just paid gets in within seconds (short cache for non-premium)", async () => {
  const realNow = Date.now;
  let now = 1_000_000;
  Date.now = () => now;
  try {
    assert.equal((await gate(page("/", "gt_at=free"), env, next)).status, 302);
    w.premiumBy.free = true; // the Stripe webhook activated the membership
    now += 3_000;
    assert.equal((await gate(page("/", "gt_at=free"), env, next)).status, 302); // still cached for 10 s
    now += 8_000;
    assert.equal((await gate(page("/", "gt_at=free"), env, next)).status, 200);
  } finally { Date.now = realNow; }
});

test("premium gate: a membership that ends locks the member out again", async () => {
  const realNow = Date.now;
  let now = 5_000_000;
  Date.now = () => now;
  try {
    assert.equal((await gate(page("/", "gt_at=good"), env, next)).status, 200);
    w.premiumBy.good = false; // subscription expired
    now += 61_000;
    assert.equal((await gate(page("/", "gt_at=good"), env, next)).status, 302);
  } finally { Date.now = realNow; }
});

test("login: members without a membership can still log in (to reach the upgrade page)", async () => {
  const res = await login(post("/api/login", { email: "f@x.com", password: "secret123" }), env);
  assert.equal(res.status, 200);
  assert.ok(setCookies(res).some((c) => c.startsWith("gt_at=free")));
});

// ---------- checkout ----------
test("checkout: only same-origin posts, a session and a known plan", async () => {
  assert.equal((await checkout(post("/api/checkout", { plan: "monthly" }, { Origin: "https://evil.example", Cookie: "gt_at=free" }), env)).status, 403);
  assert.equal((await checkout(post("/api/checkout", { plan: "monthly" }), env)).status, 401);
  assert.equal((await checkout(post("/api/checkout", { plan: "lifetime" }, { Cookie: "gt_at=free" }), env)).status, 400);
});

test("checkout: starts Stripe checkout with the member's own token", async () => {
  const res = await checkout(post("/api/checkout", { plan: "yearly" }, { Cookie: "gt_at=free" }), env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { url: "https://checkout.stripe.com/c/pay_123" });
  const sent = w.calls.find((c) => c.url.endsWith("/functions/v1/create-checkout"))!;
  assert.deepEqual(sent.body, { plan: "yearly" });
  assert.equal((sent.init!.headers as Record<string, string>).Authorization, "Bearer free");
});

test("checkout: a failing checkout function returns 502", async () => {
  w.checkoutUrl = null;
  assert.equal((await checkout(post("/api/checkout", { plan: "monthly" }, { Cookie: "gt_at=free" }), env)).status, 502);
});

// ---------- account deletion ----------
const delReq = (body: unknown, headers: Record<string, string> = { Cookie: "gt_at=free" }) => post("/api/delete-account", body, headers);

test("delete account: same origin, a session and the typed confirmation are required", async () => {
  assert.equal((await deleteAccount(delReq({ confirm: "DELETE" }, { Origin: "https://evil.example", Cookie: "gt_at=free" }), env)).status, 403);
  assert.equal((await deleteAccount(delReq({ confirm: "DELETE" }, {}), env)).status, 401);
  assert.equal((await deleteAccount(delReq({ confirm: "delete" }), env)).status, 400);
  assert.ok(!w.calls.some((c) => c.url.endsWith("/functions/v1/delete-account")));
});

test("delete account: works without a membership, uses the member's own token and clears the cookies", async () => {
  const res = await deleteAccount(delReq({ confirm: "DELETE" }), env);
  assert.equal(res.status, 200);
  assert.ok(setCookies(res).every((c) => c.includes("Max-Age=0")));
  const sent = w.calls.find((c) => c.url.endsWith("/functions/v1/delete-account"))!;
  assert.equal((sent.init!.headers as Record<string, string>).Authorization, "Bearer free");
  assert.deepEqual(sent.body, { confirm: "DELETE" });
});

test("delete account: a failing deletion returns 502 and keeps the session", async () => {
  w.deleteOk = false;
  const res = await deleteAccount(delReq({ confirm: "DELETE" }), env);
  assert.equal(res.status, 502);
  assert.equal(setCookies(res).length, 0);
});

test("ai: the member fair-use cap can be set with AI_MEMBER_DAILY_LIMIT", async () => {
  await ai(aiReq(longPrompt), { ...env, AI_MEMBER_DAILY_LIMIT: "50" });
  const rpcCall = w.calls.find((c) => c.url.endsWith("consume_ai_request"))!;
  assert.equal(rpcCall.body.p_member_limit, 50);
});
