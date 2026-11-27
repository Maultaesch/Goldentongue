#!/usr/bin/env bash
# Deploys the member site (static app + login + server functions) to Cloudflare Pages.
# Needs: Node 22, `npx wrangler login` done once, and these variables:
#   SUPABASE_URL, SUPABASE_ANON_KEY            (same Supabase project as the app)
#   OPENAI_API_KEY                             (for the AI features; optional)
#   TURNSTILE_SITE_KEY                         (optional; also enable CAPTCHA in Supabase Auth)
#   PRIVACY_URL, TERMS_URL, SUPPORT_EMAIL      (links and contact shown on the login, upgrade and deletion pages)
# Optional: PAGES_PROJECT (default goldentongue-members)
set -euo pipefail
: "${SUPABASE_URL:?}" "${SUPABASE_ANON_KEY:?}"
PROJECT="${PAGES_PROJECT:-goldentongue-members}"
cd "$(dirname "$0")/.."

npm install --silent
npm test
npx wrangler pages project create "$PROJECT" --production-branch main >/dev/null 2>&1 || true

put() { printf '%s' "$2" | npx wrangler pages secret put "$1" --project-name "$PROJECT" >/dev/null; echo "secret $1 set"; }
put SUPABASE_URL "$SUPABASE_URL"
put SUPABASE_ANON_KEY "$SUPABASE_ANON_KEY"
[ -n "${OPENAI_API_KEY:-}" ] && put OPENAI_API_KEY "$OPENAI_API_KEY"
[ -n "${TURNSTILE_SITE_KEY:-}" ] && put TURNSTILE_SITE_KEY "$TURNSTILE_SITE_KEY"
[ -n "${PRIVACY_URL:-}" ] && put PRIVACY_URL "$PRIVACY_URL"
[ -n "${TERMS_URL:-}" ] && put TERMS_URL "$TERMS_URL"
[ -n "${SUPPORT_EMAIL:-}" ] && put SUPPORT_EMAIL "$SUPPORT_EMAIL"

# Deploy from the project root so the functions/ folder is bundled.
npx wrangler pages deploy public --project-name "$PROJECT" --branch main
echo "Done. Open the pages.dev address above and sign up."
