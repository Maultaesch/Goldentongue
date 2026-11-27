-- GoldenTongue: initial schema, RLS and server-side functions.


-- ---------- Tables ----------
create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text,
  adult_confirmed boolean not null default false,
  goals text[] not null default '{}',
  experience text,
  personality text,
  confidence_level int check (confidence_level between 1 and 10),
  locale text not null default 'en',
  created_at timestamptz not null default now()
);

create table public.subscriptions (
  user_id uuid not null references public.profiles (id) on delete cascade,
  plan text not null check (plan in ('monthly', 'quarterly', 'yearly')),
  status text not null,                       -- active, trialing, past_due, canceled
  provider text not null check (provider in ('stripe', 'apple', 'google')),
  provider_ref text not null,
  current_period_end timestamptz not null,
  primary key (user_id, provider_ref)
);

create table public.lines (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  text text not null,
  why text,
  recovery text,
  scores jsonb not null default '{}',
  alternatives text[] not null default '{}',
  example jsonb,
  popularity int not null default 0,
  premium boolean not null default false
);
create index lines_category_idx on public.lines (category, popularity desc);

create table public.favorites (
  user_id uuid not null references public.profiles (id) on delete cascade,
  line_id uuid not null references public.lines (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, line_id)
);

create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  kind text not null default 'daily',
  text text not null unique,
  skill text not null default 'communication',
  difficulty int not null default 1
);

create table public.user_challenges (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  challenge_id uuid not null references public.challenges (id),
  day date not null default current_date,
  result int not null check (result between 1 and 3),
  unique (user_id, day)
);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('coach', 'simulator', 'voice', 'story')),
  persona text,
  started_at timestamptz not null default now(),
  score jsonb,
  summary text
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

create table public.voice_analyses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  audio_path text,
  delete_after timestamptz not null default now() + interval '24 hours',
  metrics jsonb,
  feedback text,
  created_at timestamptz not null default now()
);

create table public.skill_scores (
  id bigint generated always as identity primary key,
  user_id uuid not null references public.profiles (id) on delete cascade,
  skill text not null check (skill in
    ('confidence','communication','flirting','deep_talk','articulation','charisma','business')),
  score int not null check (score between 0 and 100),
  measured_at timestamptz not null default now()
);
create index skill_scores_user_idx on public.skill_scores (user_id, skill, measured_at desc);

create table public.gamification (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  xp int not null default 0,
  streak int not null default 0,
  longest_streak int not null default 0,
  last_active date
);

create table public.ai_usage (
  user_id uuid not null references public.profiles (id) on delete cascade,
  day date not null default current_date,
  requests int not null default 0,
  tokens int not null default 0,
  primary key (user_id, day)
);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  session_id uuid references public.sessions (id) on delete set null,
  reason text not null,
  created_at timestamptz not null default now()
);

-- ---------- Row level security ----------
alter table public.profiles enable row level security;
alter table public.subscriptions enable row level security;
alter table public.lines enable row level security;
alter table public.favorites enable row level security;
alter table public.challenges enable row level security;
alter table public.user_challenges enable row level security;
alter table public.sessions enable row level security;
alter table public.messages enable row level security;
alter table public.voice_analyses enable row level security;
alter table public.skill_scores enable row level security;
alter table public.gamification enable row level security;
alter table public.ai_usage enable row level security;
alter table public.reports enable row level security;

create policy "own profile read"   on public.profiles for select using (id = auth.uid());
create policy "own profile update" on public.profiles for update using (id = auth.uid())
  with check (id = auth.uid());

create policy "own subscription read" on public.subscriptions for select using (user_id = auth.uid());

create policy "content read lines"      on public.lines      for select to authenticated using (true);
create policy "content read challenges" on public.challenges for select to authenticated using (true);

create policy "own favorites read"   on public.favorites for select using (user_id = auth.uid());
create policy "own favorites insert" on public.favorites for insert with check (user_id = auth.uid());
create policy "own favorites delete" on public.favorites for delete using (user_id = auth.uid());

create policy "own challenges read" on public.user_challenges for select using (user_id = auth.uid());

create policy "own sessions all" on public.sessions for all using (user_id = auth.uid())
  with check (user_id = auth.uid());
create policy "own messages all" on public.messages for all
  using (exists (select 1 from public.sessions s where s.id = session_id and s.user_id = auth.uid()))
  with check (exists (select 1 from public.sessions s where s.id = session_id and s.user_id = auth.uid()));

create policy "own voice read" on public.voice_analyses for select using (user_id = auth.uid());
create policy "own scores read" on public.skill_scores for select using (user_id = auth.uid());
create policy "own game read" on public.gamification for select using (user_id = auth.uid());
create policy "own report insert" on public.reports for insert with check (user_id = auth.uid());
-- subscriptions, ai_usage, gamification and skill_scores are written only by
-- security definer functions or the service role (edge functions, webhooks).

-- ---------- Functions ----------
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, display_name, adult_confirmed)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)),
    coalesce((new.raw_user_meta_data ->> 'adult_confirmed')::boolean, false)
  );
  insert into public.gamification (user_id) values (new.id);
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create or replace function public.is_premium(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.subscriptions
    where user_id = p_user
      and status in ('active', 'trialing', 'past_due')
      and current_period_end + interval '3 days' > now()
  );
$$;

-- Returns true and counts the request if the caller may use the AI today.
create or replace function public.consume_ai_request(p_free_limit int default 5) returns boolean
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_count int;
begin
  if v_uid is null then return false; end if;
  insert into public.ai_usage (user_id, day, requests) values (v_uid, current_date, 0)
    on conflict (user_id, day) do nothing;
  select requests into v_count from public.ai_usage
    where user_id = v_uid and day = current_date for update;
  if not public.is_premium(v_uid) and v_count >= p_free_limit then
    return false;
  end if;
  update public.ai_usage set requests = requests + 1
    where user_id = v_uid and day = current_date;
  return true;
end $$;

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
    where user_id = v_uid and skill = v_skill order by measured_at desc limit 1;
  insert into public.skill_scores (user_id, skill, score)
    values (v_uid, v_skill, least(100, coalesce(v_old, 40) + 3));
  select score into v_old from public.skill_scores
    where user_id = v_uid and skill = 'confidence' order by measured_at desc limit 1;
  insert into public.skill_scores (user_id, skill, score)
    values (v_uid, 'confidence', least(100, coalesce(v_old, 40) + 2));
end $$;

revoke all on function public.consume_ai_request(int) from public, anon;
revoke all on function public.complete_challenge(uuid, int) from public, anon;
grant execute on function public.consume_ai_request(int) to authenticated;
grant execute on function public.complete_challenge(uuid, int) to authenticated;
grant execute on function public.is_premium(uuid) to authenticated;
