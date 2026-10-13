# Fundamentos de producto y arquitectura

## Estado

Esta carpeta es la fuente canónica para la evolución de Carer Record App (CRA). Define el producto, el alcance del prototipo funcional académico, la arquitectura objetivo, el modelo de dominio y datos, los flujos, las decisiones y la evidencia que deben guiar los siguientes incrementos.

La documentación distingue permanentemente entre:

| Estado               | Significado                                                                   |
| -------------------- | ----------------------------------------------------------------------------- |
| **Confirmado**       | Existe evidencia en código, migraciones, pruebas o documentación versionada.  |
| **Decidido**         | Dirección adoptada; puede no estar implementada todavía.                      |
| **Propuesto**        | Diseño sujeto a spike, medición o decisión posterior.                         |
| **Pendiente**        | Falta implementación o evidencia para cerrar el punto.                        |
| **Fuera de alcance** | No se implementará en el prototipo académico salvo una nueva decisión formal. |

Una decisión aceptada no equivale a funcionalidad implementada. La implementación solo se declara cuando existe código y prueba reproducible.

## Resumen ejecutivo

Carer Record es una capa de contexto clínico e integración para hospitalización. No reemplaza la Ficha Clínica Electrónica (FCE), no prescribe, no diagnostica y no se presenta como producto listo para datos reales. El prototipo busca demostrar, con datos sintéticos, que es posible:

- integrar un subconjunto limitado de FHIR R4 desde una FCE simulada;
- normalizarlo hacia un modelo interno mantenible y trazable;
- limitar el acceso mediante permisos configurables por institución y unidad;
- consultar una hospitalización y su timeline de información relevante;
- registrar contexto mediante texto o audio con confirmación del mismo autor;
- ejecutar ASR y NER localmente antes de solicitar síntesis cloud;
- generar resúmenes temporales de fuentes autorizadas sin convertirlos en registros clínicos.

`carer-record-app` es el repositorio canónico. Conserva Flutter, Supabase Auth, PostgreSQL, PostgREST, Edge Functions, RLS, migraciones y pgTAP. El repositorio hermano `../carer-record` conserva evidencia histórica y experimentos funcionales; sus decisiones inseguras o acopladas a MariaDB no se portan literalmente.

## Decisiones centrales

1. El proyecto es un prototipo funcional académico estructurado para evolución futura.
2. CRA continúa sobre Flutter y Supabase; RLS es la autoridad de autorización.
3. La demo usa una organización, pero claves, relaciones y políticas se diseñan con aislamiento multiinstitución.
4. Cada hospital configura roles sobre un catálogo fijo de permisos. Para Personal clínico, los permisos concretos solo habilitan lectura junto con una asignación asistencial vigente a la hospitalización; el alcance organizacional o de unidad no la sustituye. La excepción de demo requiere `clinical.organization.read` reservado, permiso concreto, alcance y RLS; no depende del nombre/ID del rol y está limitada por ADR-013.
5. La hospitalización, no el paciente aislado, es el eje para ubicación, timeline, notas y permisos.
6. FHIR R4 es una frontera de intercambio, no el esquema interno.
7. El primer subconjunto FHIR incluye `Organization`, `Patient`, `Encounter`, `Location`, `Condition`, `Observation`, `AllergyIntolerance` y `MedicationRequest`, más `CapabilityStatement`, `Bundle` y `OperationOutcome` como infraestructura.
8. Los datos externos son inicialmente de solo lectura y no existe write-back a la FCE.
9. Las notas de audio conservan el audio en el dispositivo, usan ASR y NER locales y envían solamente texto tokenizado a un proveedor cloud abstracto mediante una Edge Function.
10. El mapa reversible nunca sale del límite confiable. La respuesta se valida, restaura localmente y es confirmada por el mismo autor.
11. Audio, transcripción, mapa y artefactos intermedios se eliminan al confirmar, descartar o expirar.
12. Un resumen de periodo es una vista temporal con caché invalidable; nunca se publica automáticamente como nota.
13. Gestión de turnos, RRHH, handoff formal, FHIR universal, datos reales y cumplimiento productivo quedan fuera del prototipo.
14. Los hitos de bitácora son notas de contexto confirmadas e inmutables (texto o audio almacenado en bucket privado) que el autor publica en el timeline de su hospitalización; el audio de hito sí se persiste, a diferencia del flujo experimental de ASR (ADR-015).

## Mapa de lectura

### Producto y alcance

| Documento                                         | Pregunta que responde                                        |
| ------------------------------------------------- | ------------------------------------------------------------ |
| [Visión de producto](01-product-vision.md)        | ¿Qué problema aborda CRA y qué lugar ocupa frente a una FCE? |
| [Prototipo funcional](02-functional-prototype.md) | ¿Qué debe demostrar académicamente y qué no puede afirmar?   |
| [Alcance](03-scope.md)                            | ¿Qué existe, qué se construirá y qué queda fuera?            |
| [Roadmap](12-delivery-roadmap.md)                 | ¿En qué cortes verticales se implementará y verificará?      |

### Arquitectura y datos

| Documento                                          | Pregunta que responde                                               |
| -------------------------------------------------- | ------------------------------------------------------------------- |
| [Arquitectura objetivo](04-target-architecture.md) | ¿Cómo colaboran Flutter, Supabase, ingesta y proveedores externos?  |
| [Control de acceso](05-access-control.md)          | ¿Cómo se modelan roles, permisos, ámbitos y RLS?                    |
| [Integración FHIR](06-fhir-integration.md)         | ¿Qué parte de FHIR se soporta y cómo se protege el dominio interno? |
| [Modelo de dominio](07-domain-model.md)            | ¿Cuáles son los conceptos, agregados e invariantes del producto?    |
| [Modelo de datos](08-data-model.md)                | ¿Qué estructura relacional objetivo soporta esos conceptos?         |
| [Audio, IA y NER](09-audio-ai-ner.md)              | ¿Cómo se captura, protege, sintetiza y elimina contenido temporal?  |
| [Seguridad y privacidad](10-security-privacy.md)   | ¿Cuáles son límites de confianza, amenazas y controles?             |
| [Pruebas y validación](11-testing-validation.md)   | ¿Qué evidencia técnica y académica exige cada capacidad?            |

### Baseline histórico

| Documento                                          | Contenido                                                                 |
| -------------------------------------------------- | ------------------------------------------------------------------------- |
| [`carer-record`](baseline/carer-record.md)         | Fotografía fechada de arquitectura, funciones, datos y riesgos heredados. |
| [`carer-record-app`](baseline/carer-record-app.md) | Fotografía del commit base de Flutter/Supabase, RLS, pruebas y deuda.     |
| [Comparación](baseline/comparison.md)              | Evidencia histórica para elegir CRA como repositorio canónico.            |

### Flujos funcionales

| Flujo                                                      | Estado documental  |
| ---------------------------------------------------------- | ------------------ |
| [Autenticación](flows/authentication.md)                   | Actual y evolución |
| [Administración de usuarios](flows/user-administration.md) | Actual y evolución |
| [Roles y permisos](flows/roles-permissions.md)             | Objetivo           |
| [Ingesta FHIR](flows/fhir-ingestion.md)                    | Objetivo           |
| [Consulta clínica](flows/clinical-query.md)                | Actual y evolución |
| [Nota textual](flows/text-note.md)                         | Objetivo           |
| [Nota de audio](flows/audio-note.md)                       | Objetivo           |
| [Resumen de periodo](flows/period-summary.md)              | Objetivo           |

Cada flujo define objetivo, actores, permisos, precondiciones, camino principal, errores, estados, datos, RLS, auditoría, criterios de aceptación y pruebas.

### Gobierno y anexos

| Documento                                                  | Contenido                                                    |
| ---------------------------------------------------------- | ------------------------------------------------------------ |
| [Índice de ADR](decisions/index.md)                        | Registro de decisiones aceptadas y estado de implementación. |
| [Índice de evidencia](appendices/evidence-index.md)        | Fuentes que respaldan el diagnóstico y las decisiones.       |
| [Trazabilidad](appendices/requirements-traceability.md)    | Requisito → ADR → flujo → entidad → prueba.                  |
| [Catálogo FHIR R4](appendices/fhir-r4-resource-catalog.md) | Familias de recursos y contexto de selección.                |
| [Selección FHIR](appendices/fhir-resource-selection.md)    | Recursos incluidos, diferidos y descartados con argumentos.  |
| [Glosario](appendices/terminology-glossary.md)             | Terminología usada consistentemente por la fundación.        |
| [Preguntas abiertas](appendices/open-questions.md)         | Decisiones de implementación todavía no resueltas.           |
| [Registro de riesgos](appendices/risk-register.md)         | Riesgos, prioridad, controles y evidencia requerida.         |

## Recorridos recomendados

### Incorporación de una persona desarrolladora

1. Leer visión, prototipo y alcance.
2. Revisar la comparación de repositorios.
3. Leer arquitectura, acceso y modelo de dominio.
4. Consultar el flujo específico que se implementará.
5. Revisar ADR, riesgos y trazabilidad asociados.
6. Implementar el corte vertical siguiendo permisos → datos/RLS → pruebas → repositorio → UI.

### Cambio de modelo o seguridad

1. Revisar `04-target-architecture.md`, `05-access-control.md` y `08-data-model.md`.
2. Confirmar que la ADR vigente permite el cambio; crear una ADR sustitutiva si cambia una decisión.
3. Actualizar threat model, pruebas, trazabilidad, riesgos y flujo afectado.
4. Usar migraciones aditivas y probar reset limpio y upgrade con datos sintéticos.

### Incorporación de un recurso FHIR

1. Actualizar catálogo y matriz de selección.
2. Definir perfil/campos, referencias, pérdidas aceptadas y terminología.
3. Definir procedencia, identidad, idempotencia y entidad canónica.
4. Añadir fixtures, mapping tests, replay y casos inválidos.
5. Actualizar read model y UI solo después de cerrar autorización y persistencia.

## Reglas de mantenimiento

- El código y las migraciones son autoridad sobre lo implementado; esta fundación es autoridad sobre dirección y alcance.
- `baseline/` es una fotografía fechada y no se mantiene como descripción del estado actual.
- Las referencias de evidencia usan rutas relativas y líneas cuando es posible.
- Una decisión se cambia mediante una ADR nueva o sustitutiva, no ocultando la alternativa previa.
- Una capacidad solo se marca **implementada** cuando código y pruebas reproducibles existen.
- Ningún documento, fixture, log o captura contiene datos clínicos reales.
- Todo cambio funcional revisa alcance, ADRs, flujos, modelo, seguridad, pruebas, riesgos y trazabilidad.
- La documentación se valida con `pnpm docs:format:check`, `pnpm docs:lint` y `git diff --check`.
