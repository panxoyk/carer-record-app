# Carer Record

Aplicación móvil para el registro clínico, en una primera etapa enfocada en acceso y administración de usuarios.

## Desarrollo local

Requiere Node 22+, pnpm 10.17+, Docker Desktop, FVM y la versión indicada en `app/.fvmrc`.

```sh
pnpm install
cd app && fvm install && cd ..
cp .env.example .env
pnpm db:start
pnpm db:reset
pnpm app:run
```

Tras `pnpm db:start`, copia la clave `anon`/publishable mostrada por Supabase a `SUPABASE_PUBLISHABLE_KEY` en `.env`. Nunca añadas una Service Role Key a `.env` de la app ni a Flutter. `.env` está ignorado por Git; `pnpm db:reset` reconstruye la base exclusivamente desde migraciones y `supabase/seed.sql`. La cuenta administrativa local es `admin@example.test` / `ChangeMe123!`.

Comandos de verificación: `pnpm app:format`, `pnpm app:format:check`, `pnpm app:analyze`, `pnpm pipeline:check`, `pnpm db:reset`, `pnpm db:lint` y `pnpm db:test`. Las pruebas de base de datos cubren los permisos RLS permitidos y denegados.

Los practitioners activos `physician`, `nurse` y `technician` pueden consultar
el listado y ficha de pacientes en modo solo lectura. La matriz completa está en
[`docs/roadmap.md`](docs/roadmap.md); los eventos clínicos aún no están habilitados.

Trabaja en ramas cortas desde `main`, abre un PR y actualiza el roadmap e Issue correspondiente. No se despliega automáticamente. Consulta [la arquitectura](docs/architecture.md) y [el roadmap](docs/roadmap.md).
