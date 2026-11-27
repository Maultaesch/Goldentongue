-- Studio: voice analysis, conversation simulator, Charm Blueprint.

-- Voice analyses: results stored per user. Audio is deleted right after transcription.
alter table public.voice_analyses
  add column if not exists transcript text,
  add column if not exists scores jsonb,
  add column if not exists strengths text[] not null default '{}',
  add column if not exists weaknesses text[] not null default '{}',
  add column if not exists tips text[] not null default '{}',
  add column if not exists impression text,
  add column if not exists note text,
  add column if not exists avg int;
create policy "own voice insert" on public.voice_analyses for insert with check (user_id = auth.uid());

-- Free plan: 1 analysis per week. Premium: unlimited.
create or replace function public.can_analyze_voice() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_premium(auth.uid())
      or not exists (
        select 1 from public.voice_analyses
        where user_id = auth.uid() and created_at > now() - interval '7 days'
      );
$$;
grant execute on function public.can_analyze_voice() to authenticated;

-- Private audio bucket, one folder per user.
insert into storage.buckets (id, name, public) values ('voice', 'voice', false)
  on conflict (id) do nothing;
create policy "voice upload own" on storage.objects for insert to authenticated
  with check (bucket_id = 'voice' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "voice read own" on storage.objects for select to authenticated
  using (bucket_id = 'voice' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "voice delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'voice' and (storage.foldername(name))[1] = auth.uid()::text);

-- Simulator: reuse sessions and messages; add feedback per message and a mode.
alter table public.sessions add column if not exists mode text not null default 'chat'
  check (mode in ('chat', 'call'));
alter table public.sessions add column if not exists ended_at timestamptz;
alter table public.messages add column if not exists feedback jsonb;
create index if not exists messages_session_idx on public.messages (session_id, created_at);

-- Charm Blueprint: one row per generated plan.
create table if not exists public.blueprints (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  data jsonb not null,
  created_at timestamptz not null default now()
);
alter table public.blueprints enable row level security;
create policy "own blueprints read" on public.blueprints for select using (user_id = auth.uid());
create policy "own blueprints insert" on public.blueprints for insert with check (user_id = auth.uid());

-- Same self-only entitlement helper is used by the edge functions: is_premium_self() (migration 0003).
-- Keep simulator and blueprint premium-only by checking it server-side.
