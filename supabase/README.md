# Supabase local

Supabase local proporciona Auth, PostgreSQL, PostgREST y Edge Functions. La [fundación](../docs/foundation/README.md) define la dirección; el comportamiento implementado se verifica en migraciones, funciones y pruebas.

## Estructura

- `config.toml`: configuración de servicios locales y funciones.
- `migrations/`: cambios de esquema, permisos, políticas y contratos SQL versionados.
- `seed.sql`: cuentas y vínculos sintéticos locales; se aplica después de migraciones.
- `functions/`: Edge Functions, contratos generados y pruebas Deno.
- `tests/`: pruebas pgTAP de políticas e invariantes SQL.
- `fixtures/`: datos de compatibilidad para pruebas existentes, no fuente del demo actual.

RLS es la autoridad de autorización. Un guard de UI no la reemplaza. No edites migraciones ya aplicadas: agrega una migración nueva. No guardes claves Service Role, secretos ni datos clínicos reales; la Service Role solo puede existir en servidor.

## Operación local

Desde la raíz del repositorio, instala dependencias y copia `.env.example` a `.env`. Ejecuta `pnpm exec supabase start` para obtener la URL local y la clave anon/publishable, y completa `.env` con esa clave publishable. El flujo normal mantiene `pnpm env:up` en una terminal para Supabase/HAPI y la pasarela autorizada; `pnpm app:run` en otra terminal inicia solo Flutter. `pnpm env:stop` detiene los servicios locales conservando los volúmenes.

Para una base nueva o desechable, `pnpm db:reset` aplica migraciones y seed y destruye el estado local previo. No lo ejecutes como paso ordinario. `pnpm db:stop` detiene Supabase conservando el volumen. La cuenta de demo y contraseña están definidas en `seed.sql`; solo sirven para desarrollo local.

## Validación

- Migraciones/RLS: `pnpm db:lint` y `pnpm db:test` (servicios locales requeridos).
- Edge Functions: `pnpm functions:format:check`, `pnpm functions:lint`, `pnpm functions:typecheck` y `pnpm functions:test`.
- La validación completa por capa y el uso de selectores están en [scripts](../scripts/README.md) y la estrategia canónica [testing y validación](../docs/foundation/11-testing-validation.md).

No inicies servicios ni ejecutes resets como parte de una validación documental.
