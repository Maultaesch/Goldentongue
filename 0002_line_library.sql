-- Separate the pickup line library from the short social tips used in the Social tabs.
alter table public.lines
  add column if not exists collection text not null default 'social'
  check (collection in ('social', 'library'));

-- Needed for idempotent seeding.
create unique index if not exists lines_unique_idx on public.lines (collection, category, text);
create index if not exists lines_collection_idx on public.lines (collection, category, popularity desc);
