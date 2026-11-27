#!/usr/bin/env bash
# Checks everything the launch needs BEFORE anything is deployed: tools, settings and the keys themselves.
# Usage: set -a; . launch/.env; set +a; scripts/preflight.sh
# Switches: OFFLINE=1 only checks the settings (no network), SKIP_TOOLS=1 skips the tool checks.
set -uo pipefail
fail=0; warn=0
ok()   { printf 'PASS  %s\n' "$1"; }
bad()  { printf 'FAIL  %s\n' "$1"; fail=1; }
note() { printf 'WARN  %s\n' "$1"; warn=1; }
need() { if [ -n "${!1:-}" ]; then ok "$1 is set"; else bad "$1 is missing (see launch/.env.example)"; fi; }
http() { curl -s -m 20 -o /dev/null -w '%{http_code}' "$@" 2>/dev/null || echo 000; }
OPENAI_BASE_URL="${OPENAI_BASE_URL:-https://api.openai.com}"
STRIPE_BASE_URL="${STRIPE_BASE_URL:-https://api.stripe.com}"
SUPABASE_CHECK_URL="${SUPABASE_CHECK_URL:-${SUPABASE_URL:-}}"   # override only for tests

echo "== Tools"
if [ "${SKIP_TOOLS:-0}" = 1 ]; then echo "      (skipped)"; else
  for t in curl node npx supabase psql; do command -v "$t" >/dev/null && ok "$t installed" || bad "$t is not installed"; done
  if command -v node >/dev/null; then
    major=$(node -v | sed 's/^v\([0-9]*\).*/\1/'); [ "${major:-0}" -ge 22 ] && ok "Node $major (22 or newer)" || bad "Node 22 or newer is required (found $(node -v))"
  fi
fi

echo "== Settings"
for v in SUPABASE_PROJECT_REF SUPABASE_URL SUPABASE_ANON_KEY DATABASE_URL OPENAI_API_KEY PAGES_PROJECT WEB_ORIGIN; do need "$v"; done
case "${SUPABASE_URL:-}" in https://*.supabase.co) ok "SUPABASE_URL looks right";; "") ;; *) bad "SUPABASE_URL must look like https://<ref>.supabase.co";; esac
if [ -n "${SUPABASE_PROJECT_REF:-}" ] && [ -n "${SUPABASE_URL:-}" ]; then
  [ "$SUPABASE_URL" = "https://${SUPABASE_PROJECT_REF}.supabase.co" ] && ok "project id matches the URL" || bad "SUPABASE_PROJECT_REF does not match SUPABASE_URL"
fi
case "${DATABASE_URL:-}" in postgres://*|postgresql://*|"") ;; *) bad "DATABASE_URL must start with postgresql://";; esac
case "${OPENAI_API_KEY:-}" in sk-*|"") ;; *) bad "OPENAI_API_KEY should start with sk-";; esac
case "${WEB_ORIGIN:-}" in https://*|"") ;; *) bad "WEB_ORIGIN must start with https://";; esac
case "${WEB_ORIGIN:-}" in */) bad "WEB_ORIGIN must not end with a slash";; esac
[ -n "${PRIVACY_URL:-}" ] && [ -n "${TERMS_URL:-}" ] && ok "privacy and terms links set" || note "PRIVACY_URL / TERMS_URL not set (needed before the stores, recommended for the website)"
echo "== Legal pages"
scripts/check_legal.sh "${LEGAL_DIR:-docs/legal}" || fail=1
[ -n "${SUPPORT_EMAIL:-}" ] || note "SUPPORT_EMAIL not set (shown on the account deletion page)"
[ -n "${ADMIN_EMAIL:-}" ] && ok "ADMIN_EMAIL set" || note "ADMIN_EMAIL not set: nobody will have free access until you run scripts/make_admin.sh"
if [ -n "${TURNSTILE_SITE_KEY:-}" ] && [ -z "${TURNSTILE_SECRET:-}" ]; then bad "TURNSTILE_SITE_KEY is set but TURNSTILE_SECRET is missing (both are needed)"; fi
if [ -z "${STRIPE_SECRET_KEY:-}" ]; then note "Stripe not configured: only admins can get in until you add the STRIPE_* settings"
else for v in STRIPE_WEBHOOK_SECRET STRIPE_PRICE_MONTHLY STRIPE_PRICE_QUARTERLY STRIPE_PRICE_YEARLY; do need "$v"; done; fi

if [ "${OFFLINE:-0}" = 1 ] || [ "${DRY_RUN:-0}" = 1 ]; then echo "== Network checks skipped"; else
  echo "== Supabase"
  if [ -n "${SUPABASE_URL:-}" ] && [ -n "${SUPABASE_ANON_KEY:-}" ]; then
    [ "$(http -H "apikey: $SUPABASE_ANON_KEY" "$SUPABASE_CHECK_URL/auth/v1/health")" = 200 ] && ok "Auth service reachable" || bad "Auth service not reachable (check SUPABASE_URL and the anon key)"
    [ "$(http -H "apikey: $SUPABASE_ANON_KEY" "$SUPABASE_CHECK_URL/rest/v1/")" = 200 ] && ok "database API accepts the anon key" || bad "database API rejected the anon key"
  fi
  echo "== AI service"
  if [ -n "${OPENAI_API_KEY:-}" ]; then
    code=$(http -H "Authorization: Bearer $OPENAI_API_KEY" "$OPENAI_BASE_URL/v1/models")
    case "$code" in
      200) ok "OpenAI accepts the key";;
      401) bad "OpenAI rejected the key (wrong or revoked)";;
      429) bad "OpenAI says the account is out of quota: add billing credit";;
      *)   bad "OpenAI check failed (HTTP $code)";;
    esac
    if [ "$code" = 200 ]; then
      body=$(curl -s -m 20 -H "Authorization: Bearer $OPENAI_API_KEY" "$OPENAI_BASE_URL/v1/models")
      m="${COACH_MODEL:-gpt-4o-mini}"; echo "$body" | grep -q "\"$m\"" && ok "model $m is available to this key" || note "model $m not listed for this key: set COACH_MODEL (and AI_MODEL in wrangler.toml) to one you can use"
    fi
  fi
  if [ -n "${STRIPE_SECRET_KEY:-}" ]; then
    echo "== Stripe"
    for p in STRIPE_PRICE_MONTHLY STRIPE_PRICE_QUARTERLY STRIPE_PRICE_YEARLY; do
      [ -n "${!p:-}" ] && { [ "$(http -u "$STRIPE_SECRET_KEY:" "$STRIPE_BASE_URL/v1/prices/${!p}")" = 200 ] && ok "$p exists in Stripe" || bad "$p not found with this Stripe key (test and live keys have separate prices)"; }
    done
    case "$STRIPE_SECRET_KEY" in sk_live_*) note "Stripe LIVE key: real payments will be charged";; sk_test_*) ok "Stripe test key (no real money)";; esac
  fi
  echo "== Accounts logged in on this computer"
  if [ "${SKIP_TOOLS:-0}" != 1 ]; then
    supabase projects list >/dev/null 2>&1 && ok "Supabase CLI is logged in" || bad "Supabase CLI is not logged in: run 'supabase login'"
    npx --yes wrangler whoami 2>/dev/null | grep -qiE "logged in|associated with the email|account id" && ok "Cloudflare (wrangler) is logged in" || bad "Cloudflare is not logged in: run 'npx wrangler login'"
  fi
fi
echo
if [ "$fail" = 0 ]; then echo "Ready to launch$([ "$warn" = 1 ] && echo ' (with warnings)')."; else echo "Fix the FAIL lines above, then run this again."; fi
exit "$fail"
