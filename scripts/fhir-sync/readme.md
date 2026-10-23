# FHIR structural sync (local development)

Run `pnpm fhir:sync` after the local Supabase database and HAPI demo are running. The command reads paginated Patient, Encounter and Location resources, writes ignored local SQL, and applies it through `psql` in the exact `supabase_db_carer-record` container. Override that container with `FHIR_SYNC_DB_CONTAINER` when using a deliberately named local project.

The source logical key is `demo-hapi`; UUID namespace input is `demo-hospital\0demo-hapi`, followed by resource type and FHIR `Resource.id`. UUID bytes are the first 128 bits of SHA-256 with RFC 4122 version/variant bits set. `fhir_sources` and the typed link tables are the authority for FHIR identity; `patients.external_reference` is left NULL because it is globally unique and cannot safely represent a multi-source key.

Demo care assignments are an independent, explicit operation: `pnpm fhir:demo:assignments`. It uses `demo-assignments.json`, creates only missing rows, and does not revive an existing revoked/expired decision. It must be run after structural sync.

Focused unit tests: `pnpm fhir:sync:test`. The opt-in PostgreSQL rollback integration test is run with `FHIR_SYNC_PG_INTEGRATION=1 pnpm fhir:sync:test`; it requires an already-running, migrated local DB container and does not reset it.

This script is a local demo projection, not the production ingestion worker or clinical-record gateway. Never point it at real clinical data.
