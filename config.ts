import { config } from "../_lib/handlers.ts";
import type { Env } from "../_lib/supa.ts";

export const onRequestGet: PagesFunction<Env> = (ctx) => config(ctx.env);
