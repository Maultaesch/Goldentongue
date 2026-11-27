import { me } from "../_lib/handlers.ts";
import type { Env } from "../_lib/supa.ts";

export const onRequestGet: PagesFunction<Env> = (ctx) => me(ctx.request, ctx.env);
