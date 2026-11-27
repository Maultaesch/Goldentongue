#!/usr/bin/env bash
# Launches the GoldenTongue members website WITH the AI service, from your computer, in one command.
#   1. cp launch/.env.example launch/.env   and fill it in
#   2. DRY_RUN=1 scripts/launch_website.sh  (shows what would happen, changes nothing)
#   3. scripts/launch_website.sh            (does it)
# Needs: Node 22, Supabase CLI (`supabase login`), `npx wrangler login`, psql. See docs/LAUNCH_WEBSITE.md.
set -euo pipefail
cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-launch/.env}"
[ -f "$ENV_FILE" ] || { echo "Create $ENV_FILE first: cp launch/.env.example launch/.env, then fill it in."; exit 1; }
set -a
# shellcheck source=/dev/null
. "$ENV_FILE"
set +a
DRY_RUN="${DRY_RUN:-0}"; export DRY_RUN
run()  { if [ "$DRY_RUN" = 1 ]; then printf '[dry run] %s\n' "$*"; else "$@"; fi; }
step() { printf '\n== %s\n' "$*"; }

step "1/7 Checking your settings and keys"
scripts/preflight.sh

step "2/7 Database, functions and content"
SUPABASE_PROJECT_REF="$SUPABASE_PROJECT_REF" DATABASE_URL="$DATABASE_URL" run scripts/deploy_backend.sh

step "3/7 Secrets for the AI and payment functions"
secrets=("OPENAI_API_KEY=$OPENAI_API_KEY" "APP_URL=$WEB_ORIGIN"
         "COACH_MODEL=${COACH_MODEL:-gpt-4o-mini}" "FREE_DAILY_LIMIT=${FREE_DAILY_LIMIT:-5}" "MEMBER_DAILY_LIMIT=${MEMBER_DAILY_LIMIT:-300}")
if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
  secrets+=("STRIPE_SECRET_KEY=$STRIPE_SECRET_KEY" "STRIPE_WEBHOOK_SECRET=$STRIPE_WEBHOOK_SECRET"
            "STRIPE_PRICE_MONTHLY=$STRIPE_PRICE_MONTHLY" "STRIPE_PRICE_QUARTERLY=$STRIPE_PRICE_QUARTERLY" "STRIPE_PRICE_YEARLY=$STRIPE_PRICE_YEARLY")
fi
[ -n "${REVENUECAT_WEBHOOK_AUTH:-}" ] && secrets+=("REVENUECAT_WEBHOOK_AUTH=$REVENUECAT_WEBHOOK_AUTH")
if [ "$DRY_RUN" = 1 ]; then
  printf '[dry run] supabase secrets set (%s values: %s)\n' "${#secrets[@]}" "$(printf '%s\n' "${secrets[@]}" | cut -d= -f1 | tr '\n' ' ')"
else
  supabase secrets set --project-ref "$SUPABASE_PROJECT_REF" "${secrets[@]}"
fi

step "4/7 Supabase sign-in settings (site address, redirects, captcha)"
if [ -n "${SUPABASE_ACCESS_TOKEN:-}" ]; then
  body=$(printf '{"site_url":"%s","uri_allow_list":"%s,io.goldentongue://login-callback"' "$WEB_ORIGIN" "$WEB_ORIGIN")
  if [ -n "${TURNSTILE_SECRET:-}" ]; then
    body="$body$(printf ',"security_captcha_enabled":true,"security_captcha_provider":"turnstile","security_captcha_secret":"%s"' "$TURNSTILE_SECRET")"
  fi
  body="$body}"
  if [ "$DRY_RUN" = 1 ]; then echo "[dry run] PATCH https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/config/auth (site_url, uri_allow_list${TURNSTILE_SECRET:+, captcha})"
  else
    code=$(curl -s -o /tmp/gt_auth_patch.txt -w '%{http_code}' -X PATCH "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/config/auth" \
      -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" -d "$body" || echo 000)
    if [ "$code" = 200 ]; then echo "Sign-in settings updated."; else echo "WARNING: could not update sign-in settings (HTTP $code). Set them by hand: Authentication -> URL Configuration: Site URL $WEB_ORIGIN, redirect URLs $WEB_ORIGIN and io.goldentongue://login-callback."; fi
  fi
else
  echo "No SUPABASE_ACCESS_TOKEN: set these by hand in Supabase -> Authentication -> URL Configuration:"
  echo "  Site URL: $WEB_ORIGIN"
  echo "  Redirect URLs: $WEB_ORIGIN and io.goldentongue://login-callback"
  [ -n "${TURNSTILE_SECRET:-}" ] && echo "  Attack Protection: enable CAPTCHA, provider Turnstile, paste TURNSTILE_SECRET"
fi

step "5/7 Website on Cloudflare Pages"
if [ "$DRY_RUN" = 1 ]; then
  echo "[dry run] cloudflare/members-site/scripts/deploy.sh (project $PAGES_PROJECT, secrets: SUPABASE_URL SUPABASE_ANON_KEY OPENAI_API_KEY${TURNSTILE_SITE_KEY:+ TURNSTILE_SITE_KEY} PRIVACY_URL TERMS_URL SUPPORT_EMAIL)"
else
  out=$(mktemp); trap 'rm -f "$out"' EXIT
  PAGES_PROJECT="$PAGES_PROJECT" cloudflare/members-site/scripts/deploy.sh | tee "$out"
  url=$(grep -oE 'https://[a-z0-9.-]+\.pages\.dev' "$out" | tail -1 || true)
  if [ -n "$url" ] && [ "${url#https://*.}" != "${WEB_ORIGIN#https://*.}" ] && [ "$url" != "$WEB_ORIGIN" ]; then
    echo "NOTE: Cloudflare's address is $url but WEB_ORIGIN is $WEB_ORIGIN. Set WEB_ORIGIN=$url in launch/.env and run this script again so sign-in and payments return to the right place."
  fi
fi

step "6/7 Admin account"
echo "Sign up now at $WEB_ORIGIN/login with ${ADMIN_EMAIL:-your email}, confirm the email if asked, then run:"
echo "  DATABASE_URL=... scripts/make_admin.sh ${ADMIN_EMAIL:-you@example.com}"

step "7/7 Checking the live website from outside"
API_URL="$SUPABASE_URL" SKIP_GATEWAY=1 SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" WEB_ORIGIN="$WEB_ORIGIN" run scripts/verify_deployment.sh
echo; echo "Launch finished. Next: docs/LAUNCH_WEBSITE.md, section 'Test it yourself'."
