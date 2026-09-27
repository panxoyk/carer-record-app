# Baseline histórico de `carer-record-app` (CRA)

## Naturaleza del documento

Este documento es una fotografía histórica de `carer-record-app` en el commit `922f3877bdd4ba0b8087f13067bab69d1c165dd6`, tomada el 27 de septiembre de 2026 durante la definición de foundation. No se mantiene como estado actual; el código, las migraciones y las pruebas prevalecen ante cualquier diferencia posterior.

## Resumen ejecutivo

**Confirmado.** CRA es un monorepo de prototipo móvil con Flutter, Supabase local versionado, Edge Functions y un scaffold Python para futura ingesta FHIR. Implementa acceso, recuperación de contraseña, administración de practitioners y consulta de pacientes y eventos clínicos en modo de solo lectura (`README.md:1`; `app/`; `supabase/`; `scripts/data_pipeline/main.py:1-15`).

**Confirmado.** La autorización se apoya en RLS, no en la UI. Los roles asistenciales activos leen pacientes y eventos; los administradores gestionan usuarios sin acceso clínico implícito; las cuentas suspendidas no conservan privilegios (`supabase/tests/patients_rls.test.sql:29-169`).

**Confirmado.** CRA es más estrecho que el repositorio hermano. No contiene notas, audio, ASR, LLM, cierre de turno, offline ni ingesta FHIR funcional. Esas ausencias son límites explícitos, no comportamiento implícito.

## Estructura y tecnologías

| Área                 | Implementación                                                     | Estado                                                                                   |
| -------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------- |
| App móvil            | Flutter 3.29.3, Dart >=3.7, Riverpod, GoRouter y Supabase Flutter. | **Confirmado** (`app/pubspec.yaml:6`, `app/pubspec.yaml:10`)                             |
| Datos e identidad    | Supabase Auth, PostgreSQL y PostgREST en entorno local.            | **Confirmado** (`app/lib/core/network/supabase_client.dart:5`, `supabase/config.toml:3`) |
| Backend privilegiado | Edge Function Deno para crear practitioners.                       | **Confirmado** (`supabase/functions/create-practitioner/index.ts:21`)                    |
| IA                   | Frontera autenticada `clinical-summary` que responde 501.          | **Pendiente** (`supabase/functions/clinical-summary/index.ts:17`)                        |
| Ingesta              | Scaffold Python reservado para FHIR.                               | **Pendiente** (`scripts/data_pipeline/main.py:2`)                                        |
| Gestión del repo     | pnpm, FVM, Deno, Supabase CLI, Lefthook y CI.                      | **Confirmado** (`package.json:5`, `package.json:7`, `.github/workflows/verify.yml:1`)    |

## Aplicación Flutter

### Inicialización

**Confirmado.** `main` inicializa Supabase con URL y clave publishable recibidas mediante `--dart-define`, crea un `ProviderScope` y usa `MaterialApp.router` con el tema clínico compartido (`app/lib/main.dart:8`, `app/lib/main.dart:17`).

**Confirmado.** La URL y clave publishable proceden de `.env` a través del script de ejecución; no son credenciales privilegiadas (`scripts/run-app.sh:1-24`; `app/lib/main.dart:8-18`).

### Organización

**Confirmado.** El código está organizado verticalmente por `auth`, `practitioner`, `patient`, `clinical_event` y `users`, con separación `data/domain/presentation` donde aplica. El acceso remoto queda detrás de repositorios (`app/lib/domains/`).

**Confirmado.** `patient`, `practitioner` y `clinical_event` tienen entidades y modelos tipados. Los providers de Riverpod construyen repositorios y exponen consultas asíncronas (`app/lib/domains/patient/presentation/patient_providers.dart:7`, `app/lib/domains/practitioner/presentation/practitioner_providers.dart:8`, `app/lib/domains/clinical_event/presentation/clinical_event_providers.dart:7`).

### Navegación y autorización visual

**Confirmado.** GoRouter reacciona a cambios de Auth y protege rutas según sesión, recuperación, perfil, estado y rol (`app/lib/core/router/app_router.dart:11`).

El flujo observable es:

1. sin sesión, solo `/login` y `/recover` permanecen accesibles (`app/lib/core/router/app_router.dart:18`);
2. durante recuperación, toda navegación conduce a `/update-password` (`app/lib/core/router/app_router.dart:22`);
3. perfil ausente o suspendido conduce a `/suspended` (`app/lib/core/router/app_router.dart:28`);
4. un rol asistencial que entra a `/` se redirige a `/patients` (`app/lib/core/router/app_router.dart:35`);
5. solo administrador llega a `/users` (`app/lib/core/router/app_router.dart:38`);
6. el administrador es apartado de rutas `/patients` (`app/lib/core/router/app_router.dart:41`).

**Confirmado.** Estos guards mejoran experiencia, pero la seguridad efectiva reside en RLS (`supabase/migrations/20260910100000_patient_read_access.sql:10-48`).

## Identidad y sesión

### Acceso

**Confirmado.** `AuthRepository` usa `signInWithPassword`, recorta el email y delega la sesión al SDK de Supabase (`app/lib/domains/auth/data/auth_repository.dart:8`). La pantalla gestiona estado ocupado y error genérico (`app/lib/domains/auth/presentation/auth_screens.dart:49`).

### Recuperación

**Confirmado en código.** La solicitud usa el deep link `io.carerrecord.app://login-callback/recover`; la pantalla de actualización exige seis caracteres antes de llamar a Supabase (`app/lib/domains/auth/data/auth_repository.dart:20`, `app/lib/domains/auth/presentation/auth_screens.dart:177`). El redirect está permitido en Supabase local (`supabase/config.toml:18`).

**Pendiente de validación en la fotografía.** No se encontró evidencia reproducible del recorrido con aplicación abierta y cerrada.

### Registro público y suspensión

**Confirmado.** El registro público global está deshabilitado (`supabase/config.toml:18`). Los usuarios se crean mediante administración, y un perfil suspendido solo recibe la pantalla de suspensión y cierre de sesión (`app/lib/core/router/app_router.dart:121`).

### Persistencia de sesión

**Confirmado.** CRA delega manejo de sesión al SDK `supabase_flutter`; no contiene una implementación propia de tokens en `SharedPreferences`. Esto reduce superficie respecto del repositorio hermano, aunque no equivale a una evaluación de almacenamiento seguro para datos reales.

## Practitioners y administración

### Modelo

**Confirmado.** Los roles son `physician`, `nurse`, `technician` y `administrator`; los estados son `active` y `suspended` (`supabase/migrations/20260910000000_initial_clinical_schema.sql:4`, `supabase/migrations/20260910010000_auth_administration.sql:2`). El perfil referencia a `auth.users` y contiene nombre, rol, licencia opcional y timestamps (`supabase/migrations/20260910000000_initial_clinical_schema.sql:7`).

### Lectura y actualización

**Confirmado.** El repositorio obtiene el perfil actual, lista practitioners y actualiza rol o estado mediante PostgREST (`app/lib/domains/practitioner/data/practitioner_repository.dart:11`, `app/lib/domains/practitioner/data/practitioner_repository.dart:21`, `app/lib/domains/practitioner/data/practitioner_repository.dart:44`).

**Confirmado.** La UI excluye al usuario actual de la lista editable y ofrece activar, suspender o cambiar rol (`app/lib/domains/users/presentation/users_screen.dart:46`). La exclusión evita una acción accidental en interfaz; RLS sigue siendo la autoridad.

### Creación

**Confirmado.** Flutter invoca `create-practitioner` con email, contraseña inicial, nombre y rol (`app/lib/domains/practitioner/data/practitioner_repository.dart:29`). La función:

- acepta solo POST (`supabase/functions/create-practitioner/index.ts:21`);
- exige cabecera de autorización y obtiene el usuario del JWT (`supabase/functions/create-practitioner/index.ts:26`);
- comprueba que el llamador sea administrador activo (`supabase/functions/create-practitioner/index.ts:38`);
- valida tipos y rol (`supabase/functions/create-practitioner/index.ts:47`);
- usa Service Role en un cliente separado (`supabase/functions/create-practitioner/index.ts:74`);
- crea `auth.users` y luego `practitioners` (`supabase/functions/create-practitioner/index.ts:80`);
- intenta borrar el usuario Auth si falla la creación del perfil (`supabase/functions/create-practitioner/index.ts:88`).

**Pendiente en la fotografía.** La UI no presenta validación completa, estado de envío, error visible ni retry para creación/actualización (`app/lib/domains/users/presentation/users_screen.dart:140`).

## Consulta clínica

### Modelo de pacientes

**Confirmado.** `patients` contiene UUID, referencia externa, nombre, fecha de nacimiento, payload JSON objeto y timestamps; una migración posterior agrega RUT, unidad y cama con normalización y constraints (`supabase/migrations/20260910000000_initial_clinical_schema.sql:16`, `supabase/migrations/20260910110000_clinical_timeline.sql:1`).

**Confirmado.** El repositorio móvil selecciona exclusivamente `id`, referencia, RUT, nombre, nacimiento, unidad y cama; lista ordenada por apellido/nombre y busca un paciente por ID (`app/lib/domains/patient/data/patient_repository.dart:9`).

### Listado y búsqueda

**Confirmado.** `PatientsScreen` carga todos los pacientes autorizados, construye filtros de unidad y realiza búsqueda local (`app/lib/domains/patient/presentation/patient_screens.dart:90`). La búsqueda normaliza mayúsculas, espacios, diacríticos y RUT (`app/lib/domains/patient/domain/entities/patient.dart:24`, `app/lib/domains/patient/domain/entities/patient.dart:59`).

**Confirmado.** Las tarjetas muestran nombre, ubicación y RUT enmascarado (`app/lib/domains/patient/presentation/patient_screens.dart:189`). La regla de enmascaramiento revela solo los últimos tres dígitos y oculta por completo formatos inesperados (`app/lib/domains/patient/domain/entities/patient.dart:41`).

### Ficha

**Confirmado.** La vista de información muestra nombre, nacimiento, ubicación, referencia externa, RUT, unidad y cama (`app/lib/domains/patient/presentation/patient_screens.dart:686`).

**Pendiente en la fotografía.** Los rótulos “Activo” y “Hospitalización activa” son constantes visuales, no resultados de campos de estado o encuentro (`app/lib/domains/patient/presentation/patient_screens.dart:743`, `app/lib/domains/patient/presentation/patient_screens.dart:814`).

### Eventos clínicos

**Confirmado.** `clinical_events` almacena paciente, practitioner registrador opcional, tipo, instante, payload JSON objeto y creación (`supabase/migrations/20260910000000_initial_clinical_schema.sql:28`). El payload debe contener un `summary` string no vacío (`supabase/migrations/20260910110000_clinical_timeline.sql:45`).

**Confirmado.** El repositorio obtiene eventos por paciente y los ordena de más reciente a más antiguo (`app/lib/domains/clinical_event/data/clinical_event_repository.dart:10`). La UI presenta fecha, categoría y resumen, y filtra localmente (`app/lib/domains/patient/presentation/patient_screens.dart:465`).

**Pendiente en la fotografía.** El encabezado “HOY” es constante y la presentación no define conversión de zona horaria (`app/lib/domains/patient/presentation/patient_screens.dart:407`).

## Persistencia y autorización

### Esquema

**Confirmado.** Las migraciones versionan tres tablas: `practitioners`, `patients` y `clinical_events`, con enums, claves foráneas, constraints e índices (`supabase/migrations/20260910000000_initial_clinical_schema.sql:4`). No existe tabla de notas, turnos, hospitales, fuentes, audio o auditoría.

### RLS administrativa

**Confirmado.** Cada practitioner lee su perfil; un administrador activo puede listar, insertar, actualizar y eliminar perfiles por políticas RLS (`supabase/migrations/20260910010000_auth_administration.sql:23`). La creación de `auth.users` permanece en la Edge Function porque requiere Service Role (`supabase/functions/create-practitioner/index.ts:29-45`).

### RLS clínica

**Confirmado.** `can_read_patients()` exige perfil activo y rol asistencial (`supabase/migrations/20260910100000_patient_read_access.sql:3`). `can_read_clinical_events()` reutiliza esa regla (`supabase/migrations/20260910110000_clinical_timeline.sql:54`). Solo existen políticas `SELECT`; no hay políticas de escritura clínica.

**Confirmado.** Una migración endurece los helpers `security definer` con `search_path` vacío, revoca ejecución a `public` y `anon`, y oculta funciones internas de trigger a clientes autenticados (`supabase/migrations/20260912000000_harden_function_privileges.sql:1`).

### Datos de desarrollo

**Confirmado.** El seed crea cuentas y datos sintéticos con una contraseña común de demostración; el README enumera roles y estado (`README.md:100`; `supabase/seed.sql:1-247`). Estos datos son exclusivamente locales y no deben reutilizarse fuera del entorno controlado.

## Edge Functions e IA

### `create-practitioner`

**Confirmado.** Es una operación administrativa funcional con separación entre credenciales del llamador y Service Role. Su verificación automatizada observada se limita a formato, lint y tipos (`package.json:21-26`).

### `clinical-summary`

**Confirmado como frontera, no como feature.** La función exige `Authorization`, valida el usuario contra Supabase y responde `501` con `not_implemented` (`supabase/functions/clinical-summary/index.ts:3`). No consulta datos, no invoca IA y no genera resumen.

## Pipeline de datos

**Pendiente.** `scripts/data_pipeline/main.py` solo acepta `--check`, imprime que el scaffold está listo y declara la ingesta FHIR intencionalmente diferida (`scripts/data_pipeline/main.py:9`). `pyproject.toml` reserva Python >=3.14 y el nombre del paquete (`scripts/data_pipeline/pyproject.toml:1`).

**Confirmado.** El pipeline ejecutable informa que la ingesta FHIR está diferida (`scripts/data_pipeline/main.py:9-15`).

## Calidad y pruebas

### Automatización

**Confirmado.** `package.json` ofrece checks separados para Flutter, pipeline, Edge Functions, documentación y base de datos, y compone verificaciones no dependientes de servicios en `pnpm check` (`package.json:15`, `package.json:20`, `package.json:33`). Lefthook instala ese check antes de commit (`package.json:7`).

### Base de datos

**Confirmado.** pgTAP cubre:

- perfil propio y prohibición de autoelevación (`supabase/tests/practitioners_rls.test.sql:27`);
- administración activa y suspensión (`supabase/tests/practitioners_rls.test.sql:71`);
- denegación a anónimos y sesiones sin perfil (`supabase/tests/patients_rls.test.sql:29`);
- lectura por los tres roles asistenciales (`supabase/tests/patients_rls.test.sql:56`);
- denegación a administrador y cuenta suspendida (`supabase/tests/patients_rls.test.sql:105`);
- ausencia de escritura clínica (`supabase/tests/patients_rls.test.sql:133`);
- privilegios de funciones SQL (`supabase/tests/function_privileges.test.sql:7`).

### Dart

**Confirmado.** Existe una suite de dominio para enmascaramiento y búsqueda de RUT/nombre (`app/test/domains/patient/domain/entities/patient_test.dart:5`). En la fotografía no se encontraron pruebas de widgets, router, repositorios ni Auth.

### Brechas de evidencia

**Pendiente en la fotografía.** No se encontraron pruebas HTTP de Edge Functions ni integración automatizada móvil-Supabase. Esto limita lo que puede declararse validado.

## Operación local

**Confirmado.** El entorno requiere Node/pnpm, Deno, Docker, FVM/Flutter y herramientas iOS cuando corresponda (`README.md:7`). Supabase se levanta localmente, `.env` queda ignorado y `db:reset` reconstruye migraciones y seed (`README.md:27`, `README.md:41`).

**Confirmado.** iOS Simulator usa loopback y Android Emulator usa `10.0.2.2` para alcanzar la máquina host (`README.md:53`, `README.md:72`). Dispositivos físicos no forman parte del entorno actual (`README.md:98`).

## Limitaciones y riesgos conocidos

| Limitación                     | Estado                      | Consecuencia                                                              |
| ------------------------------ | --------------------------- | ------------------------------------------------------------------------- |
| Solo lectura clínica           | **Decidido**                | No demuestra captura de contexto, notas ni cierre de turno.               |
| FHIR no implementado           | **Pendiente**               | Los pacientes/eventos dependen de seed o carga externa no documentada.    |
| IA no implementada             | **Pendiente**               | `clinical-summary` es solo una frontera autenticada.                      |
| Textos clínicos no respaldados | **Pendiente**               | La UI puede sugerir asignación, estado u horizonte temporal inexistentes. |
| Zona horaria indefinida        | **Pendiente**               | La fecha/hora mostrada puede ser ambigua.                                 |
| Error y retry incompletos      | **Pendiente**               | Algunos fallos asíncronos no tienen recuperación clara.                   |
| Listas completas               | **Fuera de alcance actual** | No escala a grandes volúmenes sin paginación/búsqueda remota.             |
| Sin auditoría                  | **Fuera de alcance actual** | No es apto para operación clínica real.                                   |
| Sin multihospital/procedencia  | **Fuera de alcance actual** | No representa aún integraciones institucionales múltiples.                |
| Sin offline clínico            | **Fuera de alcance actual** | Requiere conectividad con Supabase.                                       |
| Sin despliegue productivo      | **Fuera de alcance**        | El entorno validado es local con datos sintéticos.                        |

## Conclusión

**Confirmado.** CRA proporciona una base pequeña, reproducible y explícitamente autorizada para consulta clínica sintética. Su fortaleza no es la amplitud funcional, sino la coherencia entre alcance, RLS, migraciones, pruebas críticas y documentación.

**Decidido.** Debe continuar como implementación canónica. Las capacidades futuras se agregarán verticalmente y no se declararán funcionales hasta tener permisos, persistencia, pruebas y recorrido móvil acordes con la definición académica.
