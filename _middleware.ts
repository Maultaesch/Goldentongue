import { gate } from "./_lib/handlers.ts";
import type { Env } from "./_lib/supa.ts";

// Every request passes here first: only the login page and its API are public.
export const onRequest: PagesFunction<Env> = (ctx) => gate(ctx.request, ctx.env, () => ctx.next());
