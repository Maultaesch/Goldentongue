#!/usr/bin/env bash
# One-command deploy of the API gateway (Worker) and the website (Pages).
# Prerequisites: Node 22, Flutter, `npx wrangler login` done once, and these variables:
#   SUPABASE_URL      https://<project>.supabase.co
#   SUPABASE_ANON_KEY the project's anon key
#   API_URL           https://api.example.com   (custom domain of the Worker; or the workers.dev URL)
#   WEB_ORIGIN        https://app.example.com   (custom domain of the Pages project; or the pages.dev URL)
# Optional: PAGES_PROJECT (default goldentongue-web), TURNSTILE_SITE_KEY, TURNSTILE_BASE_URL, PRIVACY_URL, TERMS_URL
set -euo pipefail
: "${SUPABASE_URL:?}" "${SUPABASE_ANON_KEY:?}" "${API_URL:?}" "${WEB_ORIGIN:?}"
PAGES_PROJECT="${PAGES_PROJECT:-goldentongue-web}"

echo "== 1/4 API gateway"
(cd cloudflare/worker && npm install --silent && npm test && \
  npx wrangler deploy --var "UPSTREAM:${SUPABASE_URL}" --var "ALLOWED_ORIGINS:${WEB_ORIGIN}")

echo "== 2/4 Web files"
scripts/setup_web.sh "${API_URL}"
flutter pub get

echo "== 3/4 Build"
flutter build web --release --pwa-strategy=none \
  --dart-define=SUPABASE_URL="${API_URL}" \
  --dart-define=SUPABASE_ANON_KEY="${SUPABASE_ANON_KEY}" \
  --dart-define=TURNSTILE_SITE_KEY="${TURNSTILE_SITE_KEY:-}" \
  --dart-define=TURNSTILE_BASE_URL="${TURNSTILE_BASE_URL:-${WEB_ORIGIN}/}" \
  --dart-define=PRIVACY_URL="${PRIVACY_URL:-}" \
  --dart-define=TERMS_URL="${TERMS_URL:-}"

echo "== 4/4 Website"
npx wrangler pages project create "${PAGES_PROJECT}" --production-branch main >/dev/null 2>&1 || true
npx wrangler pages deploy build/web --project-name "${PAGES_PROJECT}" --branch main
echo "Done. Open ${WEB_ORIGIN} on your phone and use 'Add to Home Screen'."
