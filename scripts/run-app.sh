#!/usr/bin/env sh
set -eu

if [ ! -f .env ]; then
  echo 'Missing .env. Copy .env.example to .env and set SUPABASE_PUBLISHABLE_KEY.' >&2
  exit 1
fi

set -a
. ./.env
set +a

: "${SUPABASE_URL:?SUPABASE_URL is required in .env}"
: "${SUPABASE_PUBLISHABLE_KEY:?SUPABASE_PUBLISHABLE_KEY is required in .env}"

if [ "${1:-}" = "--" ]; then
  shift
fi

cd app
exec fvm flutter run \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  "$@"
