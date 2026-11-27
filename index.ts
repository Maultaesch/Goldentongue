// GoldenTongue API gateway (Cloudflare Worker).
// Sits in front of Supabase: custom domain, CORS allowlist, path allowlist, rate limits and body limits.
// The app uses https://api.<your-domain> as SUPABASE_URL; nothing else in the client changes.
import { type Bucket, corsHeaders, decide, parseList } from "./policy.ts";

export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  UPSTREAM: string; // https://<project>.supabase.co
  ALLOWED_ORIGINS: string; // comma separated, e.g. https://app.example.com
  ALLOWED_FUNCTIONS: string; // comma separated edge function names exposed to clients
  RATE_LIMIT_AI?: RateLimiter;
  RATE_LIMIT_AUTH?: RateLimiter;
  RATE_LIMIT_API?: RateLimiter;
}

const limiterFor = (env: Env, bucket: Bucket) =>
  bucket === "ai" ? env.RATE_LIMIT_AI : bucket === "auth" ? env.RATE_LIMIT_AUTH : env.RATE_LIMIT_API;

const reply = (status: number, error: string, extra: Record<string, string> = {}) =>
  new Response(JSON.stringify({ error }), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ...extra },
  });

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    if (url.pathname === "/healthz") return reply(200, "ok", { "Cache-Control": "no-store" }); // used by scripts/verify_deployment.sh
    const cors = corsHeaders(req.headers.get("Origin"), parseList(env.ALLOWED_ORIGINS));
    if (cors === null) return reply(403, "Origin not allowed");

    if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    const decision = decide(req.method, url.pathname, parseList(env.ALLOWED_FUNCTIONS));
    if (!decision.ok) return reply(decision.status, decision.error, cors);

    const declared = Number(req.headers.get("Content-Length") ?? "0");
    if (declared > decision.maxBody) return reply(413, "Request too large", cors);

    const limiter = limiterFor(env, decision.bucket);
    if (limiter) {
      const ip = req.headers.get("CF-Connecting-IP") ?? "unknown";
      const { success } = await limiter.limit({ key: `${decision.bucket}:${ip}` });
      if (!success) return reply(429, "Too many requests", { ...cors, "Retry-After": "60" });
    }

    const headers = new Headers(req.headers);
    headers.delete("host");
    headers.delete("origin"); // the upstream does not need the browser origin
    const upstreamReq = new Request(env.UPSTREAM.replace(/\/$/, "") + url.pathname + url.search, {
      method: req.method,
      headers,
      body: req.method === "GET" || req.method === "HEAD" ? undefined : req.body,
      redirect: "manual", // OAuth redirects must reach the browser unchanged
      // @ts-ignore required by the runtime when streaming a request body
      duplex: "half",
    });

    let upstream: Response;
    try {
      upstream = await fetch(upstreamReq, { signal: AbortSignal.timeout(90_000) });
    } catch {
      return reply(502, "Upstream unavailable", cors);
    }

    const out = new Headers(upstream.headers);
    for (const [k, v] of Object.entries(cors)) out.set(k, v);
    out.set("X-Content-Type-Options", "nosniff");
    if (decision.bucket !== "api") out.set("Cache-Control", "no-store");
    return new Response(upstream.body, { status: upstream.status, statusText: upstream.statusText, headers: out });
  },
};
