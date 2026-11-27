-- Deep Talk and Business practice exercises with AI evaluation.
create table if not exists public.exercises (
  id uuid primary key default gen_random_uuid(),
  track text not null check (track in ('deep_talk', 'business')),
  category text not null,
  title text not null,
  prompt text not null,
  criteria text[] not null,
  position int not null default 0,
  unique (track, category, title)
);
alter table public.exercises enable row level security;
create policy "exercises read" on public.exercises for select to authenticated using (true);

-- Attempts are written only by the exercise-evaluate edge function (service role), so scores cannot be forged.
create table if not exists public.exercise_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  exercise_id uuid not null references public.exercises (id) on delete cascade,
  answer text not null,
  score int not null check (score between 0 and 100),
  result jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.exercise_attempts enable row level security;
create policy "own attempts read" on public.exercise_attempts for select using (user_id = auth.uid());
create index if not exists exercise_attempts_user_idx on public.exercise_attempts (user_id, created_at desc);
