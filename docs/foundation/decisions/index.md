# Índice de decisiones de arquitectura

## Convenciones

- **Aceptada:** decisión vigente para el alcance indicado; no implica que esté implementada.
- **Propuesta:** requiere resolver preguntas o validar factibilidad antes de comprometer implementación.
- **Implementación:** se informa por separado porque una ADR aceptada puede describir arquitectura objetivo.
- **Sustituida:** otra ADR reemplaza la decisión y debe enlazarse desde ambas.

Ninguna ADR de esta carpeta acredita cumplimiento productivo. La evidencia de estado se mantiene en [evidence-index.md](../appendices/evidence-index.md).

## Registro

| ADR                                                      | Decisión                                      | Estado                                    | Implementación observada                |
| -------------------------------------------------------- | --------------------------------------------- | ----------------------------------------- | --------------------------------------- |
| [ADR-001](adr-001-repositorio-canonico.md)               | Repositorio canónico                          | Aceptada                                  | Sí, para código e infraestructura local |
| [ADR-002](adr-002-prototipo-academico.md)                | Prototipo académico                           | Aceptada                                  | Sí, alcance parcial                     |
| [ADR-003](adr-003-supabase.md)                           | Supabase como backend versionado              | Aceptada                                  | Sí, alcance actual                      |
| [ADR-004](adr-004-fhir-frontera.md)                      | FHIR como frontera anticorrupción             | Aceptada                                  | No; solo scaffold                       |
| [ADR-005](adr-005-permisos-configurables.md)             | Permisos configurables                        | Aceptada                                  | Sí, demo sintética/local                |
| [ADR-013](adr-013-acceso-clinico-por-asignacion.md)      | Acceso clínico por asignación                 | Aceptada                                  | Sí, demo sintética/local                |
| [ADR-014](adr-014-delegacion-gestion-asignaciones.md)    | Delegación de gestión de asignaciones         | Aceptada                                  | Sí, demo sintética/local                |
| [ADR-015](adr-015-hitos-bitora-audio.md)                 | Hitos de bitácora en texto o audio almacenado | Aceptada                                  | Sí, demo sintética/local                |
| [ADR-006](adr-006-audio.md)                              | Captura de audio local y explícita            | Aceptada, en parte sustituida por ADR-015 | No (flujo experimental)                 |
| [ADR-007](adr-007-asr-local.md)                          | ASR local                                     | Aceptada                                  | No                                      |
| [ADR-008](adr-008-ner-tokenizacion-reversible.md)        | NER y tokenización reversible                 | Aceptada                                  | No                                      |
| [ADR-009](adr-009-sintesis-cloud-proveedor-abstracto.md) | Síntesis cloud tras proveedor abstracto       | Aceptada con restricción                  | Stub sin proveedor                      |
| [ADR-010](adr-010-retencion-eliminacion-audio.md)        | Retención mínima y eliminación de audio       | Aceptada, en parte sustituida por ADR-015 | No (flujo experimental)                 |
| [ADR-011](adr-011-resumen-temporal-cache.md)             | Resumen temporal versionado y caché           | Aceptada                                  | Stub sin implementación                 |
| [ADR-012](adr-012-turnos-fuera-de-alcance.md)            | Turnos fuera de alcance                       | Aceptada                                  | No se observa dominio de turnos         |

## Regla de cambio

Una decisión se modifica con una ADR nueva que la sustituya, no reescribiendo silenciosamente sus consecuencias. Correcciones editoriales o enlaces de evidencia pueden actualizarse sin nueva ADR. Todo cambio debe revisar seguridad, pruebas, roadmap, trazabilidad, preguntas y riesgos relacionados.
