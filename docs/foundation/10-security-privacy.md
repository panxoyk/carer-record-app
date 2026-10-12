# Seguridad y privacidad

El corte RLS clínico revoca `SELECT` completo en `patients` y `clinical_events`, incluyendo RUT, referencias externas, JSONB, `recorded_by` y columnas no necesarias. Tres vistas por hospitalización usan `security_invoker=true` y `security_barrier=true`; dependen de grants de columnas y RLS del invocador y no tienen acceso para `anon`. `clinical_events.summary` es una proyección tipada sincronizada desde payload dentro de PostgreSQL; el payload bruto no se concede ni se devuelve.

## Propósito y límite de aseguramiento

Este documento define controles y criterios de validación para el prototipo académico Carer Record. Describe una arquitectura objetivo y un método de trabajo; no certifica cumplimiento normativo, seguridad productiva, anonimización ni aptitud clínica. El estado implementado se limita a autenticación, administración de usuarios y lectura clínica sobre datos sintéticos, según `README.md:1-4`. Antes de usar datos reales se requieren, como mínimo, revisión jurídica, evaluación de impacto de privacidad, modelado institucional de amenazas, gestión operativa de incidentes y aprobación del responsable de seguridad.

Los términos PHI e IPS se usan aquí como categorías de ingeniería, no como una determinación jurídica. PHI designa información de salud identificable; IPS, información personal sensible. La clasificación legal aplicable, las bases de licitud, los responsables y encargados de tratamiento y los plazos obligatorios permanecen abiertos en `appendices/open-questions.md`.

## Principios

- Minimización: capturar y conservar solo lo imprescindible para demostrar el flujo.
- Denegación por defecto: ninguna sesión, rol o servicio obtiene acceso por inferencia.
- Separación de privilegios: autenticación, administración, acceso clínico y procesamiento privilegiado son autoridades distintas.
- Procesamiento local primero: audio, ASR y detección de entidades no deben abandonar el dispositivo o entorno local en el flujo con información sensible.
- Sintéticos en nube: ningún proveedor cloud recibe PHI, IPS, audio, texto clínico real, tokens reversibles ni claves de reidentificación.
- Trazabilidad sin contenido: registrar quién hizo qué y cuándo, evitando copiar cuerpos clínicos a logs o auditoría.
- Borrado verificable: la eliminación incluye originales, derivados, cachés, reintentos y referencias operacionales.
- Evidencia antes que afirmaciones: un control se considera existente solo cuando hay implementación y prueba referenciables.

## Activos y clasificación

| Activo                        | Clasificación de diseño     | Ubicación prevista                                            | Regla principal                                                    |
| ----------------------------- | --------------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------ |
| Credenciales y sesión         | Secreto/IPS                 | Supabase Auth y almacenamiento seguro del cliente por definir | Nunca registrar tokens, contraseñas ni enlaces de recuperación     |
| Perfil de practitioner        | IPS                         | `practitioners`                                               | RLS; administración separada del acceso clínico                    |
| Identidad y ficha de paciente | PHI/IPS                     | `patients`                                                    | Acceso clínico explícito, mínimo y auditable                       |
| Evento clínico                | PHI                         | `clinical_events`                                             | Lectura o escritura según permiso específico; no por rol implícito |
| Audio fuente                  | PHI de máxima exposición    | Almacenamiento local temporal por definir                     | Sin nube; cifrado, TTL y borrado verificable                       |
| Transcripción                 | PHI                         | Local hasta tokenización; persistencia por decidir            | No enviar texto identificable a nube                               |
| Mapa de tokens                | Secreto de reidentificación | Almacén local separado y cifrado                              | Nunca compartir con el proveedor de síntesis                       |
| Texto tokenizado              | Sigue siendo sensible       | Local; nube solo en pruebas sintéticas                        | NER reduce exposición, no anonimiza                                |
| Resumen y caché               | PHI derivada                | Supabase/local según diseño final                             | Vincular a versión de fuente y caducar al cambiarla                |
| Auditoría y outbox            | Sensible operacional        | Postgres                                                      | Metadatos mínimos; sin payload clínico ni secretos                 |

La base actual ya contiene identificadores directos, fecha de nacimiento, ubicación y payload clínico (`supabase/migrations/20260910000000_initial_clinical_schema.sql:16-36` y `supabase/migrations/20260910110000_clinical_timeline.sql:1-5`). El enmascaramiento visual del RUT en Flutter (`app/lib/domains/patient/domain/entities/patient.dart:41-49`) no cambia la clasificación del valor almacenado ni limita lo que recibe el cliente.

## Fronteras de confianza

1. **Dispositivo móvil:** captura audio y presenta PHI. Debe asumirse comprometible; no puede actuar como autoridad de autorización.
2. **API de Supabase:** valida JWT y aplica RLS. La clave publishable identifica al cliente, pero no concede privilegios por sí sola (`app/lib/core/network/supabase_client.dart:4-15`).
3. **Postgres:** autoridad de permisos y consistencia. Las políticas deben filtrar cada operación aun cuando la UI o el repositorio fallen.
4. **Edge Functions:** frontera servidor para operaciones que necesitan secretos o composición de servicios. Deben revalidar identidad, autorización, método, esquema e idempotencia.
5. **Procesamiento local ASR/NER:** frontera que puede manejar texto identificable, pero no convierte automáticamente el resultado en anónimo.
6. **Proveedor cloud de síntesis:** frontera externa no confiable para PHI/IPS. Durante este prototipo solo recibe casos íntegramente sintéticos.
7. **Pipeline FHIR:** frontera anticorrupción; valida procedencia, perfil, versión, cardinalidad y referencia antes de persistir.
8. **Logs, CI y herramientas de desarrollo:** fronteras de exfiltración frecuentes. Solo deben contener datos sintéticos y metadatos sanitizados.

## Modelo de amenazas

| ID   | Amenaza y escenario                                            | Controles requeridos                                                             | Validación                                                                    | Riesgo residual                                   |
| ---- | -------------------------------------------------------------- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------- |
| T-01 | Usuario anónimo o suspendido consulta PHI                      | JWT, RLS de denegación por defecto, estado activo                                | pgTAP anónimo/sin perfil/suspendido                                           | Configuración incorrecta o nueva tabla sin RLS    |
| T-02 | Administración o excepción demo expone acceso clínico excesivo | Autoridades separadas, `clinical.organization.read` reservado, RLS y auditoría   | pgTAP admin sin permiso, Admin demo, copia/delegación denegada y tenant ajeno | Cambio futuro de matriz sin revisión              |
| T-03 | Cliente manipula rutas o llamadas PostgREST                    | RLS en cada tabla; UI solo como guard de experiencia                             | Pruebas directas SQL/API                                                      | Política permisiva o privilegio de tabla excesivo |
| T-04 | Service Role llega a app, repo o logs                          | Secreto solo en Edge; escaneo de secretos; cliente del caller separado           | Revisión estática y prueba de entorno                                         | Compromiso del runtime o consola del proveedor    |
| T-05 | Audio queda en temporales, backups o reintentos                | Directorio dedicado, cifrado, TTL, borrado idempotente y barrido                 | Prueba de eliminación y fault injection                                       | Recuperación forense del dispositivo              |
| T-06 | NER omite nombre, RUT o identificador indirecto                | Tratar salida como sensible; revisión de cobertura; tokens reversibles separados | Corpus adversarial y métricas por entidad                                     | Reidentificación por contexto clínico             |
| T-07 | PHI se envía al proveedor cloud                                | Bloqueo de egress para flujos reales; solo fixtures sintéticos; allowlist        | E2E con proveedor simulado y test de payload                                  | Error humano o mala clasificación del dataset     |
| T-08 | Logs capturan prompts, audio, tokens o JWT                     | Logging estructurado con allowlist y redacción en origen                         | Tests de ausencia y revisión de muestras                                      | Excepción de librería o stack trace no sanitizado |
| T-09 | Reintento duplica evento, resumen o mensaje                    | Clave de idempotencia, restricción única, outbox transaccional                   | Repetición y concurrencia                                                     | Duplicado desde fuente sin identidad estable      |
| T-10 | Caché muestra resumen obsoleto o de otro paciente              | Clave por paciente+versión+modelo; RLS; invalidación por fuente                  | Tests de aislamiento e invalidación                                           | Ventana de consistencia documentada               |
| T-11 | Recurso FHIR malformado contamina el modelo                    | Validación estricta en frontera y cuarentena                                     | Fixtures válidos/inválidos y contract tests                                   | Perfil externo ambiguo o versión no soportada     |
| T-12 | Auditoría se altera o contiene PHI                             | Append-only lógico, permisos restringidos, metadatos mínimos                     | pgTAP de escritura/lectura y revisión de esquema                              | Usuario privilegiado de base de datos             |
| T-13 | Dependencia o workflow comprometido exfiltra secretos          | Acciones fijadas por SHA, permisos mínimos, ambientes sin PHI                    | Revisión de workflow y SBOM por definir                                       | Compromiso de cadena de suministro                |

La suite capturada en el baseline demuestra parte de T-01 a T-03: cubre anónimo, sesión sin perfil, roles clínicos, administrador y suspendido (`supabase/tests/patients_rls.test.sql:29-130`). La fotografía no contiene evidencia para audio, NER, proveedor cloud, caché u outbox.

## Autenticación, autorización y RLS

RLS es la autoridad. El router impide navegación inconveniente (`app/lib/core/router/app_router.dart:16-45`), pero no constituye un control de acceso. Cada tabla expuesta debe:

- habilitar RLS antes de otorgar privilegios;
- tener políticas separadas por operación;
- usar funciones de autorización con `search_path` fijo y privilegios mínimos;
- negar a `anon`, sesiones sin perfil y cuentas suspendidas;
- probar casos permitidos y denegados con el rol real de Postgres;
- evitar que un permiso administrativo implique permiso clínico.

La implementación capturada en el baseline concede lectura clínica estática a `physician`, `nurse` y `technician` activos (`supabase/migrations/20260910100000_patient_read_access.sql:3-23`) y replica esa decisión en eventos (`supabase/migrations/20260910110000_clinical_timeline.sql:53-68`). ADR-005 y ADR-013 reemplazan esta lista por permisos configurables y asignaciones vigentes a hospitalización para Personal clínico, sin relajar la denegación por defecto. La excepción del Administrador de demo requiere `clinical.organization.read` reservado, permiso concreto, alcance, RLS y auditoría; no usa nombre/ID de rol ni Service Role y no es una política de producción. La fotografía no permite inferir qué matriz ejecuta una revisión posterior del código.

Las funciones `security definer` actuales fijan un `search_path` vacío y revocan ejecución innecesaria (`supabase/migrations/20260912000000_harden_function_privileges.sql:1-56`). Toda función nueva con elevación debe declarar propietario, roles invocantes, tablas accesibles y pruebas de abuso.

## Service Role y secretos

La Service Role Key evita RLS y por ello solo puede existir en un runtime servidor controlado. No debe incluirse en Flutter, `--dart-define`, fixtures, CI de pull requests, mensajes de error ni documentación. La Edge Function de creación usa credenciales del caller para autenticar y autorizar (`supabase/functions/create-practitioner/index.ts:26-45`) y un cliente separado con Service Role para la operación administrativa (`supabase/functions/create-practitioner/index.ts:74-95`). Ese patrón es evidencia de diseño, no prueba de aislamiento productivo.

Requisitos adicionales para cualquier función privilegiada:

- fallar al iniciar si falta una variable requerida, sin imprimir su valor;
- aceptar solo métodos y content types esperados;
- validar el cuerpo con una allowlist y límites de tamaño;
- propagar un identificador de correlación no sensible;
- aplicar autorización de negocio antes de crear el cliente privilegiado;
- hacer compensación explícita o usar una transacción/outbox cuando haya varios efectos;
- no devolver detalles internos del proveedor.

El rollback de creación de usuario actual puede fallar y solo emite un marcador (`supabase/functions/create-practitioner/index.ts:96-101`); debe considerarse riesgo operativo, no atomicidad garantizada.

## Audio, ASR, NER y síntesis

### Audio

La captura requiere consentimiento o base autorizante definida, indicador visible, duración y tamaño máximos, interrupción segura y una identidad de sesión. El archivo se escribe en almacenamiento privado local, con nombre aleatorio, sin datos del paciente en nombre o metadatos. No se sincroniza con galerías, backups o telemetría. ADR-006 y ADR-010 gobiernan el flujo y su eliminación.

### ASR local

El reconocimiento ocurre localmente conforme a ADR-007. Modelo, checksum, idioma, versión y parámetros forman parte de la procedencia. Un resultado ASR es borrador: debe distinguir incertidumbre, no inventar texto y permitir revisión humana. La ausencia de red no puede activar una caída automática a nube.

### NER y tokenización reversible

NER no anonimiza. Puede omitir entidades, conservar cuasi-identificadores y permitir reidentificación por contexto. El texto tokenizado conserva clasificación sensible. Conforme a ADR-008:

- cada entidad detectada se sustituye por un token opaco estable dentro del documento;
- el mapa token→valor se cifra y almacena separado del texto;
- el acceso al mapa exige permiso explícito y se audita;
- la reversión solo ocurre localmente en el flujo autorizado;
- logs, métricas y errores nunca incluyen valor original ni mapa;
- se prueban falsos negativos, solapamientos, Unicode, fechas, direcciones, RUT y referencias indirectas.

### Síntesis cloud

ADR-009 define una interfaz de proveedor para evitar acoplar dominio y payloads. Durante el prototipo, la integración cloud solo procesa escenarios completamente sintéticos y etiquetados como tales. La tokenización de un caso real no habilita su envío. Debe existir un guard técnico que rechace datasets sin procedencia sintética, además de la norma documental.

## Retención y eliminación

La política objetivo es minimizar, no archivar por defecto. Antes de implementar audio se deben resolver los plazos exactos de `Q-PRIV-03`; mientras permanezcan abiertos, ningún dato real puede entrar al flujo.

Una solicitud o vencimiento debe marcar el artefacto, impedir nuevas lecturas y ejecutar una eliminación idempotente de:

- archivo de audio y fragmentos temporales;
- buffers, waveform y cachés del dispositivo;
- transcripción y resultados intermedios que no deban persistir;
- mapa reversible cuando ya no exista finalidad autorizada;
- trabajos pendientes y referencias de outbox que puedan reconstruir contenido;
- copias del proveedor, si alguna integración futura fuese autorizada;
- cachés de resumen derivadas cuando corresponda.

La auditoría conserva el hecho de la eliminación, identificadores opacos, actor, razón y resultado, no el contenido eliminado. Backups, recuperación y dispositivos perdidos requieren políticas institucionales antes de alegar borrado completo.

## Logs, auditoría y outbox

### Logs operacionales

Usar eventos estructurados y allowlist. Campos admisibles: timestamp, nivel, código estable, componente, versión, duración, resultado, correlation ID y actor pseudónimo cuando sea imprescindible. Campos prohibidos: JWT, cookies, email, RUT, nombre, fecha de nacimiento, ubicación clínica, texto libre, prompt, respuesta del modelo, audio, URL firmada, mapa de tokens y Service Role.

Los mensajes de error deben usar códigos estables como ya hace parcialmente `create-practitioner` (`supabase/functions/create-practitioner/index.ts:14-23`), pero `console.error` y stack traces también deben pasar por sanitización.

### Auditoría

Auditar eventos de seguridad y negocio relevantes: login y recuperación sin secreto, cambio de estado/rol/permiso, lectura o exportación sensible si el alcance lo exige, captura y borrado de audio, reversión de tokens, solicitud de síntesis, regeneración de resumen y fallo de outbox. La fase 2.2 implementa solo el subset de concesión/revocación de asignaciones: tenant, timestamp, actor derivado, acción, objetivo, resultado, idempotency key y metadata JSONB sanitizada. `audit.read` está protegido por RLS; no hay DML runtime directo y la bitácora es append-only. Separar auditoría de depuración. Definir quién puede consultar y cuánto se conserva antes de producción.

### Outbox transaccional

Cuando una mutación de base de datos deba producir auditoría o integración, escribir el cambio y un registro outbox en la misma transacción. Un worker reclama con bloqueo, publica de forma idempotente y registra intento, resultado y próximo retry. El payload contiene referencias mínimas, no copias clínicas. Una dead-letter queue necesita acceso restringido, TTL y procedimiento de recuperación. El outbox mejora entrega; no equivale por sí solo a exactly-once.

## Respuesta a incidentes del prototipo

1. Detener el flujo afectado y preservar solo evidencia no sensible.
2. Revocar sesiones y rotar credenciales expuestas; si hay Service Role, tratar el proyecto como comprometido.
3. Identificar alcance por auditoría y correlation IDs, sin ampliar la exposición mediante exports.
4. Si datos reales entraron al entorno local, detener el trabajo, purgar volúmenes, exportaciones y logs, y rotar cualquier credencial no local expuesta (`AGENTS.md:26`).
5. Documentar causa, ventana, activos, corrección y prueba de regresión.
6. Escalar según el proceso institucional y legal que aún debe definirse.

## Puerta previa a datos reales o producción

No se habilitan datos reales ni se afirma cumplimiento productivo hasta contar con evidencia aprobada de:

- inventario y diagramas de flujo de datos actualizados;
- base jurídica, consentimiento cuando aplique y evaluación de impacto;
- RLS y privilegios probados para toda tabla, vista, bucket y RPC;
- secretos gestionados, rotación, ambientes aislados y backups probados;
- cifrado en tránsito y reposo, almacenamiento seguro móvil y borrado remoto definidos;
- retención y eliminación extremo a extremo verificadas;
- proveedor, residencia, subprocesadores y contratos aprobados;
- monitoreo, auditoría, respuesta a incidentes y recuperación operacional;
- pruebas de seguridad, privacidad, carga y resiliencia independientes;
- revisión clínica de riesgos de ASR, NER y síntesis;
- resolución de las preguntas bloqueantes del apéndice.

## Evidencia relacionada

- Decisiones: [ADR-003](decisions/adr-003-supabase.md), [ADR-005](decisions/adr-005-permisos-configurables.md), [ADR-013](decisions/adr-013-acceso-clinico-por-asignacion.md), [ADR-007](decisions/adr-007-asr-local.md), [ADR-008](decisions/adr-008-ner-tokenizacion-reversible.md), [ADR-009](decisions/adr-009-sintesis-cloud-proveedor-abstracto.md), [ADR-010](decisions/adr-010-retencion-eliminacion-audio.md) y [ADR-011](decisions/adr-011-resumen-temporal-cache.md).
- Catálogo de fuentes: [Índice de evidencia](appendices/evidence-index.md).
- Seguimiento: [Registro de riesgos](appendices/risk-register.md) y [Preguntas abiertas](appendices/open-questions.md).
  La evidencia del gate local 5.2 ejercita alta Edge 201, replay 200, conflicto 409, caller clínico denegado y Service Role denegada como identidad llamante; en el harness local la Service Role se limita a consultas de verificación read-only de Auth y de filas IAM relacionadas, nunca actúa como caller. La integración usa reset completo del proyecto sintético desechable, sin borrar auditoría manualmente. Los metadatos administrativos de auditoría contienen solo campos de firma de operación (UUID opacos, estado/vigencia y códigos de permiso); excluyen nombres, email, JWT y payload clínico. El advisory lock por organización serializa transiciones protegidas del Administrador, incluida suspensión y revocación de grants. La concurrencia en dos sesiones no se probó; no afirmar esa garantía empíricamente validada.
