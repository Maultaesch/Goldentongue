-- Progress: server-side recording of skill scores from the AI features.
-- Called only by edge functions with the service role (never by the app directly), so users
-- cannot write scores for themselves.
create or replace function public.record_skill_scores(p_user uuid, p_values jsonb, p_xp int default 0)
returns void language plpgsql security definer set search_path = public as $$
declare
  k text;
  v int;
  old_score int;
begin
  for k, v in select key, round(value::numeric)::int from jsonb_each_text(p_values) loop
    continue when k not in ('confidence','communication','flirting','deep_talk','articulation','charisma','business');
    v := greatest(0, least(100, v));
    select score into old_score from public.skill_scores
      where user_id = p_user and skill = k order by measured_at desc, id desc limit 1;
    insert into public.skill_scores (user_id, skill, score)
      values (p_user, k, case when old_score is null then v else round(old_score * 0.6 + v * 0.4)::int end);
  end loop;
  if p_xp > 0 then
    update public.gamification set xp = xp + least(p_xp, 100) where user_id = p_user;
  end if;
end $$;

revoke all on function public.record_skill_scores(uuid, jsonb, int) from public, anon, authenticated;
grant execute on function public.record_skill_scores(uuid, jsonb, int) to service_role;
