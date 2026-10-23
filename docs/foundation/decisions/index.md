# Índice de decisiones de arquitectura

## Convenciones

- **Aceptada:** decisión vigente para el alcance indicado; no implica que esté implementada.
- **Propuesta:** requiere resolver preguntas o validar factibilidad antes de comprometer implementación.
- **Implementación:** se informa por separado porque una ADR aceptada puede describir arquitectura objetivo.
- **Sustituida:** otra ADR reemplaza la decisión y debe enlazarse desde ambas.

Ninguna ADR de esta carpeta acredita cumplimiento productivo. La evidencia de estado se mantiene en [evidence-index.md](../appendices/evidence-index.md).

## Registro

| ADR                                                      | Decisión                                                      | Estado                                    | Implementación observada                                                        |
| -------------------------------------------------------- | ------------------------------------------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------- |
| [ADR-001](adr-001-repositorio-canonico.md)               | Repositorio canónico                                          | Aceptada                                  | Sí, para código e infraestructura local                                         |
| [ADR-002](adr-002-prototipo-academico.md)                | Prototipo académico                                           | Aceptada                                  | Sí, alcance parcial                                                             |
| [ADR-003](adr-003-supabase.md)                           | Supabase como backend versionado                              | Aceptada                                  | Sí, alcance actual                                                              |
| [ADR-004](adr-004-fhir-frontera.md)                      | FHIR como frontera anticorrupción                             | Aceptada, en parte sustituida por ADR-019 | Parcial: cliente y mapper en la app (ADR-019); la ingesta sigue siendo scaffold |
| [ADR-005](adr-005-permisos-configurables.md)             | Permisos configurables                                        | Aceptada                                  | Sí, demo sintética/local                                                        |
| [ADR-013](adr-013-acceso-clinico-por-asignacion.md)      | Acceso clínico por asignación                                 | Aceptada                                  | Sí, demo sintética/local                                                        |
| [ADR-014](adr-014-delegacion-gestion-asignaciones.md)    | Delegación de gestión de asignaciones                         | Aceptada                                  | Sí, demo sintética/local                                                        |
| [ADR-015](adr-015-hitos-bitora-audio.md)                 | Hitos de bitácora en texto o audio almacenado                 | Aceptada, en parte sustituida por ADR-016 | Sí, demo sintética/local                                                        |
| [ADR-016](adr-016-asr-local-transcripcion-confirmada.md) | ASR local y transcripción confirmada                          | Aceptada                                  | Sí, demo sintética/local                                                        |
| [ADR-017](adr-017-sintesis-local.md)                     | Síntesis local con modelo en el dispositivo                   | Aceptada                                  | Sí, demo sintética/local                                                        |
| [ADR-018](adr-018-modulo-ia-local-compartido.md)         | Módulo compartido de IA en el dispositivo                     | Aceptada                                  | Sí, organización técnica                                                        |
| [ADR-019](adr-019-lectura-fhir-directa-desde-la-app.md)  | Lectura directa de FHIR desde la app y bitácora enlazada      | Sustituida por ADR-020                    | Histórica; bypass móvil retirado, conservar para contexto                       |
| [ADR-020](adr-020-fhir-server-structural-sync.md)        | Sincronización FHIR estructural y consulta clínica autorizada | Aceptada                                  | Corte mínimo implementado; ver estado y evidencia en ADR-020 y testing          |
| [ADR-006](adr-006-audio.md)                              | Captura de audio local y explícita                            | Aceptada, en parte sustituida por ADR-016 | Sí, demo sintética/local                                                        |
| [ADR-007](adr-007-asr-local.md)                          | ASR local                                                     | Aceptada                                  | Sí, motor sherpa_onnx tras ADR-016                                              |
| [ADR-008](adr-008-ner-tokenizacion-reversible.md)        | NER y tokenización reversible                                 | Sustituida por ADR-017                    | No                                                                              |
| [ADR-009](adr-009-sintesis-cloud-proveedor-abstracto.md) | Síntesis cloud tras proveedor abstracto                       | Sustituida por ADR-017                    | No; `clinical-summary` eliminado                                                |
| [ADR-010](adr-010-retencion-eliminacion-audio.md)        | Retención mínima y eliminación de audio                       | Aceptada, en parte sustituida por ADR-016 | Sí, purga local de temporales                                                   |
| [ADR-011](adr-011-resumen-temporal-cache.md)             | Resumen temporal versionado y caché                           | Aceptada                                  | Stub sin implementación                                                         |
| [ADR-012](adr-012-turnos-fuera-de-alcance.md)            | Turnos fuera de alcance                                       | Aceptada                                  | No se observa dominio de turnos                                                 |

## Regla de cambio

Una decisión se modifica con una ADR nueva que la sustituya, no reescribiendo silenciosamente sus consecuencias. Correcciones editoriales o enlaces de evidencia pueden actualizarse sin nueva ADR. Todo cambio debe revisar seguridad, pruebas, roadmap, trazabilidad, preguntas y riesgos relacionados.
