import { signup } from "../_lib/handlers.ts";
import type { Env } from "../_lib/supa.ts";

export const onRequestPost: PagesFunction<Env> = (ctx) => signup(ctx.request, ctx.env);
