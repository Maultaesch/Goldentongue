import { cookie, parseCookies } from "./guard.ts";
import { getUser, isAdult, refresh, rpc, type Env } from "./supa.ts";

export interface Session {
  user: { id: string; email: string };
  token: string;
  premium: boolean; // active membership OR admin (the database treats admins as premium)
  setCookies: string[]; // set only when the access token was refreshed
}

const AT = "gt_at", RT = "gt_rt";
const RT_MAX_AGE = 60 * 60 * 24 * 30;

// Per-isolate cache. Premium members are cached for a minute; non-premium only for 10 seconds,
// so a member who just paid gets in quickly.
const cache = new Map<string, { until: number; user: { id: string; email: string }; premium: boolean }>();

export function sessionCookies(t: { access_token: string; refresh_token: string; expires_in: number }) {
  return [cookie(AT, t.access_token, Math.max(60, t.expires_in)), cookie(RT, t.refresh_token, RT_MAX_AGE)];
}

async function validate(env: Env, token: string) {
  const hit = cache.get(token);
  if (hit && hit.until > Date.now()) return hit;
  const user = await getUser(env, token);
  if (!user) return null;
  if (!(await isAdult(env, token, user.id))) return null; // members must be confirmed adults
  const premium = (await rpc(env, token, "is_premium_self")) === true;
  if (cache.size > 500) cache.clear();
  const entry = { until: Date.now() + (premium ? 60_000 : 10_000), user, premium };
  cache.set(token, entry);
  return entry;
}

export function clearSessionCache() {
  cache.clear();
}

/** Returns the signed-in member, refreshing the access token when needed, or null. */
export async function resolveSession(req: Request, env: Env): Promise<Session | null> {
  const c = parseCookies(req.headers.get("Cookie"));
  if (c[AT]) {
    const v = await validate(env, c[AT]);
    if (v) return { user: v.user, premium: v.premium, token: c[AT], setCookies: [] };
  }
  if (c[RT]) {
    const t = await refresh(env, c[RT]);
    if (t) {
      const v = await validate(env, t.access_token);
      if (v) return { user: v.user, premium: v.premium, token: t.access_token, setCookies: sessionCookies(t) };
    }
  }
  return null;
}
