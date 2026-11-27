// Account deletion (required by Apple and Google Play for apps with accounts).
// Body: { confirm: "DELETE" }. Deleting the auth user cascades to the profile and everything linked to it
// (scores, sessions, messages, analyses, favorites, attempts, blueprints, subscription rows).
// Active store or Stripe subscriptions are NOT cancelled here; the apps tell the user to cancel them there.
import { cors, json } from "../_shared/http.ts";
import type { Deps } from "../_shared/deps.ts";

export const makeHandler = (d: Deps) => async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const ctx = await d.authed(req);
  if (!ctx) return json({ error: "Unauthorized" }, 401);

  let body: { confirm?: unknown };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  if (body.confirm !== "DELETE") return json({ error: "Type DELETE to confirm." }, 400);

  const { error } = await d.admin().auth.admin.deleteUser(ctx.user.id);
  if (error) return json({ error: "The account could not be deleted. Please contact support." }, 502);
  return json({ ok: true });
};
