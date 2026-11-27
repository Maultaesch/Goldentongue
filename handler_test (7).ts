import { assert, assertEquals } from "jsr:@std/assert@1";
import { inserts, makeDeps, post, USER_ID } from "../_shared/testing.ts";
import { makeHandler } from "./handler.ts";

const premium = { is_premium_self: true, consume_ai_request: true };
const session = { id: "s1", persona: "shy", mode: "chat" };
const turnLlm = {
  reply: "Haha, maybe.",
  scores: { attraction: 61, emotional: 55, confidence: 70, humor: 48, flirt: 52, lead: 66 },
  good: "Curious opener.", improve: "Ask one question at a time.",
  suggestions: ["Better 1", "Better 2"], respect_flag: false,
};

Deno.test("simulator: premium only, signed in and adult", async () => {
  assertEquals((await makeHandler(makeDeps({ authed: false }).deps)(post({ action: "start" }))).status, 401);
  assertEquals((await makeHandler(makeDeps({ adult: false, sb: { rpc: premium } }).deps)(post({ action: "start" }))).status, 422);
  const res = await makeHandler(makeDeps({ sb: { rpc: { is_premium_self: false } } }).deps)(post({ action: "start", persona: "shy" }));
  assertEquals(res.status, 402);
});

Deno.test("simulator: start validates the persona and opens the session", async () => {
  const bad = makeDeps({ sb: { rpc: premium }, llm: { reply: "Hi" } });
  assertEquals((await makeHandler(bad.deps)(post({ action: "start", persona: "nobody" }))).status, 400);

  const hz = makeDeps({ sb: { rpc: premium }, llm: { reply: "Hey you." } });
  const res = await makeHandler(hz.deps)(post({ action: "start", persona: "party", mode: "call" }));
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { session_id: "new-id", reply: "Hey you." });
  assert(hz.llmCalls[0].system.includes("Party girl"));
  assert(hz.llmCalls[0].system.includes("spoken style")); // call mode
  assertEquals(inserts(hz.calls, "sessions").length, 1);
  assertEquals(inserts(hz.calls, "messages").length, 1);
});

Deno.test("simulator: turn needs an owned session and a sane message", async () => {
  const none = makeDeps({ sb: { rpc: premium }, llm: turnLlm });
  assertEquals((await makeHandler(none.deps)(post({ action: "turn", session_id: "x", message: "hi" }))).status, 404);

  const hz = makeDeps({ sb: { rpc: premium, single: { sessions: session } }, llm: turnLlm });
  const h = makeHandler(hz.deps);
  assertEquals((await h(post({ action: "turn", session_id: "s1", message: "" }))).status, 400);
  assertEquals((await h(post({ action: "turn", session_id: "s1", message: "x".repeat(801) }))).status, 400);
});

Deno.test("simulator: flagged messages are not stored or answered", async () => {
  const hz = makeDeps({ sb: { rpc: premium, single: { sessions: session } }, llm: turnLlm, flagged: true });
  const res = await makeHandler(hz.deps)(post({ action: "turn", session_id: "s1", message: "bad content" }));
  assertEquals(res.status, 422);
  assertEquals(inserts(hz.calls, "messages").length, 0);
  assertEquals(hz.llmCalls.length, 0);
});

Deno.test("simulator: very long sessions are stopped", async () => {
  const hz = makeDeps({ sb: { rpc: premium, single: { sessions: session }, counts: { messages: 81 } }, llm: turnLlm });
  const res = await makeHandler(hz.deps)(post({ action: "turn", session_id: "s1", message: "hello" }));
  assertEquals(res.status, 422);
  assertEquals(hz.llmCalls.length, 0);
});

Deno.test("simulator: turn stores both messages and returns sanitized feedback", async () => {
  const hz = makeDeps({
    sb: { rpc: premium, single: { sessions: session }, rows: { messages: [{ role: "assistant", content: "Hi" }, { role: "user", content: "Hello" }] } },
    llm: { ...turnLlm, scores: { attraction: 999, humor: -4 }, respect_flag: true },
  });
  const res = await makeHandler(hz.deps)(post({ action: "turn", session_id: "s1", message: "Hello there" }));
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.reply, "Haha, maybe.");
  assertEquals(out.scores.attraction, 100);
  assertEquals(out.scores.humor, 0);
  assertEquals(out.scores.lead, 50); // missing -> neutral default
  assertEquals(out.respect_flag, true);
  assertEquals(inserts(hz.calls, "messages").length, 2); // his message and her reply
  assert(hz.llmCalls[0].user.includes("Him: Hello"));
  assert(hz.llmCalls[0].system.includes("Shy woman"));
});

Deno.test("simulator: end needs at least two of his messages", async () => {
  const hz = makeDeps({
    sb: { rpc: premium, single: { sessions: session }, rows: { messages: [{ role: "assistant", content: "Hi" }, { role: "user", content: "Hey" }] } },
    llm: { overall: 70 },
  });
  assertEquals((await makeHandler(hz.deps)(post({ action: "end", session_id: "s1" }))).status, 422);
});

Deno.test("simulator: end returns the report and records skills and XP server-side", async () => {
  const rows = [
    { role: "assistant", content: "Hi" }, { role: "user", content: "Hey" },
    { role: "assistant", content: "Hello" }, { role: "user", content: "How is your week?" },
  ];
  const hz = makeDeps({
    sb: { rpc: premium, single: { sessions: session }, rows: { messages: rows } },
    llm: { overall: 71, attraction: 64, charisma: 70, lead: 58, report: "Nice start.", next_steps: ["a", "b", "c", "d", "e"] },
  });
  const res = await makeHandler(hz.deps)(post({ action: "end", session_id: "s1" }));
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.overall, 71);
  assertEquals(out.next_steps.length, 4);
  assertEquals(hz.calls.filter((c) => c.op === "update" && c.table === "sessions").length, 1);
  const rec = hz.adminCalls.find((c) => c.name === "record_skill_scores")!;
  assertEquals(rec.payload, { p_user: USER_ID, p_values: { communication: 58, flirting: 64, confidence: 70 }, p_xp: 40 });
});

Deno.test("simulator: unknown action", async () => {
  const hz = makeDeps({ sb: { rpc: premium, single: { sessions: session } } });
  assertEquals((await makeHandler(hz.deps)(post({ action: "explode", session_id: "s1" }))).status, 400);
});

Deno.test("simulator: admins are not stopped by the session length limit", async () => {
  const hz = makeDeps({
    sb: { rpc: { is_premium_self: true, is_admin_self: true, consume_ai_request: true }, single: { sessions: session }, counts: { messages: 500 } },
    llm: turnLlm,
  });
  const res = await makeHandler(hz.deps)(post({ action: "turn", session_id: "s1", message: "hello" }));
  assertEquals(res.status, 200);
});

Deno.test("simulator: every AI call counts against the daily cap and is refused when it is used up", async () => {
  const capped = { rpc: { is_premium_self: true, consume_ai_request: false }, single: { sessions: session } };
  const start = makeDeps({ sb: capped, llm: { reply: "Hi" } });
  assertEquals((await makeHandler(start.deps)(post({ action: "start", persona: "shy" }))).status, 429);
  const turn = makeDeps({ sb: capped, llm: turnLlm });
  assertEquals((await makeHandler(turn.deps)(post({ action: "turn", session_id: "s1", message: "hello" }))).status, 429);
  assertEquals(inserts(turn.calls, "messages").length, 0); // nothing is stored when the request is refused
  const rows = [{ role: "user", content: "a" }, { role: "assistant", content: "b" }, { role: "user", content: "c" }];
  const end = makeDeps({ sb: { ...capped, rows: { messages: rows } }, llm: { overall: 70 } });
  assertEquals((await makeHandler(end.deps)(post({ action: "end", session_id: "s1" }))).status, 429);
  assertEquals(start.llmCalls.length + turn.llmCalls.length + end.llmCalls.length, 0);
});

Deno.test("simulator: the member cap comes from MEMBER_DAILY_LIMIT", async () => {
  const hz = makeDeps({ sb: { rpc: premium }, llm: { reply: "Hey" }, env: { MEMBER_DAILY_LIMIT: "7" } });
  await makeHandler(hz.deps)(post({ action: "start", persona: "shy" }));
  const call = hz.calls.find((c) => c.name === "consume_ai_request")!;
  assertEquals(call.payload, { p_free_limit: 0, p_member_limit: 7 });
});
