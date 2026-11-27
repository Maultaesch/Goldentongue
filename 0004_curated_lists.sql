-- Curated lists: 50 best openers and 50 flirt techniques.
alter table public.lines drop constraint if exists lines_collection_check;
alter table public.lines add constraint lines_collection_check
  check (collection in ('social', 'library', 'opener', 'flirt'));

alter table public.lines
  add column if not exists title text,
  add column if not exists position int,
  add column if not exists best_situation text,
  add column if not exists difficulty text,
  add column if not exists confidence_required int check (confidence_required between 1 and 5),
  add column if not exists responses text[] not null default '{}',
  add column if not exists voice_delivery text,
  add column if not exists red_flags text,
  add column if not exists success_estimate int check (success_estimate between 0 and 100),
  add column if not exists estimated boolean not null default true;

create index if not exists lines_position_idx on public.lines (collection, position);
