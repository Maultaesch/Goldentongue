// Thin Supabase REST/Auth client used by the member gate. Runs only on the server (Pages Functions).
export interface Env {
  SUPABASE_URL: string;
  SUPABASE_ANON_KEY: string;
  OPENAI_API_KEY?: string;
  AI_MODEL?: string;
  AI_FREE_DAILY_LIMIT?: string;
  AI_MEMBER_DAILY_LIMIT?: string; // fair-use cap per paying member and day (default 300); admins are unlimited
  TURNSTILE_SITE_KEY?: string;
  SUPPORT_EMAIL?: string; // shown on the public account deletion page
  PRIVACY_URL?: string; // public privacy policy and terms (required by the stores and good practice on the web)
  TERMS_URL?: string;
  REQUIRE_PREMIUM?: string; // "false" lets every confirmed member in; default: premium members and admins only
}

export interface Tokens {
  access_token: string;
  refresh_token: string;
  expires_in: number;
}

const base = (env: Env) => env.SUPABASE_URL.replace(/\/$/, "");
const headers = (env: Env, token?: string) => ({
  apikey: env.SUPABASE_ANON_KEY,
  "Content-Type": "application/json",
  ...(token ? { Authorization: `Bearer ${token}` } : {}),
});

export async function getUser(env: Env, token: string): Promise<{ id: string; email: string } | null> {
  const res = await fetch(`${base(env)}/auth/v1/user`, { headers: headers(env, token) });
  if (!res.ok) return null;
  const u = await res.json() as { id?: string; email?: string };
  return u.id ? { id: u.id, email: u.email ?? "" } : null;
}

export async function refresh(env: Env, refreshToken: string): Promise<(Tokens & { user: { id: string } }) | null> {
  const res = await fetch(`${base(env)}/auth/v1/token?grant_type=refresh_token`, {
    method: "POST", headers: headers(env), body: JSON.stringify({ refresh_token: refreshToken }),
  });
  if (!res.ok) return null;
  const t = await res.json() as Tokens & { user: { id: string } };
  return t.access_token ? t : null;
}

export async function passwordLogin(env: Env, email: string, password: string, captcha?: string) {
  const res = await fetch(`${base(env)}/auth/v1/token?grant_type=password`, {
    method: "POST", headers: headers(env),
    body: JSON.stringify({ email, password, ...(captcha ? { gotrue_meta_security: { captcha_token: captcha } } : {}) }),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) as Record<string, unknown> };
}

export async function signUp(env: Env, email: string, password: string, captcha?: string) {
  const res = await fetch(`${base(env)}/auth/v1/signup`, {
    method: "POST", headers: headers(env),
    body: JSON.stringify({
      email, password, data: { adult_confirmed: true },
      ...(captcha ? { gotrue_meta_security: { captcha_token: captcha } } : {}),
    }),
  });
  return { status: res.status, body: await res.json().catch(() => ({})) as Record<string, unknown> };
}

export async function logout(env: Env, token: string) {
  await fetch(`${base(env)}/auth/v1/logout`, { method: "POST", headers: headers(env, token) }).catch(() => {});
}

/** RLS lets a user read only their own profile row. */
export async function isAdult(env: Env, token: string, userId: string): Promise<boolean> {
  const res = await fetch(`${base(env)}/rest/v1/profiles?id=eq.${encodeURIComponent(userId)}&select=adult_confirmed`, {
    headers: headers(env, token),
  });
  if (!res.ok) return false;
  const rows = await res.json() as { adult_confirmed?: boolean }[];
  return rows[0]?.adult_confirmed === true;
}

export async function rpc(env: Env, token: string, name: string, args: Record<string, unknown> = {}) {
  const res = await fetch(`${base(env)}/rest/v1/rpc/${name}`, {
    method: "POST", headers: headers(env, token), body: JSON.stringify(args),
  });
  if (!res.ok) return null;
  return await res.json().catch(() => null);
}

/** Starts a Stripe Checkout session through the Supabase edge function (needs the member's own token). */
export async function createCheckout(env: Env, token: string, plan: string) {
  const res = await fetch(`${base(env)}/functions/v1/create-checkout`, {
    method: "POST", headers: headers(env, token), body: JSON.stringify({ plan }),
  });
  if (!res.ok) return null;
  const d = await res.json().catch(() => null) as { url?: string } | null;
  return d?.url ?? null;
}

/** Deletes the member's account through the Supabase edge function (needs the member's own token). */
export async function deleteAccount(env: Env, token: string) {
  const res = await fetch(`${base(env)}/functions/v1/delete-account`, {
    method: "POST", headers: headers(env, token), body: JSON.stringify({ confirm: "DELETE" }),
  });
  return res.ok;
}
