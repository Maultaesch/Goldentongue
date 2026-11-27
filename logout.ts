import { logout } from "../_lib/handlers.ts";
import type { Env } from "../_lib/supa.ts";

export const onRequestPost: PagesFunction<Env> = (ctx) => logout(ctx.request, ctx.env);
