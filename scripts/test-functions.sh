#!/usr/bin/env sh
set -eu

if [ ! -f .env ]; then
  echo 'Missing .env. Run pnpm db:start and create it from .env.example.' >&2
  exit 1
fi

set -a
. ./.env
set +a

supabase_url="${SUPABASE_URL:-${API_URL:-}}"
publishable_key="${SUPABASE_PUBLISHABLE_KEY:-${PUBLISHABLE_KEY:-}}"

: "${supabase_url:?SUPABASE_URL or API_URL is required in .env}"
: "${publishable_key:?SUPABASE_PUBLISHABLE_KEY or PUBLISHABLE_KEY is required in .env}"

SUPABASE_URL="${SUPABASE_FUNCTIONS_TEST_URL:-http://127.0.0.1:54321}"
SUPABASE_PUBLISHABLE_KEY="$publishable_key"
export SUPABASE_URL
export SUPABASE_PUBLISHABLE_KEY

exec deno test \
  --config supabase/functions/deno.json \
  --lock=supabase/functions/deno.lock \
  --frozen \
  --allow-env \
  --allow-net \
  supabase/functions/create-practitioner/index.test.ts
