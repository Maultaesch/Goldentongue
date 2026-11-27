// Request handlers for the member site. Route files in functions/ are thin wrappers around these.
import { clearCookie, isAccountPath, isPublicPath, safeNext, sameOrigin, wantsHtml } from "./guard.ts";
import { resolveSession, sessionCookies } from "./session.ts";
import { createCheckout, deleteAccount as supaDeleteAccount, isAdult, logout as supaLogout, passwordLogin, rpc, signUp, type Env } from "./supa.ts";

const json = (body: unknown, status = 200, cookies: string[] = []) => {
  const h = new Headers({ "Content-Type": "application/json", "Cache-Control": "no-store" });
  for (const c of cookies) h.append("Set-Cookie", c);
  return new Response(JSON.stringify(body), { status, headers: h });
};

const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/** Middleware: everything except the login/upgrade pages and their API is for paying members and admins only. */
export async function gate(req: Request, env: Env, next: () => Promise<Response>): Promise<Response> {
  const url = new URL(req.url);
  if (isPublicPath(url.pathname)) return next();
  const s = await resolveSession(req, env);
  if (!s) {
    if (wantsHtml(req) && req.method === "GET") {
      const target = url.pathname + url.search;
      return new Response(null, { status: 302, headers: { Location: `/login?next=${encodeURIComponent(safeNext(target))}`, "Cache-Control": "no-store" } });
    }
    return json({ error: "Please log in." }, 401);
  }
  // Logged in, but no active membership: only the account endpoints (status, checkout) and the upgrade page.
  if (env.REQUIRE_PREMIUM !== "false" && !s.premium && !isAccountPath(url.pathname)) {
    if (wantsHtml(req) && req.method === "GET") {
      const c = url.searchParams.get("checkout");
      const to = c === "success" || c === "cancel" ? `/upgrade?checkout=${c}` : "/upgrade";
      return new Response(null, { status: 302, headers: { Location: to, "Cache-Control": "no-store" } });
    }
    return json({ error: "premium" }, 402);
  }
  const res = await next();
  const out = new Response(res.body, res);
  out.headers.set("Cache-Control", "private, no-store");
  for (const c of s.setCookies) out.headers.append("Set-Cookie", c);
  return out;
}

async function readBody(req: Request): Promise<Record<string, unknown> | null> {
  if (Number(req.headers.get("Content-Length") ?? "0") > 20_000) return null;
  try { return await req.json() as Record<string, unknown>; } catch { return null; }
}

function authError(body: Record<string, unknown>, status: number) {
  const code = String(body.error_code ?? body.code ?? "");
  const msg = String(body.msg ?? body.message ?? body.error_description ?? "").toLowerCase();
  if (code === "email_not_confirmed" || msg.includes("not confirmed")) return json({ error: "Please confirm your email first." }, 403);
  if (code.includes("captcha") || msg.includes("captcha")) return json({ error: "Security check failed. Please try again." }, 400);
  if (status === 429) return json({ error: "Too many attempts. Please wait a moment." }, 429);
  if (status === 400 || status === 401 || status === 422) return json({ error: "Wrong email or password." }, 401);
  return json({ error: "Login is unavailable right now." }, 502);
}

export async function login(req: Request, env: Env): Promise<Response> {
  if (!sameOrigin(req)) return json({ error: "Forbidden" }, 403);
  const b = await readBody(req);
  const email = String(b?.email ?? "").trim().toLowerCase();
  const password = String(b?.password ?? "");
  if (!EMAIL.test(email) || password.length < 1 || password.length > 200) return json({ error: "Enter your email and password." }, 400);

  const r = await passwordLogin(env, email, password, b?.captcha ? String(b.captcha) : undefined);
  const t = r.body as { access_token?: string; refresh_token?: string; expires_in?: number; user?: { id: string } };
  if (r.status !== 200 || !t.access_token || !t.refresh_token || !t.user) return authError(r.body, r.status);

  if (!(await isAdult(env, t.access_token, t.user.id))) {
    return json({ error: "Members must be 18 or older." }, 403);
  }
  return json({ ok: true }, 200, sessionCookies({ access_token: t.access_token, refresh_token: t.refresh_token, expires_in: t.expires_in ?? 3600 }));
}

export async function signup(req: Request, env: Env): Promise<Response> {
  if (!sameOrigin(req)) return json({ error: "Forbidden" }, 403);
  const b = await readBody(req);
  const email = String(b?.email ?? "").trim().toLowerCase();
  const password = String(b?.password ?? "");
  if (!EMAIL.test(email)) return json({ error: "Enter a valid email address." }, 400);
  if (password.length < 8 || password.length > 200) return json({ error: "Use a password with at least 8 characters." }, 400);
  if (b?.adult !== true) return json({ error: "Please confirm that you are 18 or older." }, 400);

  const r = await signUp(env, email, password, b?.captcha ? String(b.captcha) : undefined);
  if (r.status >= 400) {
    const code = String(r.body.error_code ?? r.body.code ?? "");
    if (code.includes("captcha")) return json({ error: "Security check failed. Please try again." }, 400);
    if (r.status === 429) return json({ error: "Too many attempts. Please wait a moment." }, 429);
    if (code === "weak_password") return json({ error: "That password is too weak." }, 400);
    return json({ error: "Could not create the account. Try logging in instead." }, 400);
  }
  const t = r.body as { access_token?: string; refresh_token?: string; expires_in?: number };
  if (t.access_token && t.refresh_token) {
    return json({ ok: true, confirm: false }, 200, sessionCookies({ access_token: t.access_token, refresh_token: t.refresh_token, expires_in: t.expires_in ?? 3600 }));
  }
  return json({ ok: true, confirm: true }); // email confirmation is on: no session yet
}

export async function logout(req: Request, env: Env): Promise<Response> {
  if (!sameOrigin(req)) return json({ error: "Forbidden" }, 403);
  const s = await resolveSession(req, env);
  if (s) await supaLogout(env, s.token);
  return json({ ok: true }, 200, [clearCookie("gt_at"), clearCookie("gt_rt")]);
}

export function config(env: Env): Response {
  return json({ turnstileSiteKey: env.TURNSTILE_SITE_KEY ?? "", privacyUrl: env.PRIVACY_URL ?? "", termsUrl: env.TERMS_URL ?? "", supportEmail: env.SUPPORT_EMAIL ?? "" });
}

export async function me(req: Request, env: Env): Promise<Response> {
  const s = await resolveSession(req, env);
  if (!s) return json({ error: "Please log in." }, 401);
  const [admin, premium] = await Promise.all([rpc(env, s.token, "is_admin_self"), rpc(env, s.token, "is_premium_self")]);
  return json({ email: s.user.email, admin: admin === true, premium: premium === true || admin === true });
}

/** Server side AI for members: limits are enforced in the database (admins and premium are unlimited). */
export async function ai(req: Request, env: Env): Promise<Response> {
  if (!sameOrigin(req)) return json({ error: "Forbidden" }, 403);
  const s = await resolveSession(req, env);
  if (!s) return json({ error: "Please log in." }, 401);
  if (!env.OPENAI_API_KEY) return json({ error: "AI is not configured." }, 503);

  const b = await readBody(req);
  const prompt = typeof b?.prompt === "string" ? b.prompt : "";
  if (prompt.length < 10 || prompt.length > 8000) return json({ error: "Invalid request." }, 400);

  const key = env.OPENAI_API_KEY;
  const auth = { "Content-Type": "application/json", Authorization: `Bearer ${key}` };
  try {
    const mod = await fetch("https://api.openai.com/v1/moderations", {
      method: "POST", headers: auth, body: JSON.stringify({ model: "omni-moderation-latest", input: prompt }),
    });
    if (mod.ok && (await mod.json() as { results?: { flagged?: boolean }[] }).results?.[0]?.flagged) {
      return json({ error: "I can't help with that request." }, 422);
    }
  } catch { /* moderation outage: continue, the prompts carry their own safety rules */ }

  const limit = Number(env.AI_FREE_DAILY_LIMIT ?? "20");
  const memberLimit = Number(env.AI_MEMBER_DAILY_LIMIT ?? "300");
  const allowed = await rpc(env, s.token, "consume_ai_request", { p_free_limit: limit, p_member_limit: memberLimit });
  if (allowed !== true) return json({ error: "limit" }, 429);

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST", headers: auth,
    body: JSON.stringify({
      model: env.AI_MODEL ?? "gpt-4o-mini", temperature: 0.8, max_tokens: 1000,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "Follow the instructions in the user message and answer with a single valid JSON object only." },
        { role: "user", content: prompt },
      ],
    }),
  });
  if (!res.ok) return json({ error: "The AI is unavailable right now." }, 502);
  try {
    const c = await res.json() as { choices?: { message?: { content?: string } }[] };
    const data = JSON.parse(c.choices?.[0]?.message?.content ?? "null");
    if (!data || typeof data !== "object") throw new Error("shape");
    return json({ data });
  } catch {
    return json({ error: "The AI returned an unusable answer." }, 502);
  }
}

const PLANS = new Set(["monthly", "quarterly", "yearly"]);

/** Members without a membership can start a Stripe Checkout; the webhook then activates the membership. */
export async function checkout(req: Request, env: Env): Promise<Response> {
  if (!sameOrigin(req)) return json({ error: "Forbidden" }, 403);
  const s = await resolveSession(req, env);
  if (!s) return json({ error: "Please log in." }, 401);
  const b = await readBody(req);
  const plan = String(b?.plan ?? "");
  if (!PLANS.has(plan)) return json({ error: "Unknown plan." }, 400);
  const url = await createCheckout(env, s.token, plan);
  if (!url) return json({ error: "Checkout is unavailable right now." }, 502);
  return json({ url });
}

/** Permanent deletion of the member's account and data; works without a membership too. */
export async function deleteAccount(req: Request, env: Env): Promise<Response> {
  if (!sameOrigin(req)) return json({ error: "Forbidden" }, 403);
  const s = await resolveSession(req, env);
  if (!s) return json({ error: "Please log in." }, 401);
  const b = await readBody(req);
  if (b?.confirm !== "DELETE") return json({ error: "Type DELETE to confirm." }, 400);
  if (!(await supaDeleteAccount(env, s.token))) return json({ error: "The account could not be deleted. Please contact support." }, 502);
  return json({ ok: true }, 200, [clearCookie("gt_at"), clearCookie("gt_rt")]);
}
