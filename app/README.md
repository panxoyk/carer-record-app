# Carer Record App

Aplicacion Flutter movil de Carer Record. La aplicacion se conecta a Supabase con una URL y clave publishable recibidas mediante `--dart-define`; no contiene ni debe contener una Service Role Key.

## Desarrollo local

Los comandos se ejecutan desde la raíz del repositorio. Sigue la [primera instalación y bootstrap de Supabase](../README.md#primera-instalación) antes del primer uso.

Arranque normal, con Docker Desktop y un emulador/simulador iniciado:

```sh
pnpm app:run
```

`pnpm app:run` inicia/reutiliza los servicios, prepara la pasarela autorizada y ejecuta Flutter con `SUPABASE_URL` y la clave publishable de `.env`. El archivo `.env` está ignorado por Git.

El censo se consulta desde Supabase mediante contratos protegidos por RLS. La ficha clínica y su timeline usan la pasarela autorizada `clinical-record`; la app no se conecta directamente a HAPI.

## Estructura

- `lib/`: codigo Dart de la aplicacion.
- `lib/main.dart`: inicializa Flutter y Supabase, y crea la aplicacion.
- `lib/core/`: elementos transversales: sistema de diseno, cliente Supabase y router.
- `lib/domains/`: funcionalidades por dominio. Cada dominio separa acceso a datos, entidades y presentacion cuando corresponde.
- `lib/domains/fhir_record/`: lista de pacientes y ficha clínica. `data/` consume contratos autorizados de la pasarela y mapea respuestas al modelo interno; `domain/` contiene entidades y reglas de enlace con hospitalizaciones de Supabase; `presentation/` contiene las pantallas. La app no implementa un cliente directo a HAPI.
- `test/`: pruebas Dart y Flutter.
- `pubspec.yaml`: manifiesto, versiones de SDK y dependencias directas.
- `pubspec.lock`: versiones exactas de las dependencias resueltas; se versiona para obtener instalaciones reproducibles.
- `analysis_options.yaml`: reglas de analisis estatico y linter.
- `.fvmrc`: version de Flutter usada por FVM.
- `.metadata`: metadatos de Flutter para detectar plataformas y actualizaciones; Flutter indica que debe versionarse.

## Verificacion

```sh
pnpm app:format:check
pnpm app:analyze
```

Ejecuta las pruebas Dart relacionadas cuando un cambio modifique el comportamiento.

## Plataformas y proyectos nativos

Flutter comparte interfaz y lógica, con proyectos nativos versionados en `android/` e `ios/` porque contienen configuración de compilación y ajustes de plataforma, como el deep link de recuperación de contraseña. No son productos de compilación. Los `.gitignore` excluyen artefactos regenerables/locales como `build/`, `.dart_tool/`, `Pods/`, rutas locales y keystores; no añadas credenciales ni archivos de firma.

### iOS Simulator

Desde la raíz, abre Xcode workspace y lista simuladores disponibles:

```sh
open app/ios/Runner.xcworkspace
xcrun simctl list devices available
```

Inicia un simulador y ejecuta la app indicando su UDID:

```sh
pnpm app:run -- -d <SIMULATOR_UDID>
```

La URL móvil de Supabase para iOS Simulator es `http://127.0.0.1:54321`. Si CocoaPods queda fuera de sincronía, ejecuta `cd app/ios && pod install` desde la raíz.

### Android Emulator

Inicia un emulador desde Android Studio y ejecuta `pnpm app:run`. La URL móvil de Supabase debe usar `http://10.0.2.2:54321`, el alias del host desde Android Emulator.

### Dispositivo Android físico (opcional)

Los dispositivos físicos no son un entorno soportado y no se ha completado el smoke real. Como prueba opcional por USB/depuración inalámbrica, configura `SUPABASE_URL=http://127.0.0.1:54321` en `.env`, redirige el puerto y usa el entrypoint normal para conservar los servicios:

```sh
adb reverse tcp:54321 tcp:54321
pnpm app:run -- -d <DEVICE_ID>
```

Repite `adb reverse` después de reconectar el dispositivo.

## Modelos locales

La transcripción de voz descarga el archivo de modelo `sherpa-onnx-whisper-base` int8 (archivo comprimido de unos 208 MB; licencia MIT para los pesos) y la asistencia de redacción usa `Qwen3-1.7B-Q4_K_M.gguf` (archivo de unos 1,1 GB; Apache-2.0). El archivo ASR se extrae al instalar; su tamaño de descarga no equivale al espacio instalado. Los pesos no se versionan: sus manifiestos en `assets/` declaran origen, licencia, tamaño y checksums. La app ofrece preparación con progreso, verifica cada descarga y almacena los archivos en el espacio privado de soporte de la app. El uso puede omitirse; sin modelos siguen disponibles las funciones que no dependen de ellos. La gestión en Ajustes permite verificar, limpiar o volver a descargar cada modelo.

Se requiere espacio disponible para las descargas y los archivos extraídos, además de conexión para descargarlos. La inferencia es local; publicar un hito confirmado requiere conexión. Los modelos y su comportamiento se describen en [fundación: audio e IA](../docs/foundation/09-audio-ai-ner.md); su presencia no representa validación clínica.

El proyecto es un prototipo con datos sintéticos y no debe usarse para decisiones asistenciales.
