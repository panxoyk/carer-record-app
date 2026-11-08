# Carer Record

Prototipo Flutter de contexto clínico e integración para hospitalización. Usa solo datos sintéticos; nunca ingreses datos clínicos reales. La [fundación](docs/foundation/README.md) define alcance y dirección.

## Requisitos

- Node.js 22.9+, pnpm 12.18.0 y Deno 2.9.6.
- Docker Desktop iniciado.
- FVM y Flutter 3.47.7 (`app/.fvmrc`).
- Android Studio/emulador o, en macOS, Xcode, iOS Simulator y CocoaPods.

## Primera instalación

Ejecuta desde la raíz:

```sh
pnpm install --frozen-lockfile
cd app && fvm install && cd ..
cp .env.example .env
pnpm exec supabase start
```

En la salida de Supabase, copia la clave anon/publishable a `SUPABASE_PUBLISHABLE_KEY`; nunca uses la Service Role Key. `SUPABASE_LOCAL_URL` usa `http://127.0.0.1:54321`.

| Dispositivo      | `SUPABASE_URL`           |
| ---------------- | ------------------------ |
| Android Emulator | `http://10.0.2.2:54321`  |
| iOS Simulator    | `http://127.0.0.1:54321` |

Solo en la primera instalación o para descartar la base local: `pnpm db:reset` (borra y recrea sus datos).

## Ejecutar (Docker Desktop y emulador/simulador abiertos)

```sh
pnpm app:run
```

## Demo

- Administrador: `admin@example.test` / `ChangeMe123!`.
- Otras cuentas sintéticas: [Supabase, seed y cuentas](supabase/README.md).

## Dónde encontrar cada cosa

| Ruta                                                | Contenido                                             |
| --------------------------------------------------- | ----------------------------------------------------- |
| [`app/`](app/README.md)                             | Flutter, plataformas y modelos locales                |
| [`supabase/`](supabase/README.md)                   | Configuración, migraciones, seed y RLS                |
| [`scripts/`](scripts/README.md)                     | Utilidades, comandos y pruebas por capa               |
| [`scripts/fhir-sync/`](scripts/fhir-sync/README.md) | Sincronización estructural FHIR                       |
| [`docker/hapi-fhir/`](docker/hapi-fhir/README.md)   | HAPI FHIR de demostración                             |
| [`docs/`](docs/README.md)                           | Índice de guías y documentación                       |
| [`docs/foundation/`](docs/foundation/README.md)     | Fuente canónica de alcance, arquitectura y decisiones |
