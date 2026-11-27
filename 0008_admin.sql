-- Admin accounts: full access without limits.
-- The admins table has row level security and NO policies, so no client can read or change it.
-- Only the SQL editor / service role (postgres) can add admins, see grant_admin below.
create table if not exists public.admins (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  note text,
  created_at timestamptz not null default now()
);
alter table public.admins enable row level security;

create or replace function public.is_admin(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = p_user);
$$;
revoke all on function public.is_admin(uuid) from public, anon, authenticated;

-- Self-only check for the app and the edge functions.
create or replace function public.is_admin_self() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin(auth.uid());
$$;
grant execute on function public.is_admin_self() to authenticated;

-- Admins count as premium everywhere (is_premium_self, consume_ai_request, can_analyze_voice all use it),
-- so they have unlimited AI requests, unlimited voice analyses and every premium feature.
create or replace function public.is_premium(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin(p_user) or exists (
    select 1 from public.subscriptions
    where user_id = p_user
      and (
        (status in ('active', 'trialing', 'past_due') and current_period_end + interval '3 days' > now())
        or (status = 'canceled' and current_period_end > now())
      )
  );
$$;

-- Grants admin rights to an existing account (the person must have signed up first).
-- Run in the Supabase SQL editor:  select public.grant_admin('you@example.com');
create or replace function public.grant_admin(p_email text) returns void
language plpgsql security definer set search_path = public as $$
declare v_id uuid;
begin
  select id into v_id from auth.users where lower(email) = lower(p_email);
  if v_id is null then raise exception 'No account with email %', p_email; end if;
  insert into public.admins (user_id, note) values (v_id, 'granted via grant_admin') on conflict do nothing;
end $$;

create or replace function public.revoke_admin(p_email text) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from public.admins where user_id = (select id from auth.users where lower(email) = lower(p_email));
end $$;

revoke all on function public.grant_admin(text) from public, anon, authenticated;
revoke all on function public.revoke_admin(text) from public, anon, authenticated;
