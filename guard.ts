// Pure helpers: which paths are public, same-origin checks, safe redirects, cookies.

const PUBLIC_EXACT = new Set([
  "/login", "/login.html", "/upgrade", "/upgrade.html", "/delete-account", "/delete-account.html", "/manifest.json", "/favicon.png", "/robots.txt",
  "/api/login", "/api/signup", "/api/logout", "/api/config",
]);
const PUBLIC_PREFIX = ["/icons/"];

export function isPublicPath(pathname: string): boolean {
  if (PUBLIC_EXACT.has(pathname)) return true;
  return PUBLIC_PREFIX.some((p) => pathname.startsWith(p) && !pathname.includes(".."));
}

/** Signed-in members without a membership may still use these (to see their status and to pay). */
const ACCOUNT_PATHS = new Set(["/api/me", "/api/checkout", "/api/delete-account"]);
export const isAccountPath = (pathname: string) => ACCOUNT_PATHS.has(pathname);

/** Browser POSTs always send Origin. Anything else (missing or foreign) is refused. */
export function sameOrigin(req: Request): boolean {
  const origin = req.headers.get("Origin");
  return !!origin && origin === new URL(req.url).origin;
}

/** Only local paths are allowed as a post-login target (no open redirects). */
export function safeNext(value: string | null): string {
  if (!value || !value.startsWith("/") || value.startsWith("//") || value.includes("\\") || value.startsWith("/api/")) return "/";
  return value;
}

export function parseCookies(header: string | null): Record<string, string> {
  const out: Record<string, string> = {};
  for (const part of (header ?? "").split(";")) {
    const i = part.indexOf("=");
    if (i > 0) out[part.slice(0, i).trim()] = decodeURIComponent(part.slice(i + 1).trim());
  }
  return out;
}

export function cookie(name: string, value: string, maxAge: number): string {
  return `${name}=${encodeURIComponent(value)}; Path=/; Max-Age=${maxAge}; HttpOnly; Secure; SameSite=Lax`;
}

export const clearCookie = (name: string) => cookie(name, "", 0);

export const wantsHtml = (req: Request) => (req.headers.get("Accept") ?? "").includes("text/html");
