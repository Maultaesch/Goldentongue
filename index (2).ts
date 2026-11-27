import { makeHandler } from "./handler.ts";
import * as ai from "../_shared/ai.ts";

Deno.serve(makeHandler({ ...ai, env: (name: string) => Deno.env.get(name) }));
