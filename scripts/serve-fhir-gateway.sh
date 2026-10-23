#!/usr/bin/env bash
set -euo pipefail

network="supabase_network_carer-record"
hapi="carer-record-hapi-fhir"
env_file="docker/hapi-fhir/gateway.env.local"

if ! docker network inspect "$network" >/dev/null 2>&1; then
  echo "Missing Docker network $network; start Supabase with pnpm db:start first." >&2
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -Fxq "$hapi"; then
  echo "Missing running HAPI container $hapi; start it with pnpm fhir:up first." >&2
  exit 1
fi
if ! docker network inspect "$network" --format '{{range .Containers}}{{.Name}}{{"\n"}}{{end}}' | grep -Fxq "$hapi"; then
  docker network connect --alias hapi-fhir "$network" "$hapi"
fi
if [[ ! -f "$env_file" ]]; then env_file="docker/hapi-fhir/gateway.env.example"; fi
echo "Serving clinical-record; HAPI alias hapi-fhir is attached to the stable Supabase network."
exec pnpm exec supabase functions serve clinical-record --env-file "$env_file"
