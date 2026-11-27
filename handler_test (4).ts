import { assert, assertEquals } from "jsr:@std/assert@1";
import { inserts, makeDeps, post, rpcCalls, USER_ID } from "../_shared/testing.ts";
import { makeHandler } from "./handler.ts";

const llm = {
  scores: {
    attraction: 70, confidence: 80, dominance: 60, relaxation: 60, emotion: 66, pace: 54,
    pitch: 50, articulation: 75, flirt: 65, charisma: 72,
  },
  strengths: ["clear"], weaknesses: ["fast"], tips: ["pause more"], impression: "Calm and warm.", note: "ok",
};
const okSb = { rpc: { can_analyze_voice: true, consume_ai_request: true } };
const path = `${USER_ID}/1700000000.wav`;
const body = { audio_path: path, seconds: 30 };

Deno.test("voice: auth, adult check and path safety", async () => {
  assertEquals((await makeHandler(makeDeps({ authed: false }).deps)(post(body))).status, 401);
  assertEquals((await makeHandler(makeDeps({ adult: false, sb: okSb }).deps)(post(body))).status, 422);
  const h = makeHandler(makeDeps({ sb: okSb, llm }).deps);
  assertEquals((await h(post({ audio_path: "22222222-2222-2222-2222-222222222222/a.wav", seconds: 30 }))).status, 400);
  assertEquals((await h(post({ audio_path: `${USER_ID}/../x.wav`, seconds: 30 }))).status, 400);
});

Deno.test("voice: free weekly limit returns 429 before any audio is touched", async () => {
  const hz = makeDeps({ sb: { rpc: { can_analyze_voice: false } }, llm });
  const res = await makeHandler(hz.deps)(post(body));
  assertEquals(res.status, 429);
  assertEquals(hz.calls.filter((c) => c.op === "remove").length, 0);
});

Deno.test("voice: missing audio returns 404", async () => {
  const hz = makeDeps({ sb: { ...okSb, downloadError: true }, llm });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 404);
});

Deno.test("voice: too little speech is rejected and the audio is still deleted", async () => {
  const hz = makeDeps({ sb: okSb, llm, transcript: "hi there" });
  const res = await makeHandler(hz.deps)(post(body));
  assertEquals(res.status, 422);
  assertEquals(hz.calls.filter((c) => c.op === "remove").length, 1);
  assertEquals(hz.llmCalls.length, 0);
});

Deno.test("voice: flagged transcript is refused and audio deleted", async () => {
  const hz = makeDeps({ sb: okSb, llm, flagged: true });
  const res = await makeHandler(hz.deps)(post(body));
  assertEquals(res.status, 422);
  assertEquals(hz.calls.filter((c) => c.op === "remove").length, 1);
  assertEquals(inserts(hz.calls, "voice_analyses").length, 0);
});

Deno.test("voice: success stores the result, deletes audio and records skills server-side", async () => {
  const hz = makeDeps({ sb: okSb, llm, transcript: "Um hello this is a test of my voice and I like it a lot today" });
  const res = await makeHandler(hz.deps)(post({
    ...body,
    metrics: { pitchMedianHz: 200, pitchRangeSemitones: 99, pauseRatio: 0.2, energyVariation: 0.05 },
  }));
  assertEquals(res.status, 200);
  const out = await res.json();
  assertEquals(out.scores.charisma, 72);
  assertEquals(out.avg, 65); // mean of the ten scores
  // on-device metrics are validated: pitch range 99 is out of range and becomes null
  assertEquals(out.metrics.pitchMedianHz, 200);
  assertEquals(out.metrics.pitchRangeSemitones, null);
  assertEquals(out.metrics.pauseRatio, 0.2);
  assertEquals(out.metrics.fillers, 2); // "Um" and "like"
  assert(out.metrics.wpm > 0);
  // audio removed, row stored, skills recorded with the service role
  assertEquals(hz.calls.filter((c) => c.op === "remove").length, 1);
  assertEquals(inserts(hz.calls, "voice_analyses").length, 1);
  const rec = hz.adminCalls.find((c) => c.name === "record_skill_scores")!;
  assertEquals(rec.payload, {
    p_user: USER_ID,
    p_values: { articulation: 75, confidence: 80, flirting: 65, charisma: 72, communication: 60 },
    p_xp: 30,
  });
});

Deno.test("voice: unusable AI output returns 502 and records nothing", async () => {
  const hz = makeDeps({ sb: okSb, llm: { nope: true } });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 502);
  assertEquals(inserts(hz.calls, "voice_analyses").length, 0);
  assertEquals(hz.adminCalls.length, 0);
});

Deno.test("voice: refused when the daily AI cap is used up, audio still deleted, nothing stored", async () => {
  const hz = makeDeps({ sb: { rpc: { can_analyze_voice: true, consume_ai_request: false } }, llm });
  assertEquals((await makeHandler(hz.deps)(post(body))).status, 429);
  assertEquals(hz.calls.filter((c) => c.op === "remove").length, 1);
  assertEquals(hz.llmCalls.length, 0);
  assertEquals(inserts(hz.calls, "voice_analyses").length, 0);
});
