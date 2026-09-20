# Carer Record

Aplicación móvil para el registro clínico. El alcance actual incluye acceso, recuperación de contraseña, administración de usuarios y consulta clínica de solo lectura.

## Inicio rápido

### Requisitos

- Node 22 o superior y pnpm 10.17 o superior.
- Deno 2.9.6 y Docker Desktop.
- FVM y la versión de Flutter declarada en `app/.fvmrc`.
- Para iOS: macOS, Xcode con un runtime de iOS Simulator y CocoaPods.

### 1. Instala dependencias

Desde la raíz:

```bash
pnpm install --frozen-lockfile
cd app
fvm install
cd ..
```

La instalación registra un hook de pre-commit que ejecuta `pnpm check`.

### 2. Inicia Supabase y configura la app

```bash
cp .env.example .env
pnpm db:start
```

El comando muestra `Project URL` y una clave `anon` o `publishable`. Copia esos valores en `.env`:

```env
SUPABASE_URL=http://127.0.0.1:54321
SUPABASE_PUBLISHABLE_KEY=<clave-mostrada-por-supabase>
```

Después carga las migraciones y datos sintéticos:

```bash
pnpm db:reset
```

`.env` es local e ignorado por Git. Nunca agregues una Service Role Key ni datos clínicos reales.

### 3. Ejecuta la app

Consulta la sección de tu plataforma y ejecuta `pnpm app:run`. El comando pasa la URL y clave publishable de `.env` a Flutter mediante `--dart-define`.

## Ejecutar en simulador o emulador

### iOS Simulator

Abre el simulador desde Xcode (`Xcode > Open Developer Tool > Simulator`) o:

```bash
xcrun simctl list devices available
open -a Simulator
```

Selecciona un dispositivo iniciado y usa su UDID para lanzar la app:

```bash
pnpm app:run -- -d <SIMULATOR_UDID>
```

Para iOS Simulator, conserva `SUPABASE_URL=http://127.0.0.1:54321`: el simulador puede acceder al servidor local del Mac mediante loopback.

### Emulador Android

Inicia un emulador desde Android Studio y ejecuta:

```bash
pnpm app:run
```

Android reserva `10.0.2.2` como alias de la máquina anfitriona. Por eso, para conectar el emulador Android al Supabase local que corre en tu computador, usa:

```env
SUPABASE_URL=http://10.0.2.2:54321
```

`127.0.0.1` dentro de Android apunta al emulador, no a tu Mac. En iOS Simulator ocurre lo contrario para este flujo: usa `127.0.0.1`. Cambia solo el host; el puerto y la clave siguen siendo los mostrados por `pnpm db:start`.

### Proyecto nativo iOS

`app/ios/` es parte del proyecto y se versiona para reproducir la compilación en otro Mac: `Podfile`, `Podfile.lock`, el proyecto Xcode y el workspace. Si CocoaPods queda fuera de sincronía, regenera sus artefactos con:

```bash
cd app/ios
pod install
cd ../..
```

`app/ios/Pods/` se regenera y no se versiona. Los dispositivos físicos no usan estas direcciones locales y no forman parte del entorno de desarrollo actual.

## Datos de demostración

`pnpm db:reset` carga pacientes y eventos sintéticos. Todas las cuentas locales usan la contraseña `ChangeMe123!`.

| Email                       | Rol           | Estado     |
| --------------------------- | ------------- | ---------- |
| `ana.torres@example.test`   | Médico        | Activa     |
| `matias.rojas@example.test` | Enfermero     | Activa     |
| `tecnico@example.test`      | Técnico       | Activa     |
| `admin@example.test`        | Administrador | Activa     |
| `camila.vera@example.test`  | Médico        | Suspendida |

## Operaciones diarias

| Necesidad                                  | Comando                         |
| ------------------------------------------ | ------------------------------- |
| Detener Supabase y conservar datos         | `pnpm db:stop`                  |
| Reconstruir migraciones y datos sintéticos | `pnpm db:reset`                 |
| Eliminar Supabase y sus volúmenes          | `pnpm db:purge`                 |
| Formatear todos los lenguajes              | `pnpm format`                   |
| Ejecutar los checks locales                | `pnpm check`                    |
| Validar cambios de Edge Functions          | `pnpm functions:check`          |
| Regenerar tipos tras una migración         | `pnpm functions:types:generate` |

`pnpm db:purge` es destructivo. Úsalo si se introducen datos reales por error, elimina cualquier exportación o log afectado y revisa las credenciales antes de continuar. No expongas Supabase local mediante túneles ni redes compartidas no confiables.

## Verificación por cambio

- Flutter: `pnpm app:format:check`, `pnpm app:analyze` y las pruebas Dart relacionadas.
- Documentación y JSON: `pnpm docs:format:check`, `pnpm docs:lint` y `git diff --check`.
- Edge Functions: `pnpm functions:check`.
- Migraciones, RLS o funciones SQL: `pnpm db:reset`, `pnpm db:lint` y `pnpm db:test`.

CI ejecuta `pnpm check` y las pruebas de Flutter. La estrategia completa está en [docs/testing-strategy.md](docs/testing-strategy.md).

## Reglas del repositorio

- Trabaja directamente sobre `main` con commits pequeños e independientes.
- Mantén la separación Flutter `data/domain/presentation`; el acceso remoto va detrás de repositorios.
- RLS es la autoridad de autorización. La UI no agrega permisos clínicos.
- No edites migraciones aplicadas: crea una migración aditiva.
- No versiones secretos, credenciales, firmas ni datos clínicos reales.
- Actualiza roadmap, pendientes, pruebas y documentación cuando cambie el alcance o un contrato.

Los roles clínicos activos (`physician`, `nurse` y `technician`) pueden leer pacientes y eventos. Los administradores gestionan usuarios, pero no obtienen acceso clínico implícito. La matriz completa está en [docs/roadmap.md](docs/roadmap.md).

## Referencias

- [Guía de desarrollo](docs/development-guide.md)
- [Arquitectura](docs/architecture.md)
- [Roadmap y permisos](docs/roadmap.md)
- [Pendientes](docs/todo.md)
- [Estrategia de pruebas](docs/testing-strategy.md)
