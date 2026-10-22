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

### 3. Inicia el servidor FHIR de demostración

La app lista los pacientes y consulta su ficha clínica directamente en un servidor HAPI FHIR R4. El repositorio incluye uno de demostración con 10 pacientes sintéticos (ver [docker/hapi-fhir](docker/hapi-fhir/README.md)):

```bash
pnpm fhir:up
pnpm fhir:logs
```

`pnpm fhir:up` levanta HAPI en `http://127.0.0.1:8080/fhir` y carga los pacientes. La primera vez descarga la imagen y el servidor tarda unos minutos en arrancar: espera a que `pnpm fhir:logs` muestre «Pacientes de demostración cargados» y sal con `Ctrl+C`. Después enlaza los pacientes con la bitácora de Supabase:

```bash
pnpm fhir:sync
```

`pnpm fhir:sync` copia a Supabase local el mínimo que necesita la bitácora de cada paciente. Repítelo después de cada `pnpm db:reset`. Si el puerto 8080 está ocupado, usa `HAPI_FHIR_PORT=8081 pnpm fhir:up` y define `FHIR_BASE_URL=http://127.0.0.1:8081/fhir` en `.env`.

### 4. Ejecuta la app

Consulta la sección de tu plataforma y ejecuta `pnpm app:run`. El comando pasa la URL y clave publishable de `.env` a Flutter mediante `--dart-define`. La URL del servidor FHIR (`FHIR_BASE_URL`) se lee de `.env` y vale por defecto `http://10.0.2.2:8080/fhir`, la que corresponde al emulador Android; en otras plataformas defínela en `.env` (ver más abajo).

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

Para iOS Simulator, conserva `SUPABASE_URL=http://127.0.0.1:54321`: el simulador puede acceder al servidor local del Mac mediante loopback. Para el servidor FHIR, define también en `.env` la URL con loopback:

```env
FHIR_BASE_URL=http://127.0.0.1:8080/fhir
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

El servidor FHIR sigue la misma regla: el valor por defecto de `FHIR_BASE_URL` (`http://10.0.2.2:8080/fhir`) ya sirve para el emulador y puedes dejarlo vacío en `.env`.

### Dispositivo Android físico (opcional)

Los dispositivos físicos no forman parte del entorno de desarrollo soportado, pero puedes probar con uno por USB o por depuración inalámbrica redirigiendo los puertos del computador con `adb reverse`, de modo que el teléfono use `127.0.0.1`:

```bash
adb reverse tcp:54321 tcp:54321
adb reverse tcp:8080 tcp:8080
fvm flutter run -d <ID_DEL_DISPOSITIVO> --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=<clave> --dart-define=FHIR_BASE_URL=http://127.0.0.1:8080/fhir
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

## Datos de demostración

`pnpm db:reset` carga pacientes y eventos sintéticos. Todas las cuentas locales usan la contraseña `ChangeMe123!`.

| Email                       | Rol           | Estado     |
| --------------------------- | ------------- | ---------- |
| `ana.torres@example.test`   | Médico        | Activa     |
| `matias.rojas@example.test` | Enfermero     | Activa     |
| `tecnico@example.test`      | Técnico       | Activa     |
| `admin@example.test`        | Administrador | Activa     |
| `camila.vera@example.test`  | Médico        | Suspendida |

`pnpm fhir:up` carga 10 pacientes sintéticos en el servidor HAPI FHIR. Son ficticios, no representan indicaciones clínicas reales y deben mantenerse así.

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

Los pacientes del HAPI y los del censo de Supabase (`pnpm db:reset`) son conjuntos distintos: la lista de la app sale del HAPI y `pnpm fhir:sync` crea en Supabase la hospitalización de cada uno para que tengan bitácora.

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

El servidor HAPI FHIR de demostración no tiene autenticación y guarda sus datos en memoria: `pnpm fhir:down` los elimina y `pnpm fhir:up` los vuelve a cargar. Tampoco lo expongas fuera de tu equipo, y no cargues en él datos clínicos reales.

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
- La app consulta el servidor HAPI FHIR directamente y sin autenticación propia; la restricción por rol es solo de interfaz. Úsalo únicamente con datos sintéticos.
- Cuando cambie una decisión, alcance o contrato, actualiza las ADR y secciones de foundation afectadas.

El contrato de autorización objetivo está en [control de acceso](docs/foundation/05-access-control.md). Para conocer el comportamiento implementado, revisa directamente las políticas, migraciones y pruebas RLS.

## Referencias

- [Fundamentos de producto y arquitectura](docs/foundation/README.md)
- [Arquitectura objetivo](docs/foundation/04-target-architecture.md)
- [Roadmap de entrega](docs/foundation/12-delivery-roadmap.md)
- [Estrategia de pruebas](docs/foundation/11-testing-validation.md)
- [Servidor HAPI FHIR de demostración](docker/hapi-fhir/README.md)
