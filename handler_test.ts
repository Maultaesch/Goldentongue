import { assert, assertEquals } from "jsr:@std/assert@1";
import { COACH_STYLES } from "../_shared/logic.ts";
import { makeDeps, post, rpcCalls } from "../_shared/testing.ts";
import { makeHandler } from "./handler.ts";

const validLlm = {
  replies: COACH_STYLES.map((s) => ({ style: s, text: `text ${s}`, why: `why ${s}` })),
  risk_note: "",
};
const ok = { sb: { rpc: { consume_ai_request: true } }, llm: validLlm };

Deno.test("coach: CORS preflight and wrong method", async () => {
  const h = makeHandler(makeDeps().deps);
  const pre = await h(new Request("http://x", { method: "OPTIONS" }));
  assertEquals(pre.status, 200);
  assertEquals(pre.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals((await h(new Request("http://x", { method: "GET" }))).status, 405);
});

Deno.test("coach: requires a valid session", async () => {
  const res = await makeHandler(makeDeps({ authed: false }).deps)(post({ message: "hello there" }));
  assertEquals(res.status, 401);
});

Deno.test("coach: validates the message", async () => {
  const h = makeHandler(makeDeps(ok).deps);
  assertEquals((await h(post({ message: "x" }))).status, 400);
  assertEquals((await h(post({ message: "x".repeat(1501) }))).status, 400);
  assertEquals((await h(post({}))).status, 400);
  const bad = new Request("http://x", { method: "POST", headers: { Authorization: "Bearer t" }, body: "{not json" });
  assertEquals((await h(bad)).status, 400);
});

Deno.test("coach: adults only", async () => {
  const hz = makeDeps({ ...ok, adult: false });
  const res = await makeHandler(hz.deps)(post({ message: "what should I say?" }));
  assertEquals(res.status, 422);
  assertEquals(hz.llmCalls.length, 0);
});

Deno.test("coach: flagged input is refused before any limit or AI use", async () => {
  const hz = makeDeps({ ...ok, flagged: true });
  const res = await makeHandler(hz.deps)(post({ message: "something not allowed" }));
  assertEquals(res.status, 422);
  assertEquals(hz.llmCalls.length, 0);
  assertEquals(rpcCalls(hz.calls, "consume_ai_request").length, 0);
});

Deno.test("coach: free limit reached returns 429 and does not call the AI", async () => {
  const hz = makeDeps({ sb: { rpc: { consume_ai_request: false } }, llm: validLlm });
  const res = await makeHandler(hz.deps)(post({ message: "what should I say?" }));
  assertEquals(res.status, 429);
  assertEquals((await res.json()).error, "limit");
  assertEquals(hz.llmCalls.length, 0);
});

Deno.test("coach: success returns the six styles and uses FREE_DAILY_LIMIT", async () => {
  const hz = makeDeps({ ...ok, env: { FREE_DAILY_LIMIT: "12" } });
  const res = await makeHandler(hz.deps)(post({ message: "what should I say next?", context: "She: hi" }));
  assertEquals(res.status, 200);
  const data = await res.json();
  assertEquals(data.replies.map((r: { style: string }) => r.style), [...COACH_STYLES]);
  assertEquals((rpcCalls(hz.calls, "consume_ai_request")[0].payload as { p_free_limit: number }).p_free_limit, 12);
  // user text is passed as quoted data, not as instructions
  assert(hz.llmCalls[0].user.includes('"""what should I say next?"""'));
  assert(hz.llmCalls[0].user.includes('"""She: hi"""'));
  assert(hz.llmCalls[0].system.includes("Never help deceive"));
});

Deno.test("coach: invalid or missing AI output returns 502", async () => {
  const bad = makeDeps({ sb: ok.sb, llm: { replies: "nope" } });
  assertEquals((await makeHandler(bad.deps)(post({ message: "hello there" }))).status, 502);
  const none = makeDeps({ sb: ok.sb });
  assertEquals((await makeHandler(none.deps)(post({ message: "hello there" }))).status, 502);
});
