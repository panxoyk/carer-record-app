# Roadmap de entrega vertical

## Enfoque

El roadmap organiza trabajo en cortes verticales demostrables, no en capas técnicas aisladas. Cada corte incorpora autorización, datos, procesamiento, interfaz mínima, observabilidad, pruebas y documentación necesarias para un flujo extremo a extremo. No asigna fechas ni promete despliegue productivo.

La fotografía previa a esta fundación registra un MVP local con autenticación, administración y timeline clínico de solo lectura (`baseline/carer-record-app.md:9-13`). El pipeline ejecutable informa que la ingesta FHIR está diferida (`scripts/data_pipeline/main.py:9-15`). Todo corte posterior se considera **propuesto** hasta que su criterio de salida tenga evidencia en el repositorio.

## Reglas de avance

- No comenzar un corte que use PHI/IPS real; el prototipo opera con sintéticos.
- Resolver decisiones bloqueantes antes de persistir nuevas categorías de datos.
- Implementar primero autorización y constraints, luego repositorios/servicios y finalmente UI.
- Una demo no equivale a terminado: deben pasar pruebas de denegación, fallo, retry y cleanup.
- Cada corte actualiza trazabilidad, riesgos, preguntas y evidencia.
- Evitar infraestructura anticipada: outbox, caché o proveedor se incorporan cuando el corte los necesita.
- Los turnos quedan fuera de alcance conforme a ADR-012.

## Estado y secuencia

| Corte | Resultado demostrable                                       | Estado documental        | Dependencias        |
| ----- | ----------------------------------------------------------- | ------------------------ | ------------------- |
| V0    | Baseline local reproducible y límites declarados            | Parcialmente evidenciado | Ninguna             |
| V1    | FHIR sintético validado llega a timeline                    | Propuesto                | V0, ADR-004         |
| V2    | Permiso configurable gobierna lectura                       | Propuesto                | V1, ADR-005         |
| V3    | Audio sintético se captura, transcribe localmente y elimina | Propuesto                | V0, ADR-006/007/010 |
| V4    | Texto sintético se tokeniza y revierte localmente           | Propuesto                | V3, ADR-008         |
| V5    | Síntesis cloud procesa solo texto sintético permitido       | Propuesto                | V4, ADR-009         |
| V6    | Resumen temporal versionado usa caché segura                | Propuesto                | V1, V5, ADR-011     |
| V7    | Eliminación, auditoría y outbox resisten fallos             | Propuesto                | V2-V6               |
| V8    | Evaluación académica reproducible y cierre de brechas       | Propuesto                | V1-V7               |

V1 y V3 pueden explorarse en paralelo mediante spikes, pero no compartir contratos inestables. V5 permanece bloqueado hasta demostrar técnicamente que el flujo cloud solo acepta procedencia sintética.

## V0 - Baseline y guardrails

**Valor:** una persona evaluadora puede levantar el entorno y observar los límites del prototipo sin asumir capacidades inexistentes.

**Alcance:** reproducibilidad local, seed sintético, autenticación, roles del baseline, lectura clínica, CI y documentación de decisiones. La fotografía registra consumo de clave publishable (`app/lib/core/network/supabase_client.dart:4-15`), RLS en tablas clínicas (`supabase/migrations/20260910000000_initial_clinical_schema.sql:41-47`) y pruebas que restringen la matriz (`supabase/tests/patients_rls.test.sql:29-169`).

**Criterios de salida:**

- setup local y CI pasan desde un checkout limpio;
- las limitaciones académicas y de datos sintéticos son visibles;
- ADR-001 a ADR-012 y apéndices están enlazados;
- no hay secretos ni datos reales versionados;
- riesgos P0 tienen tratamiento o bloqueo explícito.

## V1 - Frontera FHIR a timeline

**Valor:** un Bundle o conjunto mínimo de recursos FHIR sintéticos soportados produce pacientes y eventos internos consultables.

**Incluye:** versión/perfiles explícitos, fixtures, validación, mapping, procedencia, identidad externa, upsert idempotente, cuarentena y visualización del resultado. La frontera impide que tipos FHIR atraviesen el dominio móvil.

**Entidades:** `Patient`, `ClinicalEvent` existentes; se proponen `IngestionRun`, `SourceResource` y `MappingError` solo si el corte demuestra necesitarlos.

**Pruebas:** mappings válidos e inválidos, referencias fuera de orden, timestamps, replay, actualización y E2E F-04→F-03.

**Criterio de salida:** reingerir el mismo fixture no duplica; un recurso inválido no modifica parcialmente el timeline; la matriz de mapping y pérdidas está documentada.

## V2 - Permisos configurables

**Valor:** una persona administradora autorizada modifica una asignación de permiso y RLS refleja la decisión sin despliegue SQL.

**Incluye:** catálogo cerrado de permisos, grants por sujeto o rol, estado/vigencia si se aprueba, administración mínima y auditoría. La matriz estática del baseline (`supabase/migrations/20260910100000_patient_read_access.sql:10-16`) se migra de forma aditiva.

**Entidades:** `organizations`, `units`, `profiles`, `organization_memberships`, `roles`, `permission_catalog`, `role_permissions` y `role_assignments`, con alcance inicial de organización o unidad. La asignación individual de hospitalizaciones queda preparada, pero no integra el flujo inicial.

**Pruebas:** pgTAP de grant/revoke/suspensión/administrador/sin perfil, concurrencia e invalidación de sesión según contrato.

**Criterio de salida:** denegación por defecto permanece; ninguna edición de UI agrega autoridad; todas las combinaciones soportadas tienen casos positivos y negativos.

## V3 - Captura y ASR local con borrado

**Valor:** con audio estrictamente sintético, una persona captura una muestra, obtiene una transcripción técnica local verificable y elimina el artefacto; la experiencia final de usuario revisará audio y síntesis en V5.

**Incluye:** permiso de micrófono, consentimiento/indicador, límites, archivo privado temporal, motor ASR local detrás de interfaz, procedencia del modelo, estados y borrado idempotente. No incluye nube ni persistencia clínica.

**Entidades locales:** `RecordingSession`, `AudioArtifact`, `TranscriptDraft`; no se crean tablas remotas salvo decisión posterior.

**Pruebas:** SP-01, permisos, interrupciones, crash/restart, espacio insuficiente, checksum de modelo y ausencia de tráfico de audio.

**Criterio de salida:** el dispositivo objetivo cumple presupuesto académico documentado; no existe fallback cloud; una operación de borrado repetida deja cero artefactos observables dentro del alcance probado.

## V4 - NER y tokenización reversible

**Valor:** una transcripción sintética se transforma en texto tokenizado, muestra las entidades detectadas y puede revertirse solo localmente por un actor autorizado.

**Incluye:** taxonomía, offsets, token estable por documento, mapa cifrado separado, formato versionado, revisión humana y métricas. NER no se presenta como anonimización.

**Entidades:** `DetectedEntity`, `TokenizedDocument`, `TokenMap`; persistencia final sujeta a threat model.

**Pruebas:** SP-02/SP-03, solapamientos, Unicode, falsos negativos críticos, manipulación de token, claves ausentes y autorización de reversión.

**Criterio de salida:** round-trip determinista para el formato soportado, mapa ausente de logs y proveedor, limitaciones visibles y corpus íntegramente sintético.

## V5 - Síntesis cloud con proveedor abstracto

**Valor:** un escenario sintético produce una síntesis mediante un contrato sustituible, con fake para pruebas y un adaptador cloud en sandbox para la demostración.

**Incluye:** `SynthesisProvider`, request/response internos, adapter, timeout, cancelación, errores estables, presupuesto, idempotencia y guard de procedencia sintética.

**No incluye:** PHI/IPS real, texto clínico tokenizado proveniente de una persona real, audio ni mapa de tokens.

**Pruebas:** fake contractual, adapter sandbox con fixtures sintéticos, rechazo de procedencia desconocida/no sintética, sanitización de logs y fallo del proveedor.

**Criterio de salida:** dominio no importa SDK/tipos del proveedor; cambiar fake por adapter no cambia el caso de uso; el guard bloquea técnicamente payloads no sintéticos.

## V6 - Resumen temporal y caché

**Valor:** la persona consulta un resumen sintético de una ventana temporal y una segunda lectura reutiliza solo una entrada exactamente vigente.

**Incluye:** rango `[desde, hasta)`, zona horaria, conjunto/versiones fuente, modelo/prompt/provider version, estado, expiración e invalidación. La respuesta indica procedencia, ventana y que no sustituye la ficha.

**Entidades:** `SummaryRequest`, `SummarySnapshot` y `SummaryCacheEntry`, que pueden consolidarse si no compromete auditoría.

**Pruebas:** bordes temporales, zona horaria, hit/miss, cambio de fuente, aislamiento RLS, concurrencia, timeout y respuesta vacía.

**Criterio de salida:** una mutación o nueva versión fuente invalida el resultado; jamás se devuelve caché de otro paciente/ventana/modelo; el stub 501 observado en el baseline (`supabase/functions/clinical-summary/index.ts:3-19`) se reemplaza con tests.

## V7 - Ciclo operacional: outbox, auditoría y eliminación

**Valor:** los efectos críticos son trazables y recuperables sin conservar contenido innecesario.

**Incluye:** eventos de auditoría mínimos, outbox transaccional, worker idempotente, retries, dead-letter, barrido de retención y evidencia de borrado. Se aplica primero a un flujo crítico y luego se extiende.

**Pruebas:** crash entre commit y publicación, workers concurrentes, replay, poison message, TTL, autorización de auditoría y ausencia de PHI en payload/log.

**Criterio de salida:** una demo de fault injection recupera el efecto sin duplicarlo; cada eliminación registra resultado sin contenido; existe runbook académico de recuperación.

## V8 - Evaluación y cierre académico

**Valor:** resultados y límites son reproducibles y auditables por la evaluación, sin presentarse como validación productiva.

**Incluye:** protocolo, hardware, versiones, corpus sintético, métricas, resultados negativos, amenazas a validez, demos E2E y backlog de producción separado.

**Criterios de salida:**

- trazabilidad RQ→ADR→flujo→entidad→prueba completa para el alcance implementado;
- riesgos residuales y preguntas sin resolver explícitos;
- resultados de spikes reproducibles;
- ninguna afirmación excede la evidencia;
- turnos y capacidades productivas siguen identificados fuera de alcance.

## Trabajo explícitamente no incluido

- gestión de turnos, calendario, asistencia o handoff operativo;
- recomendación, diagnóstico o decisión clínica automatizada;
- soporte FHIR universal;
- datos reales, despliegue productivo, SLA, alta disponibilidad o disaster recovery;
- certificación regulatoria, legal, de seguridad o eficacia clínica;
- analítica secundaria, entrenamiento de modelos o reutilización de datos.

Estos límites derivan de [ADR-002](decisions/adr-002-prototipo-academico.md) y [ADR-012](decisions/adr-012-turnos-fuera-de-alcance.md).

## Control de entrega

Cada corte debe añadir una fila o actualizar estado en [requirements-traceability.md](appendices/requirements-traceability.md), registrar evidencia en [evidence-index.md](appendices/evidence-index.md), cerrar o reformular preguntas y revisar [risk-register.md](appendices/risk-register.md). La etiqueta **implementado** solo se usa cuando código y pruebas existen; **validado** requiere además que los criterios del corte se hayan ejecutado en el entorno declarado.
