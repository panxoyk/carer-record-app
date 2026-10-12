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

| ID       | Pregunta                                                                                        | Prioridad  | Responsable a confirmar  | Momento de resolución |
| -------- | ----------------------------------------------------------------------------------------------- | ---------- | ------------------------ | --------------------- |
| Q-ASR-01 | ¿Qué dispositivos, SO, idioma/acentos y presupuesto de latencia/RAM/batería son objetivo?       | Bloqueante | Móvil/investigación      | SP-01                 |
| Q-ASR-02 | ¿Qué motor/modelo y licencia permiten distribución académica?                                   | Bloqueante | Investigación/legal      | SP-01                 |
| Q-NER-01 | ¿Qué taxonomía de identificadores y umbral por clase se requieren?                              | Bloqueante | Privacidad/investigación | SP-02                 |
| Q-NER-02 | ¿Dónde y con qué mecanismo se cifra el mapa reversible?                                         | Bloqueante | Seguridad/móvil          | Diseño de V4          |
| Q-AI-01  | ¿Qué esquema estructurado de salida y límites de longitud se usarán para cada tipo de síntesis? | Alta       | Clínica/investigación    | Antes de V5           |
| Q-AI-02  | ¿Qué proveedor/modelo sandbox se evaluará y con qué límites de costo/timeout?                   | Media      | Investigación/backend    | SP-05                 |
| Q-AI-03  | ¿Cómo se prueba de forma no falsificable la procedencia sintética en runtime?                   | Bloqueante | Seguridad/backend        | Antes de V5           |

## Operación y alcance

| ID         | Pregunta                                                              | Prioridad | Responsable a confirmar | Momento de resolución |
| ---------- | --------------------------------------------------------------------- | --------- | ----------------------- | --------------------- |
| Q-OPS-02   | ¿Qué política de retry, dead-letter y alerta aplica por operación?    | Alta      | Backend/operación       | Diseño de V7          |
| Q-OPS-03   | ¿Dónde se almacenan resultados de benchmarks y por cuánto tiempo?     | Media     | Investigación           | Antes de SP-01        |
| Q-SCOPE-02 | ¿Qué evidencia exacta exige la evaluación académica y en qué formato? | Alta      | Sponsor/investigación   | Antes de V8           |

El harness `integration:local` restaura baseline antes y en `finally` después, usando únicamente el Supabase local desechable; el reset elimina también su historia/auditoría sintética y no se borran filas manualmente. La prueba concurrente de último Administrador en dos sesiones sigue abierta: los tests pgTAP prueban el contrato sin forzar una carrera real. No se presenta la garantía como evidencia concurrente.

## Regla de cierre

Cerrar una pregunta exige registrar decisión, responsable, fecha y evidencia en una ADR existente/nueva o en el capítulo correspondiente. Una respuesta informal no cambia el alcance. Si la respuesta contradice una ADR, se crea una ADR sustitutiva.
