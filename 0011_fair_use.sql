-- Fair use: paying members get a high daily cap on AI requests and voice analyses so that a bug, a stolen
-- login or abuse cannot run up the AI bill. Admins stay unlimited. Accounts without a membership cannot
-- reach the AI at all (pay first); their limit only matters if REQUIRE_PREMIUM is switched off.

drop function if exists public.consume_ai_request(int);

create or replace function public.consume_ai_request(p_free_limit int default 5, p_member_limit int default 300)
returns boolean language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
  v_limit int;
begin
  if v_uid is null then return false; end if;
  insert into public.ai_usage (user_id, day, requests) values (v_uid, current_date, 0)
    on conflict (user_id, day) do nothing;
  select requests into v_count from public.ai_usage
    where user_id = v_uid and day = current_date for update;
  v_limit := case
    when public.is_admin(v_uid) then null             -- admins: unlimited
    when public.is_premium(v_uid) then p_member_limit -- members: fair use cap
    else p_free_limit
  end;
  if v_limit is not null and v_count >= v_limit then return false; end if;
  update public.ai_usage set requests = requests + 1 where user_id = v_uid and day = current_date;
  return true;
end $$;

revoke all on function public.consume_ai_request(int, int) from public, anon;
grant execute on function public.consume_ai_request(int, int) to authenticated;

-- Voice analyses: admins unlimited, members up to 20 per day, accounts without a membership 1 per week.
create or replace function public.can_analyze_voice() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin(auth.uid())
      or case when public.is_premium(auth.uid())
           then (select count(*) from public.voice_analyses
                 where user_id = auth.uid() and created_at > now() - interval '1 day') < 20
           else not exists (select 1 from public.voice_analyses
                 where user_id = auth.uid() and created_at > now() - interval '7 days')
         end;
$$;
grant execute on function public.can_analyze_voice() to authenticated;
