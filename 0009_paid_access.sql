-- Pay first: all product content is readable only with an active membership (or an admin account).
-- Before this migration any signed-in account could read the content tables through the API.
-- is_premium_self() is true for paying members, trial users, the payment grace period and admins.

drop policy if exists "content read lines" on public.lines;
drop policy if exists "content read challenges" on public.challenges;
drop policy if exists "exercises read" on public.exercises;

create policy "paid read lines" on public.lines for select to authenticated using (public.is_premium_self());
create policy "paid read challenges" on public.challenges for select to authenticated using (public.is_premium_self());
create policy "paid read exercises" on public.exercises for select to authenticated using (public.is_premium_self());

-- Voice uploads need a membership too.
drop policy if exists "voice upload own" on storage.objects;
create policy "voice upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'voice' and (storage.foldername(name))[1] = auth.uid()::text and public.is_premium_self());

-- Earning XP and scores needs a membership (the function is security definer, so check inside).
create or replace function public.complete_challenge(p_challenge_id uuid, p_result int) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_skill text;
  v_last date;
  v_streak int;
  v_old int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if not public.is_premium(v_uid) then raise exception 'membership required'; end if;
  if p_result not between 1 and 3 then raise exception 'invalid result'; end if;
  select skill into v_skill from public.challenges where id = p_challenge_id;
  if v_skill is null then raise exception 'unknown challenge'; end if;

  insert into public.user_challenges (user_id, challenge_id, result)
  values (v_uid, p_challenge_id, p_result)
  on conflict (user_id, day) do nothing;
  if not found then return; end if;           -- already completed today

  select last_active, streak into v_last, v_streak from public.gamification where user_id = v_uid;
  v_streak := case when v_last = current_date - 1 then v_streak + 1 else 1 end;
  update public.gamification
     set xp = xp + 20 + p_result * 5 + least(v_streak, 7) * 2,
         streak = v_streak,
         longest_streak = greatest(longest_streak, v_streak),
         last_active = current_date
   where user_id = v_uid;

  select score into v_old from public.skill_scores
    where user_id = v_uid and skill = v_skill order by measured_at desc, id desc limit 1;
  insert into public.skill_scores (user_id, skill, score)
    values (v_uid, v_skill, least(100, coalesce(v_old, 40) + 3));
  select score into v_old from public.skill_scores
    where user_id = v_uid and skill = 'confidence' order by measured_at desc, id desc limit 1;
  insert into public.skill_scores (user_id, skill, score)
    values (v_uid, 'confidence', least(100, coalesce(v_old, 40) + 2));
end $$;

revoke all on function public.complete_challenge(uuid, int) from public, anon;
grant execute on function public.complete_challenge(uuid, int) to authenticated;
