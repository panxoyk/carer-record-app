#!/usr/bin/env sh
set -eu

if [ ! -f .env ]; then
  echo 'Missing .env. Copy .env.example to .env and set SUPABASE_PUBLISHABLE_KEY.' >&2
  exit 1
fi

set -a
. ./.env
set +a

: "${SUPABASE_PUBLISHABLE_KEY:?SUPABASE_PUBLISHABLE_KEY is required in .env}"
: "${SUPABASE_LOCAL_URL:=http://127.0.0.1:54321}"
: "${HAPI_FHIR_PORT:=8080}"
export HAPI_FHIR_PORT
SUPABASE_URL="${SUPABASE_URL:-$SUPABASE_LOCAL_URL}"

# app:run owns the local demo startup; these commands are safe to repeat.
pnpm db:start
compose() { docker compose -f docker/hapi-fhir/docker-compose.yml "$@"; }
compose up -d hapi-fhir
compose run --rm --no-deps hapi-seed

FHIR_HOST_URL="http://127.0.0.1:${HAPI_FHIR_PORT}/fhir"
node scripts/fhir-sync/generate-sync.mjs --apply "$FHIR_HOST_URL"
node scripts/fhir-sync/generate-sync.mjs --demo-assignments

gateway_url="${SUPABASE_LOCAL_URL%/}/functions/v1/clinical-record"
network=supabase_network_carer-record
hapi=carer-record-hapi-fhir
if ! docker network inspect "$network" >/dev/null 2>&1; then
  echo "Missing Docker network $network after Supabase startup." >&2
  exit 1
fi
if ! docker network inspect "$network" --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -Fxq "$hapi"; then
  docker network connect --alias hapi-fhir "$network" "$hapi"
fi
probe_gateway() {
  node -e '
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 3000);
    fetch(process.argv[1], { headers: { apikey: process.argv[2] }, signal: controller.signal })
      .then(async response => {
        let body;
        try { body = await response.json(); } catch { process.exitCode = 1; return; }
        if (response.status !== 405 || body?.error !== "method_not_allowed") process.exitCode = 1;
      })
      .catch(() => { process.exitCode = 1; })
      .finally(() => clearTimeout(timer));
  ' "$gateway_url" "$SUPABASE_PUBLISHABLE_KEY"
}
gateway_pid=
if ! probe_gateway; then
  ./scripts/serve-fhir-gateway.sh &
  gateway_pid=$!
fi
cleanup() {
  if [ -n "$gateway_pid" ]; then
    kill "$gateway_pid" 2>/dev/null || true
    wait "$gateway_pid" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

attempt=0
while :; do
  if [ -n "$gateway_pid" ] && ! kill -0 "$gateway_pid" 2>/dev/null; then
    echo "No se pudo iniciar la pasarela clinical-record." >&2
    exit 1
  fi
  if probe_gateway; then break; fi
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 60 ]; then
    echo "La función clinical-record no quedó disponible en el endpoint esperado." >&2
    exit 1
  fi
  sleep 2
done

if [ "${1:-}" = "--" ]; then
  shift
fi

cd app
fvm flutter run \
  --dart-define="SUPABASE_URL=$SUPABASE_URL" \
  --dart-define="SUPABASE_PUBLISHABLE_KEY=$SUPABASE_PUBLISHABLE_KEY" \
  "$@"
