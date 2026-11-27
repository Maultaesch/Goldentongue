#!/usr/bin/env bash
# Gives an existing account full access without paying and without limits.
# The person must have signed up first. Usage: DATABASE_URL=postgres://... scripts/make_admin.sh you@example.com
set -euo pipefail
: "${DATABASE_URL:?set DATABASE_URL (Supabase -> Project Settings -> Database -> Connection string)}"
email="${1:?usage: scripts/make_admin.sh you@example.com}"
case "$email" in *@*.*) ;; *) echo "That does not look like an email address."; exit 1;; esac
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -v email="$email" <<'SQL'
select public.grant_admin(:'email');
select 'admin ok' as result, public.is_admin(id) as is_admin from auth.users where lower(email) = lower(:'email');
SQL
