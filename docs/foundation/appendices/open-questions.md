# Preguntas abiertas

## Uso

Una pregunta abierta registra una decisión faltante, no una autorización provisional. Las marcadas **Bloqueante** impiden iniciar el corte o usar datos reales. “Momento de resolución” identifica el gate; no es una fecha comprometida.

## Decisiones ya cerradas

Las siguientes preguntas se resolvieron durante la fundación y no se mantienen como bloqueantes:

| Tema                    | Decisión                                                                                                                                                                                                  |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modelo de permisos      | Roles por organización sobre catálogo fijo; Personal clínico requiere permiso concreto y asignación asistencial vigente; Admin demo usa permiso reservado y RLS.                                          |
| Excepción Administrador | `clinical.organization.read` reservado solo para el rol seed protegido; RLS evalúa permiso, alcance y tenant, no nombre/ID; no es copiable ni delegable.                                                  |
| Episodios y traslados   | Alta conserva lectura histórica con asignación vigente; cancelación/invalidación deniega; corrección no hereda; traslado mantiene la asignación y la unidad no restringe Personal clínico en demo.        |
| Bootstrap y migración   | Bootstrap crea Administrador sintético; la operación autorizada mantiene al menos uno; cuentas `administrator`, `physician`, `nurse` y `technician` preexistentes tienen tratamiento de upgrade definido. |
| Versión y recursos FHIR | FHIR R4; ocho recursos de dominio y tres de infraestructura definidos en `06-fhir-integration.md`.                                                                                                        |
| Zona horaria            | Instantes UTC y presentación mediante timezone IANA de la organización; se conserva offset/precisión de origen cuando exista.                                                                             |
| Reversión NER           | La realiza localmente el mismo autor; mapa y valores nunca llegan al proveedor.                                                                                                                           |
| Síntesis de nota        | Ordena y reduce texto sin inventar hechos; el mismo autor escucha audio, edita síntesis y confirma.                                                                                                       |
| Outbox inicial          | Notas textuales/de audio y solicitudes de síntesis pendientes; solo contenido tokenizado cruza la red.                                                                                                    |
| Turnos                  | Scheduling, RRHH y handoff formal quedan fuera; el resumen usa intervalos explícitos.                                                                                                                     |

## Privacidad, legal y gobernanza

| ID        | Pregunta                                                                                                   | Prioridad  | Responsable a confirmar | Momento de resolución                  |
| --------- | ---------------------------------------------------------------------------------------------------------- | ---------- | ----------------------- | -------------------------------------- |
| Q-PRIV-01 | ¿Qué marco jurídico, roles de tratamiento y base de licitud aplicarían a una eventual prueba con personas? | Bloqueante | Institución/legal       | Antes de cualquier dato real           |
| Q-PRIV-02 | ¿Qué consentimiento o información debe mostrarse para capturar voz propia y de terceros?                   | Bloqueante | Legal/ética/UX          | Antes de V3 con participantes          |
| Q-PRIV-03 | ¿Cuál es el TTL exacto de audio, transcripción, mapa y resumen, y desde qué evento se cuenta?              | Bloqueante | Privacidad/producto     | Antes de ADR-010 implementada          |
| Q-PRIV-04 | ¿Cómo se tratan backups, dispositivos perdidos, reinstalación y borrado remoto?                            | Alta       | Seguridad/móvil         | Antes de datos reales                  |
| Q-PRIV-05 | ¿Qué eventos requieren auditoría y quién puede consultarlos?                                               | Alta       | Seguridad/institución   | Antes de V7                            |
| Q-PRIV-06 | ¿Qué residencia, subprocesadores y no-retención exigiría un proveedor futuro?                              | Bloqueante | Legal/seguridad         | Antes de cambiar restricción sintética |

## Autorización y datos

| ID        | Pregunta                                                                                       | Prioridad  | Responsable a confirmar   | Momento de resolución                                                                                                                                                                                                               |
| --------- | ---------------------------------------------------------------------------------------------- | ---------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Q-AUTH-02 | ¿Cómo se invalida una sesión/caché de autorización tras revocación?                            | Alta       | Backend/seguridad         | Resuelta en 4.4: providers autoDispose, sin caché persistente, invalidación en entrada/resume/cambio de organización y reconsulta; revocación remota se refleja en la siguiente consulta, sin push. Gates 4.5/5.2 cerrados en demo. |
| Q-DATA-01 | ¿Qué perfiles o Implementation Guides concretos restringen los recursos FHIR R4 seleccionados? | Alta       | Interoperabilidad         | Inicio de V1                                                                                                                                                                                                                        |
| Q-DATA-02 | ¿Qué sistema identifica pacientes y cómo se resuelven duplicados/conflictos?                   | Bloqueante | Datos/clínica             | Diseño de mapping V1                                                                                                                                                                                                                |
| Q-DATA-04 | ¿Qué pérdidas de mapping FHIR son aceptables y quién las aprueba?                              | Alta       | Clínica/interoperabilidad | Criterio de salida V1                                                                                                                                                                                                               |

## Audio, modelos y síntesis

Las preguntas de motor, modelo, procedencia y egreso están resueltas en el corte del 2026-10-12 (ADR-016 y ADR-017) y se detallan en "Preguntas resueltas" más abajo. Solo `Q-NER-01` sigue abierta: depende del spike SP-02 y de la taxonomía de identificadores.

| ID       | Pregunta                                                           | Prioridad  | Responsable a confirmar  | Momento de resolución |
| -------- | ------------------------------------------------------------------ | ---------- | ------------------------ | --------------------- |
| Q-NER-01 | ¿Qué taxonomía de identificadores y umbral por clase se requieren? | Bloqueante | Privacidad/investigación | SP-02                 |

## Preguntas resueltas en el corte ASR/síntesis local (2026-10-12)

La evidencia de código de este corte se completa en `docs/foundation/appendices/evidence-index.md` cuando la implementación correspondiente exista; mientras tanto, la evidencia normativa es la ADR indicada.

| ID         | Decisión                                                                                                                                                                                                                                        | Responsable           | Fecha      | Evidencia                     |
| ---------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------- | ---------- | ----------------------------- |
| Q-ASR-01   | Objetivo Android arm64 e iOS, español (Chile) sobre corpus sintético. Presupuesto: factor de tiempo real por debajo de 1,0 en el dispositivo de referencia, RAM de pico bajo 1,5 GB, batería y temperatura registradas sin umbral comprometido. | Móvil/investigación   | 2026-10-12 | ADR-016; `09-audio-ai-ner.md` |
| Q-ASR-02   | Motor `sherpa_onnx` 1.13.8 (Apache-2.0) con modelo español de licencia verificada, distribuido con versión y checksum en manifiesto versionado; los pesos no se commitean.                                                                      | Investigación/legal   | 2026-10-12 | ADR-016                       |
| Q-NER-02   | Sin objeto: con ADR-017 no hay mapa token-valor que cifrar porque nada sale del dispositivo. Los artefactos de dictado usan el almacenamiento seguro de la plataforma y se purgan al confirmar, descartar o expirar.                            | Seguridad/móvil       | 2026-10-12 | ADR-017                       |
| Q-AI-01    | Salida estructurada cuando el modelo la soporte; límites por caso de uso (hito hasta 20000 caracteres, resumen de periodo por intervalo) y códigos de error estables en el puerto `SynthesisProvider`.                                          | Clínica/investigación | 2026-10-12 | ADR-017                       |
| Q-AI-02    | Sin proveedor cloud. Runtime local `llamadart` (llama.cpp) con modelo GGUF de redacción, descarga explícita con progreso y timeout/cancelación controlados por el caso de uso.                                                                  | Investigación/backend | 2026-10-12 | ADR-017                       |
| Q-AI-03    | Deja de ser bloqueante: no hay egreso que verificar en runtime. La garantía es la ausencia de transmisión de texto, comprobable por inspección de red y por la prueba de privacidad de pgTAP.                                                   | Seguridad/backend     | 2026-10-12 | ADR-017                       |
| Q-AUDIO-01 | Sin objeto: no se persiste audio crudo, ni en bucket ni en columna. No hay retención remota que gobernar y RK-028 queda retirado. El audio local existe solo hasta confirmar, descartar o expirar.                                              | Privacidad/producto   | 2026-10-12 | ADR-016                       |

## Operación y alcance

| ID         | Pregunta                                                              | Prioridad | Responsable a confirmar | Momento de resolución |
| ---------- | --------------------------------------------------------------------- | --------- | ----------------------- | --------------------- |
| Q-OPS-02   | ¿Qué política de retry, dead-letter y alerta aplica por operación?    | Alta      | Backend/operación       | Diseño de V7          |
| Q-OPS-03   | ¿Dónde se almacenan resultados de benchmarks y por cuánto tiempo?     | Media     | Investigación           | Antes de SP-01        |
| Q-SCOPE-02 | ¿Qué evidencia exacta exige la evaluación académica y en qué formato? | Alta      | Sponsor/investigación   | Antes de V8           |

El harness `integration:local` restaura baseline antes y en `finally` después, usando únicamente el Supabase local desechable; el reset elimina también su historia/auditoría sintética y no se borran filas manualmente. La prueba concurrente de último Administrador en dos sesiones sigue abierta: los tests pgTAP prueban el contrato sin forzar una carrera real. No se presenta la garantía como evidencia concurrente.

## Regla de cierre

Cerrar una pregunta exige registrar decisión, responsable, fecha y evidencia en una ADR existente/nueva o en el capítulo correspondiente. Una respuesta informal no cambia el alcance. Si la respuesta contradice una ADR, se crea una ADR sustitutiva.
