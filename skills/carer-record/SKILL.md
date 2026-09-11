# Carer Record

Antes de modificar Carer Record, preserva Supabase como infraestructura versionada: nunca edites migraciones aplicadas y usa migraciones aditivas. Todo JSONB requiere modelo tipado y una restricción que limite su forma a objeto. Nunca envíes Service Role Keys al cliente.

Para cambios de producto, actualiza `docs/roadmap.md`, enlaza o crea el GitHub Issue adecuado y valida `pnpm app:analyze`, `pnpm app:test`, `pnpm pipeline:check` y los checks de Supabase que correspondan.
