# GoldenTongue: paying-members-only website (Cloudflare Pages)

Only paying members and admins can open the app. Visitors see the login page, members without a membership see the
upgrade page (with Stripe checkout), and the app itself is never sent to anyone else.

```
Browser -> Cloudflare Pages
            functions/_middleware.ts  checks the session cookie on EVERY request
              public:    /login, /upgrade, /api/login, /api/signup, /api/logout, /api/config, icons, manifest
              account:   /api/me, /api/checkout   (logged in, membership not required)
              members:   everything else (/, /api/ai)   -> paying members and admins only
Supabase Auth  <- the same accounts as the mobile app (one login for site and app)
```

## Launch
Use `scripts/launch_website.sh` in the main project (it deploys this site, the backend and the AI secrets together). See `docs/LAUNCH_WEBSITE.md`.

## Who gets in
| Visitor | Result |
|---|---|
| not logged in | login page |
| logged in, under 18 or unconfirmed | no session |
| logged in, no active membership | upgrade page, API calls answer 402 |
| paying member (active, trialing, 3 days grace on payment trouble, or canceled but inside the paid period) | the app |
| admin (`public.admins`) | the app, no limits |

The decision comes from the database function `is_premium_self` (admins count as premium), checked on every request
and cached for 60 seconds for members and 10 seconds for people without a membership, so someone who just paid gets
in within seconds and an expired membership locks out within a minute. Set `REQUIRE_PREMIUM = "false"` in
`wrangler.toml` to let every confirmed member in again.

How people pay: the upgrade page starts Stripe Checkout through the Supabase function `create-checkout`, Stripe calls
the `stripe-webhook` function, the webhook writes the subscription, and the page polls `/api/me` and opens the app.

## What members get
- Sign up and login with email and password (18+ confirmation, optional Cloudflare Turnstile).
- The full app: situations, 325 pickup lines, 50 openers, 50 flirt techniques, Deep Talk, Business, practice
  exercises, voice analyzer, simulator, Charm Blueprint, scores.
- AI that really works on this site: `/api/ai` checks the session, moderates the text, applies the account's limits in
  the database (`consume_ai_request`: free members 20 per day, premium and admins unlimited) and then calls OpenAI.
- Premium and admin status come from the server (`/api/me`). Admin accounts have full access without limits.

## Security model
- Session = Supabase access token (about 1 hour) and refresh token (30 days) in `HttpOnly; Secure; SameSite=Lax`
  cookies. JavaScript on the page cannot read them. The middleware validates the token with Supabase on each request
  (cached for 60 seconds), renews it with the refresh token, and only lets confirmed adults in.
- Account deletion (`/api/delete-account`, also for members without a membership) and a public help page at `/delete-account` (needed for the Google Play Data safety form).
- Login, signup, logout and AI calls accept only same-origin POSTs (CSRF protection). Redirect targets after login are
  restricted to local paths.
- `OPENAI_API_KEY` and the Supabase keys live only in Cloudflare secrets.
- The security headers and a strict Content-Security-Policy are in `public/_headers`.

## Deploy (about 10 minutes)
Prerequisites: the Supabase project from the main app with migrations `0001` to `0008` applied (profiles, premium,
admin and AI limits come from there), the Stripe setup from the main README (prices, `create-checkout`,
`stripe-webhook`; run `supabase secrets set APP_URL=<your Pages address>` so Stripe returns to this site), Node 22, a
Cloudflare account.
```
npx wrangler login
export SUPABASE_URL=https://<project>.supabase.co
export SUPABASE_ANON_KEY=...
export OPENAI_API_KEY=sk-...
scripts/deploy.sh
```
The script runs the tests, creates the Pages project, stores the secrets and deploys. It prints an address like
`https://goldentongue-members.pages.dev`. Dashboard-only ZIP uploads do not include the server functions, so
always deploy with Wrangler (or connect the Git repository in Cloudflare Pages with output directory `public`).

Then, in the Supabase dashboard:
1. Authentication -> URL Configuration: Site URL = your Pages address.
2. Authentication -> Providers -> Email: decide whether "Confirm email" is on. If it is on, new members confirm
   through the email link first. For a closed community you can also turn off public signups and create members
   yourself (Authentication -> Users -> Add user, then they sign in here).
3. Make yourself admin: `select public.grant_admin('you@example.com');` in the SQL editor.

Optional bot protection: create a Turnstile widget for your Pages hostname, set `TURNSTILE_SITE_KEY` (this site) and
enable CAPTCHA with the Turnstile secret in Supabase Auth -> Attack Protection. Both must be on together.

Custom domain: Pages project -> Custom domains (for example `members.example.com`).

## Develop and test
```
npm install
npm test                 # 43 tests: gate, premium rules, checkout, login, signup, logout, me, ai, CSRF, refresh
cp .dev.vars.example .dev.vars && npm run dev
```
Locally Safari does not send `Secure` cookies over http; use Chrome.

## Limits
- The static bundle is only served to paying members and admins. Mobile app users pay through the App Store or
  Google Play (RevenueCat) and are recognized by the same `is_premium_self`, so one membership works on both.
- Admins are granted with `select public.grant_admin('you@example.com');` and need no payment.
- The AI limit for free members is per account, not per IP. Add Cloudflare rate limiting rules in the dashboard
  (Security -> WAF -> Rate limiting) for `/api/login` and `/api/ai` if you expect abuse.
- Tested under Node with fake Supabase, Stripe function and OpenAI services. Not deployed; the login and upgrade pages
  and a real Stripe payment have not been tried in a browser.
