#!/usr/bin/env bash
# Checks a LIVE deployment from the outside: gateway, backend, pay-first rules and the members website.
# Usage (with the Cloudflare gateway; for a website-only launch set API_URL to the Supabase URL and SKIP_GATEWAY=1):
#   API_URL=https://api.example.com SUPABASE_ANON_KEY=... WEB_ORIGIN=https://members.example.com scripts/verify_deployment.sh
# Optional: TEST_EMAIL and TEST_PASSWORD of a test account, EXPECT_MEMBER=yes|no (default no)
set -uo pipefail
: "${API_URL:?}" "${SUPABASE_ANON_KEY:?}" "${WEB_ORIGIN:?}"
API_URL="${API_URL%/}"; WEB_ORIGIN="${WEB_ORIGIN%/}"
fail=0; body=$(mktemp); hdr=$(mktemp); trap 'rm -f "$body" "$hdr"' EXIT

req() { # method url [curl args...] -> prints status, leaves body and headers in files
  local m="$1" u="$2"; shift 2
  curl -s -m 30 -X "$m" -o "$body" -D "$hdr" -w '%{http_code}' "$@" "$u"
}
check() { # name expected actual
  if [ "$2" = "$3" ]; then printf 'PASS  %s\n' "$1"; else printf 'FAIL  %s (expected %s, got %s)\n' "$1" "$2" "$3"; fail=1; fi
}
no_leak() { # name needle  (the response body must not contain the needle)
  if grep -q "$2" "$body"; then printf 'FAIL  %s (content leaked)\n' "$1"; fail=1; else printf 'PASS  %s\n' "$1"; fi
}

echo "== Backend ($API_URL)"
[ "${SKIP_GATEWAY:-0}" = 1 ] || check "gateway health"                          200 "$(req GET "$API_URL/healthz")"
check "database reachable through the gateway"  200 "$(req GET "$API_URL/rest/v1/" -H "apikey: $SUPABASE_ANON_KEY")"
check "edge functions need a login"             401 "$(req POST "$API_URL/functions/v1/coach" -H "apikey: $SUPABASE_ANON_KEY" -H 'Content-Type: application/json' -d '{}')"
if [ "${SKIP_GATEWAY:-0}" != 1 ]; then
  check "webhooks are not exposed by the gateway" 404 "$(req POST "$API_URL/functions/v1/stripe-webhook" -d '{}')"
  check "auth admin API is blocked"               403 "$(req GET "$API_URL/auth/v1/admin/users" -H "apikey: $SUPABASE_ANON_KEY")"
fi
req GET "$API_URL/rest/v1/lines?select=text&limit=1" -H "apikey: $SUPABASE_ANON_KEY" >/dev/null
no_leak "pay first: anonymous visitors cannot read content" '"text"'
req GET "$API_URL/rest/v1/sections?select=title&limit=1" -H "apikey: $SUPABASE_ANON_KEY" >/dev/null
no_leak "pay first: anonymous visitors cannot read section cards" '"title"'
req GET "$API_URL/rest/v1/exercises?select=title&limit=1" -H "apikey: $SUPABASE_ANON_KEY" >/dev/null
no_leak "pay first: anonymous visitors cannot read exercises" '"title"'

echo "== Members website ($WEB_ORIGIN)"
code=$(req GET "$WEB_ORIGIN/" -H 'Accept: text/html'); check "front page redirects visitors" 302 "$code"
if grep -qi '^location: .*login' "$hdr"; then echo "PASS  redirect goes to the login page"; else echo "FAIL  redirect does not go to /login"; fail=1; fi
check "app file is not public"                  302 "$(req GET "$WEB_ORIGIN/index.html" -H 'Accept: text/html')"
req GET "$WEB_ORIGIN/" -H 'Accept: text/html' >/dev/null; no_leak "front page body has no app content" 'Practice and get scored'
check "login page is public"                    200 "$(req GET "$WEB_ORIGIN/login")"
check "account API needs a login"               401 "$(req GET "$WEB_ORIGIN/api/me" -H 'Accept: application/json')"
check "AI API needs a login"                    401 "$(req POST "$WEB_ORIGIN/api/ai" -H 'Content-Type: application/json' -d '{"prompt":"Return JSON please"}')"
check "cross-site login is refused"             403 "$(req POST "$WEB_ORIGIN/api/login" -H 'Origin: https://evil.example' -H 'Content-Type: application/json' -d '{"email":"a@b.co","password":"x"}')"

if [ -n "${TEST_EMAIL:-}" ] && [ -n "${TEST_PASSWORD:-}" ]; then
  echo "== Test account (${TEST_EMAIL})"
  jar=$(mktemp)
  code=$(curl -s -m 30 -c "$jar" -o "$body" -w '%{http_code}' -X POST "$WEB_ORIGIN/api/login" -H "Origin: $WEB_ORIGIN" -H 'Content-Type: application/json' \
    -d "{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}")
  check "test login" 200 "$code"
  code=$(curl -s -m 30 -b "$jar" -o "$body" -w '%{http_code}' -H 'Accept: text/html' "$WEB_ORIGIN/")
  if [ "${EXPECT_MEMBER:-no}" = "yes" ]; then check "member (or admin) reaches the app" 200 "$code"
  else check "account without membership is sent to the upgrade page" 302 "$code"; fi
  rm -f "$jar"
fi
echo
if [ "$fail" = 0 ]; then echo "All checks passed."; else echo "Some checks FAILED."; fi
exit "$fail"
