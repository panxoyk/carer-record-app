# Carer Record

Aplicación móvil para el registro clínico, en una primera etapa enfocada en acceso y administración de usuarios.

## Desarrollo local

Requiere Node 22+, pnpm 10.17+, Deno 2.9.6, Docker Desktop, FVM y la versión indicada en `app/.fvmrc`.

```sh
pnpm install --frozen-lockfile
cd app && fvm install && cd ..
cp .env.example .env
pnpm db:start
pnpm db:reset
pnpm app:run
```

Tras `pnpm db:start`, copia la clave `anon`/publishable mostrada por Supabase a `SUPABASE_PUBLISHABLE_KEY` en `.env`. Nunca añadas una Service Role Key a `.env` de la app ni a Flutter. `.env` está ignorado por Git; `pnpm db:reset` reconstruye la base exclusivamente desde migraciones y `supabase/seed.sql`. La cuenta administrativa local es `admin@example.test` / `ChangeMe123!`.

El entorno local admite exclusivamente datos sintéticos. `pnpm db:stop` detiene Supabase y conserva su volumen, `pnpm db:reset` reconstruye la base y vuelve a cargar el seed, y `pnpm db:purge` detiene Supabase y elimina definitivamente sus volúmenes. Este último comando es destructivo y nunca forma parte de los checks. Supabase local puede escuchar en todas las interfaces de red: no lo expongas por túneles ni lo ejecutes conectado a una red compartida no confiable.

Si se introducen datos reales accidentalmente, detén el entorno con `pnpm db:purge`, elimina exportaciones y logs locales que los contengan y revisa
si alguna credencial no local debe rotarse antes de continuar.

### Datos de demostración

`pnpm db:reset` carga 8 pacientes sintéticos y 18 eventos que cubren todas las categorías del timeline, varias unidades, campos demográficos ausentes, textos largos y un paciente sin eventos. Las cuentas locales comparten la contraseña `ChangeMe123!`:

| Email                       | Rol           | Estado     |
| --------------------------- | ------------- | ---------- |
| `ana.torres@example.test`   | Médico        | Activa     |
| `matias.rojas@example.test` | Enfermero     | Activa     |
| `tecnico@example.test`      | Técnico       | Activa     |
| `admin@example.test`        | Administrador | Activa     |
| `camila.vera@example.test`  | Médico        | Suspendida |

Usa `pnpm format` para formatear Dart, TypeScript, Markdown y JSON, y `pnpm check` para comprobar formato, lint, tipos y el pipeline. `pnpm install --frozen-lockfile` instala mediante Lefthook un hook de pre-commit que ejecuta `pnpm check`; CI repite el mismo comando, por lo que no depende de que el hook local se ejecute. Para cambios de base de datos usa además `pnpm db:reset`, `pnpm db:lint` y `pnpm db:test`. Las pruebas de base de datos cubren los permisos RLS permitidos y denegados.

Para las Edge Functions, usa `pnpm functions:test` con Supabase local iniciado. Cuando cambien migraciones, regenera sus tipos TypeScript con `pnpm functions:types:generate` e incluye `supabase/functions/database.types.ts` en el cambio.

Los practitioners activos `physician`, `nurse` y `technician` pueden consultar el listado, ficha y timeline de pacientes en modo solo lectura. La matriz completa está en [`docs/roadmap.md`](docs/roadmap.md).

Trabaja directamente sobre `main` con commits pequeños e independientes, y actualiza el roadmap, los pendientes y las pruebas que correspondan en el mismo
commit. Consulta [la arquitectura](docs/architecture.md), [el roadmap](docs/roadmap.md), [los pendientes](docs/todo.md) y [la estrategia de pruebas](docs/testing-strategy.md).
