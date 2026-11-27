-- Billing: entitlement rules. Subscriptions are written only by the webhook functions (service role).

-- Premium if the subscription is active, trialing or in payment retry (3 days grace),
-- or canceled but still inside the paid period.
create or replace function public.is_premium(p_user uuid default auth.uid()) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.subscriptions
    where user_id = p_user
      and (
        (status in ('active', 'trialing', 'past_due') and current_period_end + interval '3 days' > now())
        or (status = 'canceled' and current_period_end > now())
      )
  );
$$;

-- Avoid exposing other users' entitlement: a caller may only ask about themselves.
create or replace function public.is_premium_self() returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_premium(auth.uid());
$$;
revoke all on function public.is_premium(uuid) from public, anon, authenticated;
grant execute on function public.is_premium_self() to authenticated;
-- consume_ai_request (security definer, owned by the migration role) still calls is_premium internally.
