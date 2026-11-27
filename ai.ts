// Shared helpers for the AI edge functions.
import { createClient } from "npm:@supabase/supabase-js@2.45.0";

export { cors, json } from "./http.ts";

export { clamp } from "./logic.ts";

/** Service-role client for server-only writes (scores, XP). Never expose to the app. */
export function admin() {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
}

export async function authed(req: Request) {
  const header = req.headers.get("Authorization");
  if (!header) return null;
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: header } } },
  );
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) return null;
  const { data: p } = await supabase.from("profiles").select("adult_confirmed")
    .eq("id", data.user.id).maybeSingle();
  return { supabase, user: data.user, adult: !!p?.adult_confirmed };
}

const key = () => Deno.env.get("OPENAI_API_KEY") ?? "";

export async function llmJson(system: string, user: string, maxTokens = 1000) {
  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${key()}` },
    body: JSON.stringify({
      model: Deno.env.get("COACH_MODEL") ?? "gpt-4o-mini",
      temperature: 0.8,
      max_tokens: maxTokens,
      response_format: { type: "json_object" },
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
    }),
  });
  if (!res.ok) return null;
  try {
    const c = await res.json();
    return JSON.parse(c.choices?.[0]?.message?.content ?? "null");
  } catch {
    return null;
  }
}

export async function flagged(text: string) {
  try {
    const res = await fetch("https://api.openai.com/v1/moderations", {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${key()}` },
      body: JSON.stringify({ model: "omni-moderation-latest", input: text }),
    });
    if (!res.ok) return false;
    return !!(await res.json()).results?.[0]?.flagged;
  } catch {
    return false;
  }
}

export async function transcribe(blob: Blob, filename = "audio.m4a") {
  const fd = new FormData();
  fd.append("file", new File([blob], filename));
  fd.append("model", "whisper-1");
  const res = await fetch("https://api.openai.com/v1/audio/transcriptions", {
    method: "POST",
    headers: { Authorization: `Bearer ${key()}` },
    body: fd,
  });
  if (!res.ok) return null;
  return String((await res.json()).text ?? "");
}
