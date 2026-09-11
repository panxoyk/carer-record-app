# Carer Record

Aplicación móvil para el registro clínico, en una primera etapa enfocada en acceso y administración de usuarios.

## Desarrollo local

Requiere Node 22+, pnpm 10.17+, Docker Desktop, FVM y la versión indicada en `app/.fvmrc`.

```sh
pnpm install
cd app && fvm install && cd ..
pnpm db:start
pnpm db:reset
pnpm app:run -- --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<local-anon-key>
```

La clave publicable local aparece al ejecutar `pnpm db:start`; nunca se debe añadir una Service Role Key a Flutter. `pnpm db:reset` reconstruye la base exclusivamente desde migraciones y `supabase/seed.sql`. La cuenta administrativa local es `admin@example.test` / `ChangeMe123!`.

Comandos de verificación: `pnpm app:analyze`, `pnpm app:test`, `pnpm pipeline:check` y `pnpm db:reset`.

Trabaja en ramas cortas desde `main`, abre un PR y actualiza el roadmap e Issue correspondiente. No se despliega automáticamente. Consulta [la arquitectura](docs/architecture.md) y [el roadmap](docs/roadmap.md).
