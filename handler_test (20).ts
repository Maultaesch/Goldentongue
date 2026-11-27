import { assert, assertEquals } from "jsr:@std/assert@1";
import { makeDeps, post, USER_ID } from "../_shared/testing.ts";
import { makeHandler } from "./handler.ts";

const premium = { is_premium_self: true, consume_ai_request: true };
const exercise = {
  id: "ex1", track: "deep_talk", category: "Dreams", title: "Follow up on a dream",
  prompt: "She says she secretly wants to open a bakery.",
  criteria: ["Shows genuine curiosity", "Asks about meaning", "Encourages without overpromising"],
};
const answer = "That sounds wonderful. What is it about baking that makes you want to build a life around it?";
const llm = {
  criteria: [{ score: 80, comment: "Curious." }, { score: 70, comment: "Good question." }, { score: 60, comment: "Fine." }],
  good: "Warm and open.", improve: "Add a small personal link.", example: "A stronger version.",
};
const okSb = { rpc: premium, single: { exercises: exercise } };
const body = { exercise_id: "ex1", answer };

Deno.test("exercise: signed in, adult and premium", async () => {
  assertEquals((await makeHandler(makeDeps({ authed: false }).deps)(post(body))).status, 401);
  assertEquals((await makeHandler(makeDeps({ adult: false, sb: okSb }).deps)(post(body))).status, 422);
  assertEquals((await makeHandler(makeDeps({ sb: { rpc: { is_premium_self: false } } }).deps)(post(body))).status, 402);
});

Deno.test("exercise: validates the answer and the exercise", async () => {
  const hz = makeDeps({ sb: okSb, llm });
  const h = makeHandler(hz.deps);
  assertEquals((await h(post({ exercise_id: "ex1", answer: "too short" }))).status, 400);
  assertEquals((await h(post({ exercise_id: "ex1", answer: "x".repeat(1501) }))).status, 400);
  const missing = makeDeps({ sb: { rpc: premium }, llm });
  assertEquals((await makeHandler(missing.deps)(post(body))).status, 404);
  assertEquals(hz.llmCalls.length, 0);
});

Deno.test("exercise: daily cap returns 429 before moderation or AI", async () => {
  const hz = makeDeps({ sb: { ...okSb, counts: { exercise_attempts: 20 } }, llm });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 429);
  assertEquals(hz.llmCalls.length + hz.flaggedCalls.length, 0);
  const custom = makeDeps({ sb: { ...okSb, counts: { exercise_attempts: 3 } }, llm, env: { EXERCISE_DAILY_LIMIT: "3" } });
  assertEquals((await makeHandler(custom.deps)(post(body))).status, 429);
});

Deno.test("exercise: flagged answers are not evaluated or stored", async () => {
  const hz = makeDeps({ sb: okSb, llm, flagged: true });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 422);
  assertEquals(hz.llmCalls.length + hz.adminCalls.length, 0);
});

Deno.test("exercise: success scores with the database criteria and records the skill", async () => {
  const hz = makeDeps({ sb: okSb, llm: { ...llm, criteria: [...llm.criteria] } });
  const res = await makeHandler(hz.deps)(post(body));
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.score, 70); // mean of 80, 70, 60
  assertEquals(out.criteria.map((c: { name: string }) => c.name), exercise.criteria);
  assertEquals(out.example, "A stronger version.");
  // the answer reaches the model as quoted data together with the criteria
  assert(hz.llmCalls[0].user.includes(`"""${answer}"""`));
  assert(hz.llmCalls[0].user.includes("1. Shows genuine curiosity"));
  // attempt stored and skill recorded with the service role only
  const attempt = hz.adminCalls.find((c) => c.op === "insert" && c.table === "exercise_attempts")!;
  // deno-lint-ignore no-explicit-any
  const row = attempt.payload as any;
  assertEquals([row.user_id, row.exercise_id, row.score], [USER_ID, "ex1", 70]);
  const rec = hz.adminCalls.find((c) => c.name === "record_skill_scores")!;
  assertEquals(rec.payload, { p_user: USER_ID, p_values: { deep_talk: 70 }, p_xp: 20 });
});

Deno.test("exercise: the model cannot rename criteria or push scores out of range", async () => {
  const hz = makeDeps({
    sb: okSb,
    llm: { criteria: [{ score: 500, name: "Hacked" }, { score: -20 }, { score: 90 }], good: "g" },
  });
  const out = await (await makeHandler(hz.deps)(post(body))).json();
  assertEquals(out.criteria.map((c: { name: string }) => c.name), exercise.criteria);
  assertEquals(out.criteria.map((c: { score: number }) => c.score), [100, 0, 90]);
  assertEquals(out.score, 63);
});

Deno.test("exercise: unusable AI output returns 502 and stores nothing", async () => {
  const hz = makeDeps({ sb: okSb });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 502);
  assertEquals(hz.adminCalls.length, 0);
});

Deno.test("exercise: admins have no daily cap", async () => {
  const hz = makeDeps({ sb: { rpc: { is_premium_self: true, is_admin_self: true, consume_ai_request: true }, single: { exercises: exercise }, counts: { exercise_attempts: 500 } }, llm });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 200);
});

Deno.test("exercise: refused when the daily AI cap is used up", async () => {
  const hz = makeDeps({ sb: { rpc: { is_premium_self: true, consume_ai_request: false }, single: { exercises: exercise } }, llm });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 429);
  assertEquals(hz.llmCalls.length + hz.adminCalls.length, 0);
});
