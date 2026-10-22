# Carer Record App

Aplicacion Flutter movil de Carer Record. La aplicacion se conecta a Supabase con una URL y clave publishable recibidas mediante `--dart-define`; no contiene ni debe contener una Service Role Key.

## Desarrollo local

Los comandos se ejecutan desde la raiz del repositorio. Consulta el [README principal](../README.md) para los requisitos, la configuracion de Supabase local y los comandos disponibles.

En resumen:

```sh
pnpm install --frozen-lockfile
cd app && fvm install && cd ..
cp .env.example .env
pnpm db:start
pnpm fhir:up
pnpm fhir:sync
pnpm app:run
```

Completa `SUPABASE_URL` y `SUPABASE_PUBLISHABLE_KEY` en `.env` con los valores mostrados por `pnpm db:start`. `scripts/run-app.sh` los pasa a Flutter. `.env` esta ignorado por Git.

La lista de pacientes y la ficha clinica se consultan directamente en un servidor HAPI FHIR R4. La URL llega con `--dart-define=FHIR_BASE_URL=...`, que `scripts/run-app.sh` toma de `FHIR_BASE_URL` en `.env`; si esta vacia, vale `http://10.0.2.2:8080/fhir` (emulador Android). En iOS Simulator o en un dispositivo con `adb reverse` usa `http://127.0.0.1:8080/fhir`. El servidor de demostracion esta en `docker/hapi-fhir`; el README principal explica el flujo completo.

## Estructura

- `lib/`: codigo Dart de la aplicacion.
- `lib/main.dart`: inicializa Flutter y Supabase, y crea la aplicacion.
- `lib/core/`: elementos transversales: sistema de diseno, cliente Supabase y router.
- `lib/domains/`: funcionalidades por dominio. Cada dominio separa acceso a datos, entidades y presentacion cuando corresponde.
- `lib/domains/fhir_record/`: lista de pacientes y ficha clinica obtenidas de HAPI FHIR. `data/` contiene el cliente HTTP y el mapper de recursos FHIR al modelo interno, `domain/` las entidades y la regla que enlaza un paciente de FHIR con su hospitalizacion en Supabase, y `presentation/` las pantallas. La UI no ve recursos FHIR crudos.
- `test/`: pruebas Dart y Flutter.
- `pubspec.yaml`: manifiesto, versiones de SDK y dependencias directas (incluye `http` para el cliente FHIR).
- `pubspec.lock`: versiones exactas de las dependencias resueltas; se versiona para obtener instalaciones reproducibles.
- `analysis_options.yaml`: reglas de analisis estatico y linter.
- `.fvmrc`: version de Flutter usada por FVM.
- `.metadata`: metadatos de Flutter para detectar plataformas y actualizaciones; Flutter indica que debe versionarse.

## Plataformas nativas

Flutter comparte la interfaz y la logica en `lib/`, pero requiere proyectos nativos para compilar y distribuir la aplicacion:

- `android/`: proyecto Gradle/Kotlin que genera APK o AAB. Contiene el manifiesto, recursos, iconos, configuracion de compilacion y el punto de entrada Android.
- `ios/`: proyecto Xcode/Swift que genera la aplicacion iOS. Contiene `Info.plist`, recursos, configuracion de Xcode, `Podfile`, `Podfile.lock` y el punto de entrada iOS.

Estos directorios se versionan porque contienen configuracion necesaria para crear la aplicacion y ajustes propios de cada plataforma, como el deep link de recuperacion de contrasena. No son productos de compilacion, aunque Flutter haya creado su estructura inicial.

Los `.gitignore` de la raiz, `android/` e `ios/` excluyen solo artefactos que se pueden regenerar o que son locales: caches, `build/`, `.dart_tool/`, `Pods/`, configuracion generada, rutas locales y keystores. No anadas credenciales ni archivos de firma al repositorio.

## Verificacion

```sh
pnpm app:format:check
pnpm app:analyze
```

Ejecuta las pruebas Dart relacionadas cuando un cambio modifique el comportamiento.
