-- pgTAP tests. Run with: supabase test db
begin;
select plan(42);

-- Two users; the signup trigger creates profiles and gamification rows.
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'a@example.com', '{"adult_confirmed": true}'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'b@example.com', '{"adult_confirmed": true}');

select is((select count(*)::int from public.profiles where id in
  ('aaaaaaaa-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002')), 2,
  'signup trigger creates profiles');
select is((select count(*)::int from public.gamification where user_id = 'aaaaaaaa-0000-0000-0000-000000000001'), 1,
  'signup trigger creates the gamification row');

-- ---------- entitlement (is_premium is callable as the migration owner) ----------
select is(public.is_premium('aaaaaaaa-0000-0000-0000-000000000001'), false, 'no subscription = not premium');

insert into public.subscriptions (user_id, plan, status, provider, provider_ref, current_period_end)
  values ('aaaaaaaa-0000-0000-0000-000000000001', 'monthly', 'active', 'stripe', 'sub_1', now() + interval '10 days');
select is(public.is_premium('aaaaaaaa-0000-0000-0000-000000000001'), true, 'active subscription = premium');

update public.subscriptions set status = 'canceled' where provider_ref = 'sub_1';
select is(public.is_premium('aaaaaaaa-0000-0000-0000-000000000001'), true, 'canceled but inside the paid period = premium');

update public.subscriptions set current_period_end = now() - interval '1 day' where provider_ref = 'sub_1';
select is(public.is_premium('aaaaaaaa-0000-0000-0000-000000000001'), false, 'canceled and expired = not premium');

update public.subscriptions set status = 'past_due', current_period_end = now() - interval '1 day' where provider_ref = 'sub_1';
select is(public.is_premium('aaaaaaaa-0000-0000-0000-000000000001'), true, 'past_due inside the 3 day grace = premium');

update public.subscriptions set current_period_end = now() - interval '5 days' where provider_ref = 'sub_1';
select is(public.is_premium('aaaaaaaa-0000-0000-0000-000000000001'), false, 'past_due beyond the grace = not premium');

-- ---------- free AI limit for user B ----------
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;

select is((select count(*)::int from (
  select public.consume_ai_request(5) as ok from generate_series(1, 5)) t where ok), 5, 'free user gets 5 requests');
select is(public.consume_ai_request(5), false, 'sixth free request is refused');

-- ---------- free voice analysis: 1 per week ----------
select is(public.can_analyze_voice(), true, 'first voice analysis is allowed');
reset role;
insert into public.voice_analyses (user_id, scores, avg) values ('bbbbbbbb-0000-0000-0000-000000000002', '{}', 60);
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select is(public.can_analyze_voice(), false, 'second analysis within a week is refused');

-- ---------- row level security ----------
select is((select count(*)::int from public.voice_analyses), 1, 'user B sees only their own analyses');
select is((select count(*)::int from public.subscriptions), 0, 'user B cannot see other users subscriptions');
reset role;

-- ---------- record_skill_scores blending (service role only) ----------
select public.record_skill_scores('bbbbbbbb-0000-0000-0000-000000000002', '{"articulation": 80, "bogus": 90}', 30);
select public.record_skill_scores('bbbbbbbb-0000-0000-0000-000000000002', '{"articulation": 40}', 0);
select is((select score from public.skill_scores where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'
  and skill = 'articulation' order by measured_at desc, id desc limit 1), 64,
  'second value is blended: round(80*0.6 + 40*0.4) = 64');
select is((select xp from public.gamification where user_id = 'bbbbbbbb-0000-0000-0000-000000000002'), 30,
  'xp is awarded once and unknown skills are ignored');

-- ---------- exercises (Deep Talk and Business) ----------
insert into public.exercises (id, track, category, title, prompt, criteria, position)
  values ('eeeeeeee-0000-0000-0000-000000000001', 'deep_talk', 'Dreams', 'Test exercise', 'Prompt', array['a', 'b', 'c'], 1);

select throws_ok(
  $$insert into public.exercises (track, category, title, prompt, criteria)
    values ('deep_talk', 'Dreams', 'Test exercise', 'x', array['a'])$$,
  '23505', null, 'duplicate exercise titles in a category are rejected');
select throws_ok(
  $$insert into public.exercises (track, category, title, prompt, criteria)
    values ('flirting', 'X', 'Y', 'x', array['a'])$$,
  '23514', null, 'unknown tracks are rejected');

insert into public.subscriptions (user_id, plan, status, provider, provider_ref, current_period_end)
  values ('bbbbbbbb-0000-0000-0000-000000000002', 'monthly', 'active', 'stripe', 'sub_b', now() + interval '10 days');
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.exercises where id = 'eeeeeeee-0000-0000-0000-000000000001'), 1,
  'paying members can read exercises');
select throws_ok(
  $$insert into public.exercise_attempts (user_id, exercise_id, answer, score, result)
    values ('bbbbbbbb-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000001', 'my answer', 99, '{}')$$,
  '42501', null, 'users cannot write attempts or scores themselves');
reset role;

insert into public.exercise_attempts (user_id, exercise_id, answer, score, result) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001', 'answer a', 60, '{}'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'eeeeeeee-0000-0000-0000-000000000001', 'answer b', 70, '{}');
select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.exercise_attempts), 1, 'users only see their own attempts');
reset role;

select public.record_skill_scores('bbbbbbbb-0000-0000-0000-000000000002', '{"deep_talk": 70, "business": 55}', 20);
select is((select score from public.skill_scores where user_id = 'bbbbbbbb-0000-0000-0000-000000000002' and skill = 'deep_talk'), 70,
  'deep_talk scores are recorded');
select is((select score from public.skill_scores where user_id = 'bbbbbbbb-0000-0000-0000-000000000002' and skill = 'business'), 55,
  'business scores are recorded');

-- ---------- admin accounts: unlimited, invisible to users ----------
insert into public.admins (user_id) values ('aaaaaaaa-0000-0000-0000-000000000001');
select is(public.is_premium('aaaaaaaa-0000-0000-0000-000000000001'), true, 'admins count as premium');

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.is_admin_self(), true, 'is_admin_self is true for an admin');
select is((select count(*)::int from (
  select public.consume_ai_request(5) as ok from generate_series(1, 8)) t where ok), 8,
  'admins are not limited by the free AI counter');
reset role;

insert into public.voice_analyses (user_id, scores, avg) values ('aaaaaaaa-0000-0000-0000-000000000001', '{}', 60);
select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.can_analyze_voice(), true, 'admins can analyze voice more than once a week');
reset role;

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select is(public.is_admin_self(), false, 'is_admin_self is false for normal users');
select is((select count(*)::int from public.admins), 0, 'the admin list is invisible to users');
reset role;

-- ---------- pay first: content is invisible without a membership ----------
insert into auth.users (id, email, raw_user_meta_data)
  values ('cccccccc-0000-0000-0000-000000000003', 'c@example.com', '{"adult_confirmed": true}');
insert into public.lines (collection, category, text) values ('library', 'Funny', 'paywalled line');
insert into public.challenges (text, skill) values ('paywalled challenge', 'confidence');
insert into public.sections (track, position, title) values ('deep_talk', 99, 'paywalled section');

select set_config('request.jwt.claims', '{"sub":"cccccccc-0000-0000-0000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.lines where text = 'paywalled line'), 0, 'accounts without a membership cannot read lines');
select is((select count(*)::int from public.exercises), 0, 'accounts without a membership cannot read exercises');
select is((select count(*)::int from public.challenges where text = 'paywalled challenge'), 0, 'accounts without a membership cannot read challenges');
select is((select count(*)::int from public.sections where title = 'paywalled section'), 0, 'accounts without a membership cannot read section cards');
select throws_ok($$select public.complete_challenge('00000000-0000-0000-0000-000000000000', 3)$$, 'P0001', null,
  'accounts without a membership cannot earn XP');
reset role;

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.lines where text = 'paywalled line'), 1, 'admins can read content without paying');
select is((select count(*)::int from public.sections where title = 'paywalled section'), 1, 'admins can read section cards');
reset role;

select set_config('request.jwt.claims', '{"sub":"bbbbbbbb-0000-0000-0000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.lines where text = 'paywalled line'), 1, 'paying members can read content');
select is((select count(*)::int from public.sections where title = 'paywalled section'), 1, 'paying members can read section cards');
reset role;

-- ---------- fair use: members have a high daily cap, admins none ----------
insert into auth.users (id, email, raw_user_meta_data)
  values ('dddddddd-0000-0000-0000-000000000004', 'd@example.com', '{"adult_confirmed": true}');
insert into public.subscriptions (user_id, plan, status, provider, provider_ref, current_period_end)
  values ('dddddddd-0000-0000-0000-000000000004', 'monthly', 'active', 'stripe', 'sub_d', now() + interval '10 days');

select set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from (select public.consume_ai_request(5, 3) as ok from generate_series(1, 3)) t where ok), 3,
  'a member can use the AI up to the member cap');
select is(public.consume_ai_request(5, 3), false, 'the request above the member cap is refused');
reset role;

select set_config('request.jwt.claims', '{"sub":"aaaaaaaa-0000-0000-0000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from (select public.consume_ai_request(1, 1) as ok from generate_series(1, 10)) t where ok), 10,
  'admins are never capped');
reset role;

insert into public.voice_analyses (user_id, scores, avg)
  select 'dddddddd-0000-0000-0000-000000000004', '{}', 50 from generate_series(1, 20);
select set_config('request.jwt.claims', '{"sub":"dddddddd-0000-0000-0000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select is(public.can_analyze_voice(), false, 'members have a daily cap on voice analyses');
reset role;

select * from finish();
rollback;
