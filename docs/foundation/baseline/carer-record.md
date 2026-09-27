# Baseline histórico de `carer-record`

## Naturaleza del documento

Este documento es una fotografía histórica tomada el 27 de septiembre de 2026 durante la definición de foundation. Describe la evidencia observada entonces en el repositorio hermano y no se mantiene como estado actual. El código del repositorio correspondiente prevalece ante cualquier diferencia posterior.

## Propósito y criterio de lectura

Este documento describe el repositorio hermano `../carer-record/` en modo de solo lectura. El estado se determina desde el código ejecutable, el esquema y la documentación operativa. Cuando un informe describe una arquitectura distinta a las fuentes, se registra la divergencia y prevalece la implementación observable.

## Resumen ejecutivo

**Confirmado.** `carer-record` es un prototipo amplio que combina una app Flutter, una API FastAPI, MariaDB, archivos de audio en disco, JWT propio, adaptadores FHIR/HL7v2 y dos rutas de transcripción. Su flujo operativo documentado es Flutter → Cloudflare Tunnel → FastAPI → MariaDB (`../carer-record/README.md:166`, `../carer-record/infra/README.md:125`).

**Confirmado.** El repositorio contiene más superficie funcional que CRA: administración CRUD de usuarios, consulta clínica rica, creación de notas de texto, grabación de audio, ASR local/remoto e ingesta FHIR. Sin embargo, los endpoints de usuarios, pacientes, notas y audio carecen de una dependencia de autenticación/autorización, y los servicios Flutter no envían el JWT que guardan (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:161`, `../carer-record/app/lib/data/remote/patients_service.dart:83`, `../carer-record/app/lib/data/remote/notes_service.dart:56`).

**Decidido.** Este repositorio se considera referencia funcional y conceptual, no base de continuidad. Sus capacidades deben reespecificarse y, cuando corresponda, reimplementarse en CRA sin trasladar contratos inseguros ni dependencias operativas heredadas.

## Arquitectura observada

| Capa              | Implementación observable                                                                  | Estado                                                                                                                               |
| ----------------- | ------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------ |
| Aplicación móvil  | Flutter con `provider`, navegación imperativa y servicios HTTP directos.                   | **Confirmado** (`../carer-record/app/lib/main.dart:7`, `../carer-record/app/pubspec.yaml:30`)                                        |
| API               | FastAPI con rutas de auth, usuarios, pacientes y notas.                                    | **Confirmado** (`../carer-record/backend/app/main.py:18`)                                                                            |
| Persistencia      | MariaDB mediante SQLAlchemy y SQL textual; sincronizadores también usan `mysql.connector`. | **Confirmado** (`../carer-record/backend/app/core/config.py:3`, `../carer-record/backend/app/sync/sync_service.py:27`)               |
| Identidad         | Tabla `users`, bcrypt y JWT HS256 propio de ocho horas.                                    | **Confirmado** (`../carer-record/backend/app/core/init_db.sql:16`, `../carer-record/backend/app/core/security.py:6`)                 |
| Sesión móvil      | Token y datos de usuario en `SharedPreferences`.                                           | **Confirmado** (`../carer-record/app/lib/data/local/auth_preferences.dart:3`)                                                        |
| Acceso remoto     | Cloudflare Tunnel hacia FastAPI en un servidor Linux/Raspberry Pi.                         | **Confirmado** (`../carer-record/infra/README.md:125`)                                                                               |
| Audio             | Directorio `/home/pi/carer-record-audio` y worker `faster-whisper`.                        | **Confirmado** (`../carer-record/backend/app/api/v1/routes/notes.py:14`, `../carer-record/backend/app/workers/whisper_worker.py:31`) |
| Interoperabilidad | Importadores y sincronizador FHIR directos a MariaDB; listener HL7v2 experimental.         | **Confirmado / Parcial** (`../carer-record/integration/README.md:25`, `../carer-record/integration/README.md:32`)                    |
| Supabase          | Plan de migración, no infraestructura implementada en las fuentes operativas revisadas.    | **Pendiente** (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:3`)                                                                   |

## Aplicación Flutter

### Navegación y presentación

**Confirmado.** La aplicación arranca en `LoginScreen`, aplica tema claro/oscuro y navega con `Navigator` y `MaterialPageRoute`, sin router declarativo (`../carer-record/app/lib/main.dart:16`, `../carer-record/app/lib/presentation/auth/login_screen.dart:41`).

**Confirmado.** `HomeScreen` carga pacientes al iniciar, permite búsqueda por nombre y filtro por unidad, muestra datos de hospitalización y abre el detalle del paciente (`../carer-record/app/lib/presentation/auth/home_screen.dart:53`, `../carer-record/app/lib/presentation/auth/home_screen.dart:85`, `../carer-record/app/lib/presentation/auth/home_screen.dart:335`).

**Confirmado.** La UI muestra accesos administrativos solo cuando el rol almacenado en el DTO es `admin` (`../carer-record/app/lib/presentation/auth/home_screen.dart:238`). Este control es únicamente visual y no está respaldado por autorización equivalente en la API.

### Autenticación y sesión

**Confirmado.** El login acepta correo o RUT, envía contraseña a `/api/v1/auth/login` y recibe token y datos del usuario (`../carer-record/app/lib/data/remote/auth_service.dart:7`, `../carer-record/backend/app/api/v1/routes/auth.py:10`).

**Confirmado.** La app persiste token, ID, nombre, rol y correo en `SharedPreferences`; la reentrada biométrica desbloquea esa sesión local, pero no revalida el token con el servidor (`../carer-record/app/lib/data/local/auth_preferences.dart:11`, `../carer-record/app/lib/presentation/auth/login_screen.dart:80`).

**Confirmado.** No existe recuperación de contraseña, renovación, revocación ni validación de sesión al reingresar. El JWT contiene ID, rol y nombre, expira en 480 minutos y se firma con un secreto configurable que tiene un valor de desarrollo por defecto (`../carer-record/backend/app/core/security.py:6`, `../carer-record/backend/app/core/config.py:4`).

### Administración de usuarios

**Confirmado.** La app lista y filtra usuarios por rol, crea, edita y elimina cuentas (`../carer-record/app/lib/presentation/admin/users_screen.dart:36`, `../carer-record/app/lib/presentation/admin/user_form_screen.dart:53`). La API implementa CRUD sobre `users`, hash de contraseña y detección de email/RUT duplicado en creación (`../carer-record/backend/app/api/v1/routes/users.py:35`, `../carer-record/backend/app/api/v1/routes/users.py:42`).

**Confirmado.** Los servicios de usuarios no adjuntan `Authorization` (`../carer-record/app/lib/data/remote/users_service.dart:32`) y las rutas FastAPI no exigen usuario actual ni rol administrador (`../carer-record/backend/app/api/v1/routes/users.py:35`). Por tanto, la restricción visual del menú no protege la operación.

### Consulta de pacientes

**Confirmado.** El listado devuelve pacientes activos y no fallecidos con ubicación, fechas y diagnóstico principal (`../carer-record/backend/app/api/v1/routes/patients.py:8`). Flutter permite buscar por nombre y filtrar por unidad (`../carer-record/app/lib/presentation/admin/patients_screen.dart:64`).

**Confirmado.** El detalle devuelve datos demográficos y once grupos clínicos: encuentros, condiciones, medicamentos, observaciones, alergias, procedimientos, inmunizaciones, informes diagnósticos, imágenes, dispositivos, planes y equipo de cuidado (`../carer-record/backend/app/api/v1/routes/patients.py:42`, `../carer-record/app/lib/presentation/admin/patient_detail_screen.dart:31`). La interfaz presenta cada grupo en secciones colapsables (`../carer-record/app/lib/presentation/admin/patient_detail_screen.dart:616`).

**Confirmado.** La API de pacientes tampoco exige token ni filtra por rol, hospital, unidad o relación asistencial (`../carer-record/backend/app/api/v1/routes/patients.py:8`). Todos los clientes capaces de alcanzar la API pueden intentar consultar el conjunto completo.

### Bitácora y notas

**Confirmado.** La UI lista notas por paciente, filtra texto, voz y pendientes, ordena según la respuesta de API y hace polling cada cinco segundos mientras exista transcripción pendiente (`../carer-record/app/lib/presentation/admin/notes_screen.dart:79`, `../carer-record/app/lib/presentation/admin/notes_screen.dart:103`, `../carer-record/app/lib/presentation/admin/notes_screen.dart:127`).

**Confirmado.** El usuario puede crear una nota textual o grabar audio. El formulario textual exige al menos 20 caracteres; la nota envía `patient_id`, `author_id`, contenido, método y fuente (`../carer-record/app/lib/presentation/admin/register_event_screen.dart:378`, `../carer-record/app/lib/data/remote/notes_service.dart:77`).

**Confirmado.** El backend confía en el `author_id` recibido del cliente, verifica solo que paciente y autor existan y persiste la nota (`../carer-record/backend/app/api/v1/routes/notes.py:78`, `../carer-record/backend/app/api/v1/routes/notes.py:147`). No deriva la autoría desde una sesión autenticada.

**Confirmado.** La bitácora etiqueta “Hoy · Turno 08:00–16:00”, pero no filtra realmente por turno (`../carer-record/app/lib/presentation/admin/notes_screen.dart:303`). La documentación académica reconoce esta limitación (`../carer-record/informe/Indice/Revision del Prototipo/limitaciones-identificadas.tex:7`).

### Audio y ASR

**Confirmado.** La ruta local descarga modelos Whisper Base o Small, graba WAV de 16 kHz mono y transcribe con Sherpa ONNX en el dispositivo (`../carer-record/app/lib/presentation/settings/ai_settings_screen.dart:24`, `../carer-record/app/lib/data/services/whisper_service.dart:16`, `../carer-record/app/lib/data/services/whisper_service.dart:76`). El texto local se presenta editable antes de publicarse (`../carer-record/app/lib/presentation/admin/register_event_screen.dart:283`, `../carer-record/app/lib/presentation/admin/register_event_screen.dart:763`).

**Confirmado.** Cuando no hay modelo local, Flutter sube el WAV; FastAPI lo guarda en una ruta absoluta, crea una nota `pending` y el worker actualiza `processing`, `done` o `error` (`../carer-record/backend/app/api/v1/routes/notes.py:105`, `../carer-record/backend/app/workers/whisper_worker.py:38`). La app reproduce el audio y habilita confirmación después de escucharlo (`../carer-record/app/lib/presentation/admin/notes_screen.dart:494`).

**Confirmado.** La selección del trabajo en el worker no usa bloqueo ni reclamo atómico; dos workers pueden seleccionar la misma fila antes de marcarla (`../carer-record/backend/app/workers/whisper_worker.py:39`). La descarga de audio tampoco exige autorización (`../carer-record/backend/app/api/v1/routes/notes.py:39`).

### LLM, limpieza y borrador

**Pendiente.** T5 y Gemma tienen URL `placeholder`; la acción de limpieza espera un segundo y muestra un resultado simulado (`../carer-record/app/lib/presentation/settings/ai_settings_screen.dart:27`, `../carer-record/app/lib/presentation/settings/ai_settings_screen.dart:348`). El registro de eventos también informa que la limpieza con IA está pendiente (`../carer-record/app/lib/presentation/admin/register_event_screen.dart:384`).

**Pendiente.** “Borrador de evolución” aparece como `comingSoon` y no tiene servicio (`../carer-record/app/lib/presentation/admin/patient_detail_screen.dart:584`).

### Offline

**Pendiente.** No hay Drift/SQLite, caché clínica, cola de escrituras ni resolución de conflictos. La documentación lo declara como diseño objetivo, no implementación actual (`../carer-record/README.md:174`) y el informe limita la operación sin conexión al ASR local con el modelo ya descargado (`../carer-record/informe/Indice/Revision del Prototipo/limitaciones-identificadas.tex:8`).

## Backend y persistencia

### API y base de datos

**Confirmado.** FastAPI expone raíz, health check y routers para auth, usuarios, pacientes y notas (`../carer-record/backend/app/main.py:18`). El health check captura excepciones pero responde un objeto de error sin cambiar explícitamente el código HTTP (`../carer-record/backend/app/main.py:27`).

**Confirmado.** SQLAlchemy crea un engine directo desde `DATABASE_URL` sin configuración explícita de pool, `pool_pre_ping` o rollback en el generador de sesión (`../carer-record/backend/app/core/database.py:6`). Las rutas usan consultas SQL parametrizadas, salvo la composición controlada de campos de actualización de usuarios (`../carer-record/backend/app/api/v1/routes/users.py:87`).

**Confirmado.** El esquema MariaDB incluye usuarios, pacientes, notas, cambios de turno, staging HL7v2, log FHIR y múltiples recursos clínicos (`../carer-record/backend/app/core/init_db.sql:16`, `../carer-record/backend/app/core/init_db.sql:31`, `../carer-record/backend/app/core/init_db.sql:65`, `../carer-record/backend/app/core/init_db.sql:87`).

**Confirmado.** `shift_changes` existe solo en el esquema; no hay router ni pantalla que complete el flujo de entrega/recepción (`../carer-record/backend/app/core/init_db.sql:87`, `../carer-record/backend/app/main.py:18`).

### Seguridad observable

**Confirmado.** El login verifica cuenta activa y contraseña antes de emitir el JWT (`../carer-record/backend/app/api/v1/routes/auth.py:21`).

**Confirmado.** La API no consume ese JWT en las rutas de datos revisadas. Usuarios, pacientes, notas, confirmación y audio son accesibles sin una dependencia común de autenticación (`../carer-record/backend/app/api/v1/routes/users.py:35`, `../carer-record/backend/app/api/v1/routes/patients.py:8`, `../carer-record/backend/app/api/v1/routes/notes.py:25`).

**Confirmado.** Existen valores inseguros de desarrollo como fallback para base de datos, secreto JWT e importador FHIR (`../carer-record/backend/app/core/config.py:4`, `../carer-record/backend/app/fhir/fhir_adapter.py:25`). Esto no demuestra exposición en un despliegue, pero sí impide considerar segura la configuración por defecto.

**Confirmado.** No se observó aislamiento multihospital, auditoría inmutable ni autorización por paciente. El plan de migración los identifica como requisitos aún no implementados (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:121`, `../carer-record/infra/MIGRATION_TO_SUPABASE.md:161`).

## Integración hospitalaria

### FHIR por bundles

**Confirmado.** El importador procesa bundles JSON FHIR R4, crea pacientes y recursos clínicos, registra sincronización y evita repetir recursos ya presentes en `fhir_sync_log` (`../carer-record/backend/app/fhir/fhir_adapter.py:257`, `../carer-record/backend/app/fhir/fhir_adapter.py:382`). Soporta Encounter, Condition, MedicationRequest, Observation, AllergyIntolerance, Procedure, Immunization, DiagnosticReport, ImagingStudy, CarePlan, CareTeam y Device (`../carer-record/backend/app/fhir/fhir_adapter.py:360`).

**Confirmado.** El importador usa MariaDB y credenciales incorporadas como fallback, no Supabase ni una API de ingesta (`../carer-record/backend/app/fhir/fhir_adapter.py:21`, `../carer-record/backend/app/fhir/fhir_adapter.py:25`).

### Sincronización incremental

**Confirmado.** `sync_service.py` consulta un servidor FHIR por `_lastUpdated`, pagina, hace commit por página y guarda checkpoints en `fhir_sync_state.json` (`../carer-record/backend/app/sync/sync_service.py:225`, `../carer-record/backend/app/sync/sync_service.py:274`, `../carer-record/backend/app/sync/sync_service.py:157`). La configuración externa selecciona recursos, extensiones y tablas por clínica (`../carer-record/backend/config/clinics/carer-record.json:1`).

**Confirmado.** La clave de sincronización no incluye hospital o fuente; el propio plan advierte riesgo de colisión entre instituciones (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:121`). Tampoco se observó exclusión mutua entre procesos de sincronización.

### HL7v2

**Parcial.** La documentación registra un listener MLLP para ADT como “en desarrollo” (`../carer-record/integration/README.md:41`). Su existencia no equivale a un flujo reproducible de extremo a extremo; el informe académico también lo califica experimental (`../carer-record/informe/Indice/Revision del Prototipo/funcionalidades-demostradas.tex:13`).

## Pruebas y validación

**Confirmado.** No se encontraron suites automatizadas de Dart, API, persistencia o integración en las rutas revisadas. El plan de migración declara que no existen pruebas automatizadas suficientes (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:614`).

**Pendiente.** Falta evidencia reproducible para autorización, ingesta, audio, idempotencia, errores y recuperación. También falta validación con personal médico y de enfermería (`../carer-record/informe/Indice/Verificacion y Validacion/validacion-del-prototipo.tex:3`).

## Divergencia documental

**Confirmado.** El informe de Hito 3 afirma que Flutter, FastAPI cloud y Supabase están implementados, incluyendo Auth, PostgreSQL y Storage (`../carer-record/informe/Indice/Revision del Prototipo/alcance-del-prototipo.tex:3`). Sin embargo:

- el README vigente define MariaDB como estado actual y Supabase como diseño objetivo (`../carer-record/README.md:11`);
- la configuración backend usa `mysql+pymysql` (`../carer-record/backend/app/core/config.py:4`);
- la autenticación es JWT propio (`../carer-record/backend/app/core/security.py:15`);
- el audio se guarda en `/home/pi/carer-record-audio` (`../carer-record/backend/app/api/v1/routes/notes.py:14`);
- el documento de migración a Supabase figura como “planificado” y conserva todas sus fases sin marcar (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:1`).

**Decidido.** Para esta fundación, la arquitectura Supabase/FastAPI cloud del informe se trata como arquitectura objetivo no corroborada por las fuentes ejecutables del repositorio.

## Capacidades y límites finales

| Área                   | Clasificación                                   | Conclusión                                                                     |
| ---------------------- | ----------------------------------------------- | ------------------------------------------------------------------------------ |
| Login email/RUT        | **Confirmado**                                  | Funciona contra JWT propio y MariaDB.                                          |
| Reentrada biométrica   | **Confirmado**                                  | Desbloquea una sesión local guardada; no revalida servidor.                    |
| CRUD de usuarios       | **Confirmado funcional / inseguro**             | Existe de extremo a extremo, sin autorización backend.                         |
| Consulta clínica rica  | **Confirmado funcional / inseguro**             | Amplia cobertura de recursos, sin protección de endpoints.                     |
| Notas de texto         | **Confirmado funcional / inseguro**             | Autor confiado al cliente y API sin autenticación.                             |
| Audio y ASR remoto     | **Confirmado parcial**                          | Persistencia y worker existen; faltan controles y concurrencia segura.         |
| ASR local              | **Confirmado en código / Pendiente de validar** | Implementado con Sherpa ONNX; sin medición en dispositivo objetivo.            |
| LLM, NER y borrador    | **Pendiente**                                   | Placeholders o UI futura.                                                      |
| Cambio de turno y alta | **Pendiente**                                   | Hay esquema o textos, no flujo funcional.                                      |
| FHIR                   | **Confirmado parcial**                          | Importación y sync existen; falta evidencia reproducible y modelo multifuente. |
| HL7v2                  | **Parcial**                                     | Experimental.                                                                  |
| Offline clínico        | **Pendiente**                                   | No implementado.                                                               |
| Seguridad y auditoría  | **Pendiente crítico**                           | Impide datos reales o uso asistencial.                                         |
| Supabase               | **Pendiente en este repo**                      | Documentado como migración objetivo.                                           |

## Conclusión

**Decidido.** `carer-record` demuestra ideas y recorridos valiosos, en especial captura multimodal, consulta clínica extensa e integración FHIR. No ofrece una base segura ni coherente para continuar: combina una arquitectura operativa heredada, una migración no ejecutada, endpoints sin autorización y documentación que sobredeclara el estado. Debe conservarse como fuente de requisitos, UI y aprendizaje, no como implementación canónica.
