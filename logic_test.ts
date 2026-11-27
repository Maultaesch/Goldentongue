// Run with: deno test supabase/functions/_shared/logic_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  buildVoiceResult, clamp, DIMS, fillerCount, isOwnAudioPath, list, num, sanitizeBlueprint,
  sanitizeExercise, sanitizeFeedback, sanitizeReport, simSkillValues, validCoachReplies, voiceSkillValues, wordCount,
} from "./logic.ts";

Deno.test("clamp keeps scores in 0..100 and defaults to 50", () => {
  assertEquals(clamp(120), 100);
  assertEquals(clamp(-5), 0);
  assertEquals(clamp(72.6), 73);
  assertEquals(clamp("abc"), 50);
  assertEquals(clamp(undefined), 50);
});

Deno.test("num accepts only numbers inside the range", () => {
  assertEquals(num(0.25, 0, 1), 0.25);
  assertEquals(num(2, 0, 1), null);
  assertEquals(num("0.5", 0, 1), null);
  assertEquals(num(NaN, 0, 1), null);
  assertEquals(num(Infinity, 0, 1), null);
});

Deno.test("list trims, limits and stringifies", () => {
  assertEquals(list(["a", 2, "c"], 2), ["a", "2"]);
  assertEquals(list("nope"), []);
  assertEquals(list(["x".repeat(500)], 1, 10)[0].length, 10);
});

Deno.test("wordCount and fillerCount", () => {
  assertEquals(wordCount("  hello   world "), 2);
  assertEquals(wordCount(""), 0);
  assertEquals(fillerCount("Um, I like, you know, actually did it"), 4);
  assertEquals(fillerCount("Clean sentence"), 0);
});

Deno.test("isOwnAudioPath only allows the caller's folder and plain file names", () => {
  const uid = "11111111-1111-1111-1111-111111111111";
  assert(isOwnAudioPath(`${uid}/1700000000.wav`, uid));
  assert(isOwnAudioPath(`${uid}/take-1.m4a`, uid));
  assert(!isOwnAudioPath(`22222222-2222-2222-2222-222222222222/a.wav`, uid));
  assert(!isOwnAudioPath(`${uid}/../other/a.wav`, uid));
  assert(!isOwnAudioPath(`${uid}/nested/a.wav`, uid));
  assert(!isOwnAudioPath(`${uid}/script.exe`, uid));
});

Deno.test("buildVoiceResult clamps scores, fills missing ones and computes the average", () => {
  const raw = { scores: { attraction: 150, confidence: 60, charisma: "x" }, strengths: ["a"], tips: ["t1", "t2"] };
  const r = buildVoiceResult(raw, { wpm: 140 })!;
  assertEquals(r.scores.attraction, 100);
  assertEquals(r.scores.charisma, 50);
  assertEquals(Object.keys(r.scores).length, DIMS.length);
  assertEquals(r.strengths, ["a"]);
  assertEquals(r.weaknesses, []);
  assertEquals(r.metrics, { wpm: 140 });
  assert(r.avg >= 0 && r.avg <= 100);
  assertEquals(buildVoiceResult({}, {}), null);
  assertEquals(buildVoiceResult(null, {}), null);
});

Deno.test("voiceSkillValues maps dimensions to dashboard skills", () => {
  const scores = {
    attraction: 70, confidence: 80, dominance: 60, relaxation: 60, emotion: 66, pace: 54,
    pitch: 50, articulation: 75, flirt: 65, charisma: 72,
  };
  assertEquals(voiceSkillValues(scores), {
    articulation: 75, confidence: 80, flirting: 65, charisma: 72, communication: 60,
  });
});

Deno.test("sanitizeFeedback bounds every field", () => {
  const f = sanitizeFeedback({
    scores: { attraction: 999, humor: -3 }, good: "g".repeat(900), suggestions: ["a", "b", "c", "d"], respect_flag: "yes",
  });
  assertEquals(f.scores.attraction, 100);
  assertEquals(f.scores.humor, 0);
  assertEquals(f.scores.lead, 50);
  assertEquals(f.good.length, 400);
  assertEquals(f.suggestions.length, 3);
  assertEquals(f.respect_flag, false); // only a real boolean true counts
  assertEquals(sanitizeFeedback({ respect_flag: true }).respect_flag, true);
  assertEquals(sanitizeFeedback(null).scores.lead, 50);
});

Deno.test("sanitizeReport and simSkillValues", () => {
  const r = sanitizeReport({ overall: 71, attraction: 64, charisma: 70, lead: 58, report: "ok", next_steps: ["1", "2", "3", "4", "5"] });
  assertEquals(r.next_steps.length, 4);
  assertEquals(simSkillValues(r), { communication: 58, flirting: 64, confidence: 70 });
});

Deno.test("sanitizeBlueprint limits tasks and minutes", () => {
  const b = sanitizeBlueprint({
    strengths: ["humor"], weaknesses: [], focus: "f",
    daily: [{ task: "voice", minutes: 500 }, { task: "chat", minutes: "x" }, ...Array(10).fill({ task: "t", minutes: 5 })],
  });
  assertEquals(b.daily.length, 6);
  assertEquals(b.daily[0].minutes, 60);
  assertEquals(b.daily[1].minutes, 5);
  assertEquals(sanitizeBlueprint(null).daily, []);
});

Deno.test("validCoachReplies keeps valid replies and falls back to the safe style", () => {
  const v = validCoachReplies({
    replies: [{ style: "playful", text: "hi", why: "because" }, { style: "weird", text: "x", why: "y" }, { text: 1 }],
    risk_note: "careful",
  })!;
  assertEquals(v.replies.length, 2);
  assertEquals(v.replies[1].style, "safe");
  assertEquals(v.risk_note, "careful");
  assertEquals(validCoachReplies({ replies: [] }), null);
  assertEquals(validCoachReplies("x"), null);
});

Deno.test("sanitizeExercise averages criterion scores and keeps database names", () => {
  const names = ["A", "B", "C"];
  const r = sanitizeExercise({ criteria: [{ score: 90 }, { score: 60 }, { score: 30 }], good: "g" }, names)!;
  assertEquals(r.score, 60);
  assertEquals(r.criteria.map((c) => c.name), names);
  assertEquals(sanitizeExercise({ score: 77 }, names)!.score, 77); // falls back to an overall score
  assertEquals(sanitizeExercise({}, names), null);
  assertEquals(sanitizeExercise(null, names), null);
});
