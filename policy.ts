// Pure routing and CORS policy for the API gateway (no Cloudflare APIs, so it is unit testable).

export type Bucket = "ai" | "auth" | "upload" | "api";

export type Decision =
  | { ok: true; bucket: Bucket; maxBody: number }
  | { ok: false; status: number; error: string };

export const AI_FUNCTIONS = ["coach", "voice-analyze", "simulator", "blueprint", "exercise-evaluate"];
const AUTH_RATE_LIMITED = /^\/auth\/v1\/(token|signup|recover|otp|magiclink|verify|resend)(\/|$)/;

export const MAX_BODY = { api: 256 * 1024, auth: 16 * 1024, ai: 64 * 1024, upload: 6 * 1024 * 1024 };

const METHODS = new Set(["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"]);

export function parseList(value: string | undefined): string[] {
  return (value ?? "").split(",").map((s) => s.trim()).filter(Boolean);
}

/** Decide whether a request may be forwarded to the Supabase project, and how it is limited. */
export function decide(method: string, pathname: string, allowedFunctions: string[]): Decision {
  if (!METHODS.has(method)) return { ok: false, status: 405, error: "Method not allowed" };

  let decoded: string;
  try {
    decoded = decodeURIComponent(pathname);
  } catch {
    return { ok: false, status: 400, error: "Bad path" };
  }
  if (decoded.includes("..") || decoded.includes("//") || decoded.includes("\\")) {
    return { ok: false, status: 400, error: "Bad path" };
  }

  if (decoded.startsWith("/functions/v1/")) {
    const name = decoded.slice("/functions/v1/".length);
    if (!/^[a-z0-9-]+$/.test(name) || !allowedFunctions.includes(name)) {
      return { ok: false, status: 404, error: "Not found" };
    }
    const ai = AI_FUNCTIONS.includes(name);
    return { ok: true, bucket: ai ? "ai" : "api", maxBody: ai ? MAX_BODY.ai : MAX_BODY.api };
  }
  if (decoded.startsWith("/auth/v1/")) {
    if (decoded.startsWith("/auth/v1/admin")) return { ok: false, status: 403, error: "Forbidden" };
    return { ok: true, bucket: AUTH_RATE_LIMITED.test(decoded) ? "auth" : "api", maxBody: MAX_BODY.auth };
  }
  if (decoded.startsWith("/storage/v1/")) {
    const upload = (method === "POST" || method === "PUT") && decoded.startsWith("/storage/v1/object/");
    return { ok: true, bucket: upload ? "upload" : "api", maxBody: upload ? MAX_BODY.upload : MAX_BODY.api };
  }
  if (decoded.startsWith("/rest/v1/")) return { ok: true, bucket: "api", maxBody: MAX_BODY.api };
  return { ok: false, status: 404, error: "Not found" };
}

const ALLOW_HEADERS = [
  "authorization", "apikey", "content-type", "x-client-info", "x-supabase-api-version", "prefer",
  "range", "accept-profile", "content-profile", "x-upsert", "cache-control", "accept",
].join(", ");

/**
 * CORS for browsers. Requests without an Origin header (mobile apps, servers) are not browser requests
 * and pass without CORS headers. Returns null when a browser origin is not allowed.
 */
export function corsHeaders(origin: string | null, allowedOrigins: string[]): Record<string, string> | null {
  if (!origin) return {};
  if (!allowedOrigins.includes(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, POST, PUT, PATCH, DELETE, HEAD, OPTIONS",
    "Access-Control-Allow-Headers": ALLOW_HEADERS,
    "Access-Control-Expose-Headers": "content-range, retry-after",
    "Access-Control-Max-Age": "86400",
    "Vary": "Origin",
  };
}
