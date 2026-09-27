# Comparación y decisión de continuidad

## Naturaleza del documento

Esta comparación es una fotografía histórica tomada el 27 de septiembre de 2026 para justificar la elección de repositorio canónico. No se actualiza con cada cambio posterior y no debe usarse para inferir el estado implementado actual.

## Decisión

**Decidido.** El desarrollo continúa en `carer-record-app` (CRA). `carer-record` queda como referencia histórica, conceptual y funcional para recuperar requisitos, decisiones de interfaz y aprendizajes de integración, pero no como base técnica que deba migrarse o endurecerse en paralelo.

La decisión no afirma que CRA tenga más funciones. Afirma que su base actual es más coherente con el alcance académico controlado: datos sintéticos, infraestructura reproducible, autorización verificable y evolución incremental.

## Comparación ejecutiva

| Dimensión                 | `carer-record`                                                                          | CRA                                                                                                   | Evaluación                                                                           |
| ------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Amplitud funcional        | Usuarios CRUD, pacientes clínicos extensos, notas, audio, ASR, FHIR y HL7 experimental. | Acceso, recuperación, practitioners y consulta clínica de solo lectura.                               | Ventaja de amplitud para `carer-record`.                                             |
| Coherencia arquitectónica | Flutter + FastAPI + MariaDB + JWT + disco, con migración Supabase solo planificada.     | Flutter + Supabase local + Edge Functions, sin backend intermedio innecesario para el alcance actual. | Ventaja de coherencia para CRA.                                                      |
| Autorización              | Token emitido, pero rutas de datos sin dependencia de autenticación.                    | RLS por rol y estado, con pruebas permitidas/denegadas.                                               | Ventaja crítica para CRA.                                                            |
| Reproducibilidad          | Requiere MariaDB, servidor, túnel, rutas locales y procesos externos.                   | Migraciones, seed y servicios locales levantados desde comandos versionados.                          | Ventaja para CRA.                                                                    |
| Sesión                    | JWT propio guardado en `SharedPreferences`; biometría reutiliza sesión local.           | Sesión administrada por Supabase Flutter.                                                             | Ventaja de menor superficie para CRA.                                                |
| Datos clínicos            | Modelo amplio para numerosos recursos FHIR.                                             | Modelo mínimo de pacientes y eventos.                                                                 | Mayor riqueza en `carer-record`; menor complejidad en CRA.                           |
| Escritura clínica         | Notas de texto/audio; autor enviado por el cliente.                                     | No existe escritura clínica sin matriz de permisos.                                                   | CRA evita un contrato inseguro; funcionalidad pendiente.                             |
| IA                        | ASR local/remoto; LLM y limpieza simulados.                                             | Resumen protegido pero no implementado.                                                               | `carer-record` aporta experimentación; ninguno completa IA clínica.                  |
| Interoperabilidad         | Importadores FHIR y HL7 experimental directos a MariaDB.                                | Scaffold FHIR sin ingesta.                                                                            | `carer-record` aporta código y aprendizaje, no un pipeline trasladable sin rediseño. |
| Pruebas                   | Sin suite automatizada suficiente.                                                      | pgTAP de RLS/privilegios y unit tests de privacidad/búsqueda.                                         | Ventaja para CRA.                                                                    |
| Estado documental         | El informe afirma Supabase implementado, mientras las fuentes siguen en MariaDB.        | Documentación, roadmap y código describen el mismo alcance.                                           | Ventaja para CRA.                                                                    |
| Producción                | No apto; seguridad, auditoría, offline y migración pendientes.                          | No apto; explícitamente local, sintético y acotado.                                                   | Ninguno es producto clínico.                                                         |

## Diferencias funcionales

### Capacidades presentes solo en `carer-record`

**Confirmado.** El repositorio hermano tiene implementaciones que CRA todavía no ofrece:

- login por correo o RUT y reentrada biométrica (`../carer-record/backend/app/api/v1/routes/auth.py:12`, `../carer-record/app/lib/presentation/auth/login_screen.dart:60`);
- CRUD completo, incluida eliminación de usuarios (`../carer-record/backend/app/api/v1/routes/users.py:107`);
- ficha con múltiples dominios FHIR (`../carer-record/backend/app/api/v1/routes/patients.py:42`);
- notas de texto y audio (`../carer-record/backend/app/api/v1/routes/notes.py:78`, `../carer-record/backend/app/api/v1/routes/notes.py:105`);
- ASR local Sherpa ONNX y remoto `faster-whisper` (`../carer-record/app/lib/data/services/whisper_service.dart:76`, `../carer-record/backend/app/workers/whisper_worker.py:31`);
- importación y sincronización FHIR (`../carer-record/backend/app/fhir/fhir_adapter.py:257`, `../carer-record/backend/app/sync/sync_service.py:225`);
- listener HL7v2 experimental (`../carer-record/integration/README.md:41`).

**Decidido.** Estas capacidades son evidencia de factibilidad y fuente de requisitos. No se consideran listas para copiar porque dependen de contratos y controles que CRA deliberadamente no tiene aún.

### Capacidades presentes solo o mejor resueltas en CRA

**Confirmado.** CRA aporta:

- recuperación de contraseña integrada con Supabase y deep link (`app/lib/domains/auth/data/auth_repository.dart:20`);
- registro público deshabilitado y estados de cuenta explícitos (`supabase/config.toml:18`, `supabase/migrations/20260910010000_auth_administration.sql:2`);
- separación entre autoridad administrativa y clínica (`supabase/tests/patients_rls.test.sql:56-116`);
- políticas RLS como autoridad del acceso (`supabase/migrations/20260910100000_patient_read_access.sql:22`);
- Edge Function con Service Role aislada para crear usuarios (`supabase/functions/create-practitioner/index.ts:74`);
- privilegios SQL endurecidos y probados (`supabase/migrations/20260912000000_harden_function_privileges.sql:45`, `supabase/tests/function_privileges.test.sql:7`);
- migraciones y seed reproducibles (`README.md:41`);
- enmascaramiento de RUT protegido con unit tests (`app/test/domains/patient/domain/entities/patient_test.dart:5`);
- checks locales y CI definidos desde el repositorio (`package.json:33`, `README.md:126`).

## Por qué no continuar en `carer-record`

### La migración objetivo no ocurrió en las fuentes

**Confirmado.** El informe académico afirma Supabase/Auth/PostgreSQL/Storage implementados (`../carer-record/informe/Indice/Revision del Prototipo/alcance-del-prototipo.tex:3`), pero el backend usa MariaDB, JWT propio y disco local (`../carer-record/backend/app/core/config.py:4`, `../carer-record/backend/app/core/security.py:15`, `../carer-record/backend/app/api/v1/routes/notes.py:14`). El plan de migración continúa marcado como planificado (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:3`).

Continuar allí obligaría a resolver simultáneamente una migración de infraestructura, una corrección de seguridad, una consolidación de integraciones y la evolución funcional.

### La autenticación no protege los datos

**Confirmado.** El login emite un JWT, pero los routers de usuarios, pacientes y notas no dependen de él (`../carer-record/backend/app/api/v1/routes/users.py:35`, `../carer-record/backend/app/api/v1/routes/patients.py:8`, `../carer-record/backend/app/api/v1/routes/notes.py:56`). Los servicios Flutter tampoco envían cabecera Bearer (`../carer-record/app/lib/data/remote/patients_service.dart:86`).

Este problema no se corrige con esconder pantallas por rol. Requiere rediseñar identidad, autorización, autoría, aislamiento y pruebas. CRA ya sitúa esa autoridad en RLS.

### Las operaciones clínicas confían en el cliente

**Confirmado.** La creación de notas recibe `author_id` desde Flutter y solo comprueba que el ID exista (`../carer-record/app/lib/data/remote/notes_service.dart:85`, `../carer-record/backend/app/api/v1/routes/notes.py:147`). Un cliente puede atribuir una nota a otro usuario si alcanza el endpoint.

CRA evita por ahora la escritura clínica mediante RLS (`supabase/tests/patients_rls.test.sql:133-169`).

### La operación depende de componentes locales acoplados

**Confirmado.** El flujo depende de MariaDB, Cloudflare Tunnel, rutas absolutas de una Raspberry Pi, worker compartiendo disco y checkpoints JSON (`../carer-record/infra/README.md:125`, `../carer-record/backend/app/workers/whisper_worker.py:54`, `../carer-record/backend/app/sync/sync_service.py:31`). El plan heredado identifica estas dependencias como motivos de migración (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:18`).

### Falta una base de pruebas crítica

**Confirmado.** El repositorio hermano reconoce que no existen pruebas automatizadas suficientes (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:614`). CRA ya protege los contratos de mayor riesgo: RLS, privilegios SQL y privacidad del RUT.

## Por qué continuar en CRA

### Menor base correcta

**Decidido.** CRA implementa menos, pero lo observado tiene límites explícitos: las pruebas demuestran consulta de solo lectura y el pipeline informa que la ingesta está diferida (`supabase/tests/patients_rls.test.sql:133-169`; `scripts/data_pipeline/main.py:9-15`). Esto permite ampliar una dimensión a la vez sin mantener dos arquitecturas activas.

### Autorización cercana a los datos

**Decidido.** RLS reduce la dependencia de que cada pantalla o repositorio recuerde aplicar permisos. Las pruebas confirman denegación a anónimos, administradores clínicamente no autorizados y cuentas suspendidas (`supabase/tests/patients_rls.test.sql:29`, `supabase/tests/patients_rls.test.sql:105`, `supabase/tests/patients_rls.test.sql:118`).

### Infraestructura reproducible

**Decidido.** Migraciones, seed, Supabase local y comandos de verificación viven en el mismo repositorio (`README.md:27`, `README.md:41`, `package.json:6`). Esto es más adecuado para evaluación académica que una combinación de servidor manual, túnel y estado externo.

### Evolución vertical

**Decidido.** CRA adopta un orden: autorización y base de datos, pruebas, modelo/repositorio e interfaz (`AGENTS.md:13-18`). Esa secuencia permite incorporar ingesta, captura o IA sin confundir una pantalla con una capacidad segura y funcional.

### Menor contradicción documental

**Confirmado para la fotografía.** Código, migraciones y pruebas describían el mismo alcance de acceso, administración y lectura clínica (`app/lib/core/router/app_router.dart:16-45`; `supabase/tests/patients_rls.test.sql:29-169`). Las brechas observadas se conservan en este baseline sin pretender mantener su estado posterior.

## Qué recuperar de `carer-record`

### Recuperar como requisitos o diseño

**Propuesto.** Conviene reutilizar conceptualmente:

- la lista de información clínica relevante para una ficha contextual;
- el flujo de bitácora por paciente;
- la captura de texto y audio con estado de revisión;
- los estados de una transcripción remota;
- los mapeos iniciales de recursos FHIR;
- los escenarios académicos de cambio de turno;
- el protocolo de usabilidad y sus tareas.

La recuperación debe expresarse como nuevos contratos y decisiones de CRA, no como copia masiva de archivos.

### No trasladar directamente

**Decidido.** No se deben portar sin rediseño:

- JWT propio, hashes de contraseña o login por RUT del backend;
- almacenamiento de token en `SharedPreferences`;
- endpoints sin dependencia de autorización;
- `author_id` confiado al cliente;
- credenciales de base con fallback;
- SQL y conexiones directas a MariaDB;
- almacenamiento de audio en ruta absoluta;
- worker sin reclamo atómico;
- checkpoints de sincronización en JSON local;
- textos de turno o estado no respaldados por datos;
- placeholders de LLM presentados como capacidad.

## Brechas que CRA debe asumir

Continuar en CRA no elimina el trabajo pendiente. Lo hace visible.

| Brecha                | Estado                                 | Condición antes de implementarla                                           |
| --------------------- | -------------------------------------- | -------------------------------------------------------------------------- |
| Ingesta FHIR          | **Pendiente**                          | Contrato mínimo, procedencia, idempotencia y pruebas reproducibles.        |
| Captura textual       | **Propuesto**                          | Matriz de escritura, autoría desde sesión, RLS e inmutabilidad/corrección. |
| Audio                 | **Futuro**                             | Storage privado, retención, autorización, límites y estados de proceso.    |
| ASR                   | **Futuro**                             | Dispositivo objetivo, corpus sintético, latencia y error medidos.          |
| LLM/NER               | **Futuro**                             | Propósito, proveedor/modelo, privacidad, trazabilidad y revisión humana.   |
| Cambio de turno       | **Futuro**                             | Modelo temporal y zona horaria definidos.                                  |
| Borrador de evolución | **Futuro**                             | Eventos estables, selección de turno y vínculo con fuentes.                |
| Offline               | **Fuera del alcance actual**           | Modelo de sincronización y conflictos separado.                            |
| Producción            | **Fuera del alcance académico actual** | Seguridad, cumplimiento, auditoría, backups y operación institucional.     |

## Secuencia de continuidad

**Propuesto.** La secuencia recomendada es:

1. cerrar pendientes de la consulta de solo lectura;
2. implementar una ingesta FHIR sintética mínima y reproducible;
3. validar que el contexto consultado responde a las tareas académicas;
4. diseñar y probar permisos de escritura para eventos propios;
5. agregar captura textual con revisión y trazabilidad;
6. evaluar audio/ASR como incremento independiente;
7. definir turnos y síntesis solo sobre eventos estables;
8. mantener offline, multihospital y producción fuera de cada incremento hasta acordar sus requisitos.

## Criterio de decisión futura

**Decidido.** La continuidad en CRA se revisará solo si aparece evidencia de que su arquitectura impide un requisito académico confirmado. La mayor cantidad de código en el repositorio hermano no constituye por sí sola esa evidencia.

## Conclusión

**Decidido.** `carer-record` prueba que varios recorridos son técnicamente explorables; CRA ofrece la base desde la cual convertirlos en capacidades delimitadas y verificables. La estrategia es preservar el conocimiento del primero y continuar la implementación exclusivamente en el segundo.
