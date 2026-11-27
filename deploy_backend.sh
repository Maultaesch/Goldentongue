#!/usr/bin/env bash
# Deploys the Supabase backend: database migrations, all edge functions, optional seed data.
# Prerequisites: Supabase CLI logged in (`supabase login`), and
#   SUPABASE_PROJECT_REF   the id from your project URL (https://<ref>.supabase.co)
# Optional: DATABASE_URL (postgres connection string) to also load the seed files.
# Secrets are set separately (see README, "Secrets"): supabase secrets set NAME=value
set -euo pipefail
: "${SUPABASE_PROJECT_REF:?}"
cd "$(dirname "$0")/.."

supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase db push

# Functions called by signed-in users (JWT is verified by Supabase).
supabase functions deploy coach voice-analyze simulator blueprint exercise-evaluate create-checkout delete-account
# Webhooks are called by Stripe and RevenueCat, so they carry their own signature or secret instead of a JWT.
supabase functions deploy stripe-webhook revenuecat-webhook --no-verify-jwt

if [ -n "${DATABASE_URL:-}" ]; then
  for f in seed seed_line_library seed_curated seed_exercises seed_sections; do
    psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f "supabase/$f.sql"
  done
else
  echo "Seed data not loaded. Run supabase/seed.sql, seed_line_library.sql, seed_curated.sql, seed_exercises.sql and seed_sections.sql in the SQL editor (or set DATABASE_URL)."
fi
echo "Backend deployed. Next: set the secrets, then make yourself admin: select public.grant_admin('you@example.com');"
