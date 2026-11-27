// Pure helpers (no network, no Deno APIs) so they can be unit tested.

export const DIMS = ["attraction", "confidence", "dominance", "relaxation", "emotion", "pace", "pitch",
  "articulation", "flirt", "charisma"] as const;
export const COACH_STYLES = ["safe", "playful", "flirty", "deep", "professional", "high_confidence"] as const;

export const clamp = (n: unknown) => {
  const v = Math.round(Number(n));
  return Number.isFinite(v) ? Math.max(0, Math.min(100, v)) : 50;
};

export const num = (v: unknown, min: number, max: number) =>
  typeof v === "number" && Number.isFinite(v) && v >= min && v <= max ? Math.round(v * 1000) / 1000 : null;

export const list = (v: unknown, n = 5, len = 300) =>
  Array.isArray(v) ? v.map((x) => String(x).slice(0, len)).slice(0, n) : [];

export const wordCount = (t: string) => (t.trim() ? t.trim().split(/\s+/).length : 0);

export const fillerCount = (t: string) =>
  (t.toLowerCase().match(/\b(um+|uh+|er|like|you know|basically|actually)\b/g) ?? []).length;

/** Audio must live in the caller's own folder and look like a plain file name. */
export function isOwnAudioPath(path: string, userId: string) {
  return path.startsWith(`${userId}/`) && !path.includes("..") &&
    /^[\w-]+\/[\w.-]+\.(wav|m4a|mp3|webm)$/.test(path);
}

export function buildVoiceResult(r: any, metrics: Record<string, unknown>) {
  if (!r?.scores) return null;
  const scores: Record<string, number> = {};
  for (const d of DIMS) scores[d] = clamp(r.scores[d]);
  const avg = Math.round(Object.values(scores).reduce((a, b) => a + b, 0) / DIMS.length);
  return {
    scores, avg, metrics,
    strengths: list(r.strengths), weaknesses: list(r.weaknesses), tips: list(r.tips),
    impression: String(r.impression ?? "").slice(0, 600), note: String(r.note ?? "").slice(0, 300),
  };
}

/** Skill values recorded after a voice analysis (blended server-side with earlier scores). */
export function voiceSkillValues(scores: Record<string, number>) {
  return {
    articulation: scores.articulation,
    confidence: scores.confidence,
    flirting: scores.flirt,
    charisma: scores.charisma,
    communication: Math.round((scores.emotion + scores.relaxation + scores.pace) / 3),
  };
}

export function sanitizeFeedback(r: any) {
  const s = r?.scores ?? {};
  return {
    scores: {
      attraction: clamp(s.attraction), emotional: clamp(s.emotional), confidence: clamp(s.confidence),
      humor: clamp(s.humor), flirt: clamp(s.flirt), lead: clamp(s.lead),
    },
    good: String(r?.good ?? "").slice(0, 400),
    improve: String(r?.improve ?? "").slice(0, 400),
    suggestions: list(r?.suggestions, 3),
    respect_flag: r?.respect_flag === true,
  };
}

export function sanitizeReport(r: any) {
  return {
    overall: clamp(r?.overall), attraction: clamp(r?.attraction), charisma: clamp(r?.charisma), lead: clamp(r?.lead),
    report: String(r?.report ?? "").slice(0, 700),
    next_steps: list(r?.next_steps, 4, 250),
  };
}

/** Skill values recorded after a finished simulator session. */
export function simSkillValues(o: { attraction: number; charisma: number; lead: number }) {
  return { communication: o.lead, flirting: o.attraction, confidence: o.charisma };
}

export function sanitizeBlueprint(r: any) {
  return {
    strengths: list(r?.strengths), weaknesses: list(r?.weaknesses),
    focus: String(r?.focus ?? "").slice(0, 300), weekly_goal: String(r?.weekly_goal ?? "").slice(0, 300),
    daily: (Array.isArray(r?.daily) ? r.daily : []).slice(0, 6).map((d: any) => ({
      task: String(d?.task ?? "").slice(0, 250),
      minutes: Math.max(1, Math.min(60, Number(d?.minutes) || 5)),
    })),
  };
}

export function validCoachReplies(value: any) {
  if (!value || typeof value !== "object" || !Array.isArray(value.replies)) return null;
  const replies = value.replies
    .filter((r: any) => r && typeof r.text === "string" && typeof r.why === "string")
    .map((r: any) => ({
      style: (COACH_STYLES as readonly string[]).includes(r.style) ? r.style : "safe",
      text: String(r.text).slice(0, 600),
      why: String(r.why).slice(0, 400),
    }));
  if (replies.length === 0) return null;
  return { replies, risk_note: typeof value.risk_note === "string" ? value.risk_note.slice(0, 400) : "" };
}

/** Criteria names come from the database, never from the model. Score = mean of the criterion scores. */
export function sanitizeExercise(r: any, criteria: string[]) {
  if (!r || typeof r !== "object") return null;
  const given = Array.isArray(r.criteria) ? r.criteria : [];
  const items = criteria.slice(0, 3).map((name, i) => ({
    name,
    score: clamp(given[i]?.score),
    comment: String(given[i]?.comment ?? "").slice(0, 250),
  }));
  const hasAll = items.length > 0 && given.length >= items.length &&
    items.every((_, i) => Number.isFinite(Number(given[i]?.score)));
  if (!hasAll && r.score === undefined) return null;
  const score = hasAll ? Math.round(items.reduce((a, b) => a + b.score, 0) / items.length) : clamp(r.score);
  return {
    score,
    criteria: items,
    good: String(r.good ?? "").slice(0, 400),
    improve: String(r.improve ?? "").slice(0, 400),
    example: String(r.example ?? "").slice(0, 600),
  };
}
