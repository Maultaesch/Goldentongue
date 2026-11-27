import { assertEquals } from "jsr:@std/assert@1";
import { inserts, makeDeps, post } from "../_shared/testing.ts";
import { makeHandler } from "./handler.ts";

const premium = { is_premium_self: true, consume_ai_request: true };
const data = { voice_analyses: [{ avg: 62, scores: {}, weaknesses: ["fast"] }], sessions: [] };
const plan = {
  strengths: ["humor"], weaknesses: ["pace"], focus: "Slow down.", weekly_goal: "3 sessions",
  daily: [{ task: "voice", minutes: 500 }, { task: "chat", minutes: "x" }],
};

Deno.test("blueprint: premium only", async () => {
  assertEquals((await makeHandler(makeDeps({ authed: false }).deps)(post({}))).status, 401);
  const res = await makeHandler(makeDeps({ sb: { rpc: { is_premium_self: false } } }).deps)(post({}));
  assertEquals(res.status, 402);
});

Deno.test("blueprint: needs some data first", async () => {
  const hz = makeDeps({ sb: { rpc: premium }, llm: plan });
  assertEquals((await makeHandler(hz.deps)(post({}))).status, 422);
  assertEquals(hz.llmCalls.length, 0);
});

Deno.test("blueprint: success stores a sanitized plan", async () => {
  const hz = makeDeps({ sb: { rpc: premium, rows: data }, llm: plan });
  const res = await makeHandler(hz.deps)(post({}));
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.daily[0].minutes, 60); // capped
  assertEquals(out.daily[1].minutes, 5); // invalid -> default
  assertEquals(inserts(hz.calls, "blueprints").length, 1);
  assertEquals(hz.llmCalls[0].user.includes("voice_analyses"), true);
});

Deno.test("blueprint: unusable AI output returns 502", async () => {
  const hz = makeDeps({ sb: { rpc: premium, rows: data } });
  assertEquals((await makeHandler(hz.deps)(post({}))).status, 502);
  assertEquals(inserts(hz.calls, "blueprints").length, 0);
});

Deno.test("blueprint: refused when the daily cap is used up", async () => {
  const hz = makeDeps({ sb: { rpc: { is_premium_self: true, consume_ai_request: false }, rows: data }, llm: plan });
  assertEquals((await makeHandler(hz.deps)(post({}))).status, 429);
  assertEquals(hz.llmCalls.length, 0);
});
