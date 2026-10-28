# Carer Record

Prototipo móvil de contexto clínico e integración para hospitalización. La visión, el alcance académico y los límites están definidos en [foundation](docs/foundation/README.md).

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

### 2. Configura la app

```bash
cp .env.example .env
```

Configura `.env` con la URL móvil apropiada (`10.0.2.2` para Android Emulator, `127.0.0.1` para iOS Simulator) y la clave publishable local. `SUPABASE_LOCAL_URL` es la URL loopback del host para scripts y por defecto es `http://127.0.0.1:54321`.

```env
SUPABASE_URL=http://10.0.2.2:54321
SUPABASE_LOCAL_URL=http://127.0.0.1:54321
SUPABASE_PUBLISHABLE_KEY=<clave-mostrada-por-supabase>
```

`.env` es local e ignorado por Git. Nunca agregues una Service Role Key ni datos clínicos reales.

### 3. Inicia el servidor FHIR de demostración

La app consulta censo y ficha mediante la pasarela autorizada `clinical-record`; no lee HAPI directamente. `pnpm app:run` inicia/reutiliza Supabase y HAPI, espera su seed, sincroniza vínculos y asignaciones, levanta/espera la pasarela y luego inicia Flutter. No borra datos ni ejecuta reset. El repositorio incluye 20 pacientes sintéticos FHIR (ver [docker/hapi-fhir](docker/hapi-fhir/README.md)):

```bash
pnpm app:run
```

La primera vez descarga imágenes y puede tardar varios minutos. `pnpm app:run` inicia HAPI y ejecuta su seed en primer plano con PUTs idempotentes antes de sincronizar; conserva recursos no incluidos en el bundle. `pnpm fhir:up` se puede ejecutar por separado para operar HAPI y seed.

```bash
pnpm fhir:sync
```

`pnpm fhir:sync` sincroniza estructura mínima; `pnpm app:run` además aplica las asignaciones declaradas. No es ingesta clínica completa. Si el puerto 8080 está ocupado, usa `HAPI_FHIR_PORT=8081 pnpm app:run`.

### 4. Ejecuta la app

Consulta la sección de tu plataforma y ejecuta `pnpm app:run`. El comando conserva los argumentos Flutter y pasa solo URL móvil de Supabase y clave publishable mediante `--dart-define`. HAPI no se expone al móvil; la Edge Function obtiene acceso por red Docker.

## Modelos en el dispositivo

El dictado de hitos y la mejora de redacción se ejecutan dentro del teléfono, así que la app necesita dos pesos que **no están en el repositorio**:unos 198 MB de `sherpa-onnx-whisper-base` (int8, Apache/MIT) y unos 1,03 GB de `Qwen3-1.7B-Q4_K_M.gguf` (Apache-2.0). Versionarlos ocuparía más que el código y bloquearía los clones.

Lo que sí está versionado son los manifiestos, `app/assets/asr_model_manifest.json` y `app/assets/llm_model_manifest.json`. Cada uno fija origen, licencia, versión, tamaño y el `sha256` de cada archivo.

Qué hace la app con ellos:

- En el **primer arranque** se abre la pantalla «Preparar el dispositivo» y descarga los dos modelos con progreso visible.
- Cada descarga se verifica por `sha256` antes de usarse; si no coincide, el instalador borra lo descargado y reintenta.
- Los pesos quedan en el directorio privado de soporte de la app (`files/asr` y `files/llm` en Android), fuera del APK y fuera de las copias de seguridad.
- En los arranques siguientes solo se comprueba el tamaño de los archivos: hashear 1,3 GB en cada inicio costaría más que la propia descarga.
- La pantalla se puede saltar. Sin modelos, la bitácora sigue funcionando: solo desaparecen el hito dictado y la ayuda a redactar (ADR-016 y ADR-017).

Necesitas ~1,3 GB libres en el dispositivo y conexión para descargar modelos y publicar hitos. La inferencia local (dictado y asistencia) funciona sin red; la publicación confirmada requiere conexión.

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

Para iOS Simulator configura `SUPABASE_URL=http://127.0.0.1:54321`; `SUPABASE_LOCAL_URL` permanece loopback del host:

```env
SUPABASE_URL=http://127.0.0.1:54321
```

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

`FHIR_BASE_URL` se configura en Flutter (por `--dart-define` o `.env`) y apunta al servidor HAPI de demostración (`http://10.0.2.2:8080/fhir` en Android Emulator). La pasarela autorizada `clinical-record` consulta HAPI desde el servidor.

### Dispositivo Android físico (opcional)

Los dispositivos físicos no forman parte del entorno de desarrollo soportado, pero puedes probar con uno por USB o por depuración inalámbrica redirigiendo los puertos del computador con `adb reverse`, de modo que el teléfono use `127.0.0.1`:

```bash
adb reverse tcp:54321 tcp:54321
fvm flutter run -d <ID_DEL_DISPOSITIVO> --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<clave>
```

Ejecuta `fvm flutter run` desde `app/`. Hay que repetir `adb reverse` cada vez que se reconecta el dispositivo. La app usa HTTP sin TLS contra estas direcciones locales solo en desarrollo; si Android lo bloquea, habilita `android:usesCleartextTraffic="true"` únicamente en `app/android/app/src/debug/AndroidManifest.xml`.

### Proyecto nativo iOS

`app/ios/` es parte del proyecto y se versiona para reproducir la compilación en otro Mac: `Podfile`, `Podfile.lock`, el proyecto Xcode y el workspace. Si CocoaPods queda fuera de sincronía, regenera sus artefactos con:

```bash
cd app/ios
pod install
cd ../..
```

`app/ios/Pods/` se regenera y no se versiona. En iOS no hay un flujo documentado para dispositivos físicos.

## Setup en Windows (manual)

`pnpm app:run` es un script bash (Linux/macOS). En Windows nativo, ejecuta los pasos equivalentes manualmente:

```powershell
# 1. Dependencias y configuración
pnpm install
cp .env.example .env
# Edita .env con SUPABASE_URL, SUPABASE_PUBLISHABLE_KEY y FHIR_BASE_URL

# 2. Base de datos
pnpm db:start
pnpm db:reset

# 3. Servidor FHIR de demostración
pnpm fhir:up
pnpm fhir:sync
pnpm fhir:demo:assignments

# 4. Gateway (en una terminal aparte, con Git Bash)
bash scripts/serve-fhir-gateway.sh

# 5. App (en otra terminal)
cd app
flutter run -d <device> --dart-define=SUPABASE_URL=http://10.0.2.2:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<clave> --dart-define=FHIR_BASE_URL=http://10.0.2.2:8080/fhir
```

Notas:

- `10.0.2.2` es el alias del host desde el emulador Android; en iOS Simulator usa `127.0.0.1`.
- Si el puerto 8080 está ocupado, usa `HAPI_FHIR_PORT=8081` y ajusta `FHIR_BASE_URL`.
- El teclado del emulador se habilita en `E:\.android\avd\<avd>\config.ini` con `hw.keyboard = yes`.
- Los modelos (LLM + ASR) se descargan en el primer arranque; se pueden pre-instalar con `adb push` a `files/llm` y `files/asr`.

## Datos de demostración

`pnpm db:reset` carga pacientes y eventos sintéticos. Todas las cuentas locales usan la contraseña `ChangeMe123!`.

| Email                       | Rol           | Estado     |
| --------------------------- | ------------- | ---------- |
| `ana.torres@example.test`   | Médico        | Activa     |
| `matias.rojas@example.test` | Enfermero     | Activa     |
| `tecnico@example.test`      | Técnico       | Activa     |
| `admin@example.test`        | Administrador | Activa     |
| `camila.vera@example.test`  | Médico        | Suspendida |

`pnpm fhir:up` carga 20 pacientes sintéticos en HAPI; no borra recursos legacy adicionales. Son ficticios, no representan indicaciones clínicas reales y deben mantenerse así.

| Ficha    | Paciente          | Ubicación                     | Escenario sintético                               |
| -------- | ----------------- | ----------------------------- | ------------------------------------------------- |
| CRA-0101 | Mercedes Alvarado | Medicina interna, cama 12     | Neumonía, hipertensión y diabetes tipo 2          |
| CRA-0102 | Javier Contreras  | Cirugía, cama 07              | Apendicitis aguda con apendicectomía              |
| CRA-0103 | Rosa Valdés       | UCI adulto, cama 03           | Insuficiencia cardíaca, fibrilación y alergia     |
| CRA-0104 | Tomás Herrera     | Pediatría, cama 04            | Crisis asmática                                   |
| CRA-0105 | Camila Núñez      | Urgencia, cama 06             | Migraña                                           |
| CRA-0106 | Benjamín Fuentes  | Cuidados intermedios, cama 21 | Infarto agudo de miocardio con angioplastía       |
| CRA-0107 | Olga Pizarro      | Medicina interna, cama 14     | EPOC reagudizada e hipotiroidismo                 |
| CRA-0108 | Matías Orellana   | Neonatología, cama 04         | Ictericia neonatal                                |
| CRA-0109 | Lucía Paredes     | Maternidad, cama 09           | Puerperio posterior a cesárea                     |
| CRA-0110 | Héctor Vega       | Medicina interna, cama 05     | Enfermedad renal crónica, diabetes e hipertensión |

El censo de la app proviene de la vista RLS de Supabase. `pnpm fhir:sync` enlaza los recursos del servidor; la pasarela entrega ficha y timeline solo tras autorización. El dataset actual sincroniza 20 pacientes y 20 episodios, 14 abiertos (8 asignados y 6 sin asignar) y 6 cerrados históricos.

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
| Levantar el servidor FHIR de demostración  | `pnpm fhir:up`                  |
| Ver los logs del servidor FHIR             | `pnpm fhir:logs`                |
| Detener el servidor FHIR                   | `pnpm fhir:down`                |
| Enlazar los pacientes de HAPI con Supabase | `pnpm fhir:sync`                |

`pnpm db:purge` es destructivo. Úsalo si se introducen datos reales por error, elimina cualquier exportación o log afectado y revisa las credenciales antes de continuar. No expongas Supabase local mediante túneles ni redes compartidas no confiables.

El servidor HAPI FHIR de demostración no tiene autenticación y guarda sus datos en memoria: `pnpm fhir:down` los elimina y `pnpm fhir:up` los vuelve a cargar. El compose de desarrollo se limita a loopback; el runtime legado aún escucha en `0.0.0.0`, por lo que no lo expongas fuera de tu equipo ni cargues datos clínicos reales.

## Verificación por cambio

- Flutter: `pnpm app:format:check`, `pnpm app:analyze` y las pruebas Dart relacionadas.
- Documentación y JSON: `pnpm docs:format:check`, `pnpm docs:lint` y `git diff --check`.
- Edge Functions: `pnpm functions:check`.
- Migraciones, RLS o funciones SQL: `pnpm db:reset`, `pnpm db:lint` y `pnpm db:test`.
- Servidor FHIR de demostración: `docker compose -f docker/hapi-fhir/docker-compose.yml config` y `node --check scripts/fhir-sync/generate-sync.mjs`.

CI ejecuta `pnpm check` y las pruebas de Flutter. La estrategia completa está en [testing y validación](docs/foundation/11-testing-validation.md).

## Reglas del repositorio

- Trabaja directamente sobre `main` con commits pequeños e independientes.
- Mantén la separación Flutter `data/domain/presentation`; el acceso remoto va detrás de repositorios.
- RLS es la autoridad de autorización. La UI no agrega permisos clínicos.
- No edites migraciones aplicadas: crea una migración aditiva.
- No versiones secretos, credenciales, firmas ni datos clínicos reales. Tampoco versiones `scripts/fhir-sync/fhir-sync.sql`: se genera en cada equipo.
- La app usa la pasarela autenticada para consultas FHIR; HAPI de demostración no autentica solicitudes y debe permanecer local y sintético.
- Cuando cambie una decisión, alcance o contrato, actualiza las ADR y secciones de foundation afectadas.

El contrato de autorización objetivo está en [control de acceso](docs/foundation/05-access-control.md). Para conocer el comportamiento implementado, revisa directamente las políticas, migraciones y pruebas RLS.

## Referencias

- [Fundamentos de producto y arquitectura](docs/foundation/README.md)
- [Arquitectura objetivo](docs/foundation/04-target-architecture.md)
- [Roadmap de entrega](docs/foundation/12-delivery-roadmap.md)
- [Estrategia de pruebas](docs/foundation/11-testing-validation.md)
- [Servidor HAPI FHIR de demostración](docker/hapi-fhir/README.md)
