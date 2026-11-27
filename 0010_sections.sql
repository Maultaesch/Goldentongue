-- Section cards (Deep Talk, Business, Speak Better) live in the database, not in the app code,
-- so nothing of the product content ships inside the free app download or the public web files.
create table if not exists public.sections (
  id uuid primary key default gen_random_uuid(),
  track text not null check (track in ('deep_talk', 'business', 'speak')),
  position int not null default 0,
  title text not null,
  tags text[] not null default '{}',
  detail_label text not null default '',
  details text[] not null default '{}',
  route text,                               -- optional in-app screen to open (for example /studio/voice)
  unique (track, title)
);
alter table public.sections enable row level security;
create policy "paid read sections" on public.sections for select to authenticated using (public.is_premium_self());
