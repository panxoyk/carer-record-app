# Carer Record

Aplicación móvil para el registro clínico. La primera etapa cubre acceso y administración de usuarios, además de consulta clínica de solo lectura.

## Desarrollo local

### 1. Instala los requisitos

- Node 22 o superior
- pnpm 10.17 o superior
- Deno 2.9.6
- Docker Desktop
- FVM
- La versión de Flutter indicada en `app/.fvmrc`

### 2. Instala dependencias y Flutter

Desde la raíz del repositorio ejecuta:

```bash
pnpm install --frozen-lockfile
cd app
fvm install
cd ..
```

La instalación configura un hook de pre-commit con Lefthook que ejecuta `pnpm check`.

### 3. Crea la configuración local

```bash
cp .env.example .env
```

No agregues una Service Role Key en `.env` ni en Flutter. La Service Role Key solo se utiliza en el servidor. El archivo `.env` está ignorado por Git.

### 4. Inicia Supabase local

```bash
pnpm db:start
```

Supabase mostrará una clave `anon` o publishable. Cópiala en `SUPABASE_PUBLISHABLE_KEY` dentro de `.env`.

### 5. Reconstruye los datos locales

```bash
pnpm db:reset
```

Este comando reconstruye la base desde las migraciones y `supabase/seed.sql`.

### 6. Ejecuta la aplicación

```bash
pnpm app:run
```

## Datos de demostración

El reinicio de la base carga 8 pacientes sintéticos y 18 eventos. Incluye todas las categorías del timeline, varias unidades, campos demográficos ausentes, textos largos y un paciente sin eventos.

Todas las cuentas locales usan esta contraseña:

```text
ChangeMe123!
```

| Email                       | Rol           | Estado     |
| --------------------------- | ------------- | ---------- |
| `ana.torres@example.test`   | Médico        | Activa     |
| `matias.rojas@example.test` | Enfermero     | Activa     |
| `tecnico@example.test`      | Técnico       | Activa     |
| `admin@example.test`        | Administrador | Activa     |
| `camila.vera@example.test`  | Médico        | Suspendida |

## Administración de Supabase local

Detén Supabase y conserva los datos locales:

```bash
pnpm db:stop
```

Reconstruye la base y vuelve a cargar los datos de demostración:

```bash
pnpm db:reset
```

Elimina Supabase y todos sus volúmenes locales de forma permanente:

```bash
pnpm db:purge
```

`pnpm db:purge` es destructivo y no forma parte de los checks. El entorno local admite exclusivamente datos sintéticos. No expongas Supabase local mediante túneles ni lo ejecutes conectado a una red compartida no confiable.

Si se introducen datos reales por error, detén y elimina el entorno local:

```bash
pnpm db:purge
```

Después elimina cualquier exportación o log local que contenga esos datos y revisa si alguna credencial no local debe rotarse antes de continuar.

## Verificaciones

Formatea Dart, TypeScript, Markdown y JSON:

```bash
pnpm format
```

Comprueba formato, lint, tipos y el pipeline:

```bash
pnpm check
```

CI ejecuta también `pnpm check`, por lo que la validación no depende del hook local.

Para cambios de base de datos, ejecuta estas verificaciones adicionales. Las pruebas cubren permisos RLS permitidos y denegados:

```bash
pnpm db:reset
pnpm db:lint
pnpm db:test
```

Para cambios en Edge Functions, con Supabase local iniciado:

```bash
pnpm functions:test
```

Si cambian las migraciones, regenera los tipos TypeScript e incluye `supabase/functions/database.types.ts` en el cambio:

```bash
pnpm functions:types:generate
```

## Permisos clínicos

Los practitioners activos con rol `physician`, `nurse` o `technician` pueden consultar el listado, la ficha y el timeline de pacientes en modo solo lectura. La matriz completa está en [`docs/roadmap.md`](docs/roadmap.md).

## Contribución

Trabaja directamente sobre `main` con commits pequeños e independientes. Actualiza el roadmap, los pendientes y las pruebas correspondientes en el mismo cambio.

Consulta estos documentos antes de implementar cambios relevantes:

- [Arquitectura](docs/architecture.md)
- [Roadmap](docs/roadmap.md)
- [Pendientes](docs/todo.md)
- [Estrategia de pruebas](docs/testing-strategy.md)
