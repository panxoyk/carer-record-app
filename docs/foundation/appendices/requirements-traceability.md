# Trazabilidad de requisitos

## Convenciones

Los identificadores son estables dentro de esta fundación. **Actual** significa evidenciado en el repositorio; **objetivo** significa decidido o propuesto, pero no implementado. Flujos y entidades objetivo no afirman existencia. La columna de pruebas nombra evidencia actual o prueba requerida.

## Flujos

| ID   | Flujo                                          | Contrato detallado                                                                                                     |
| ---- | ---------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| F-01 | Autenticación, recuperación y cierre de sesión | [Flujo de autenticación](../flows/authentication.md)                                                                   |
| F-02 | Administración de practitioners                | [Flujo de administración de usuarios](../flows/user-administration.md)                                                 |
| F-03 | Consulta de paciente y timeline                | [Flujo de consulta clínica](../flows/clinical-query.md)                                                                |
| F-04 | Ingesta FHIR sintética                         | [Flujo de ingesta FHIR R4](../flows/fhir-ingestion.md)                                                                 |
| F-05 | Captura de audio y ASR local                   | [Flujo de nota de audio](../flows/audio-note.md)                                                                       |
| F-06 | NER, tokenización y reversión                  | [Nota de audio](../flows/audio-note.md) y [nota textual](../flows/text-note.md)                                        |
| F-07 | Síntesis cloud solo sintética                  | [Nota de audio](../flows/audio-note.md), [nota textual](../flows/text-note.md) y [resumen](../flows/period-summary.md) |
| F-08 | Resumen temporal y cache                       | [Flujo de resumen de periodo](../flows/period-summary.md)                                                              |
| F-09 | Retención y eliminación de audio/derivados     | [Ciclo de vida de la nota de audio](../flows/audio-note.md)                                                            |
| F-10 | Auditoría y publicación outbox                 | Transversal a [roles y permisos](../flows/roles-permissions.md), ingesta, notas y resumen                              |

## Entidades

El [modelo de dominio](../07-domain-model.md) es la definición completa. Esta agrupación asigna identificadores de trazabilidad sin reemplazar sus agregados ni invariantes.

| ID   | Entidad o grupo                                                                       | Estado                             |
| ---- | ------------------------------------------------------------------------------------- | ---------------------------------- |
| E-01 | `Practitioner` actual; `Profile` objetivo                                             | Actual y evolución objetivo        |
| E-02 | `Organization`, `Unit`, `Membership`, `Role`, `RoleAssignment` y catálogo de permisos | Objetivo                           |
| E-03 | `Patient` e identificadores                                                           | Actual mínimo y evolución objetivo |
| E-04 | `Hospitalization` y `LocationPeriod`                                                  | Objetivo                           |
| E-05 | `ClinicalEvent` actual; `ClinicalRecord` y subtipos canónicos objetivo                | Actual mínimo y evolución objetivo |
| E-06 | `IngestionRun`, `SourceResource`, correspondencias, checkpoint y error de mapping     | Objetivo                           |
| E-07 | `RecordingSession` y `AudioArtifact` locales                                          | Objetivo local                     |
| E-08 | `TranscriptDraft`, `DetectedEntity`, `TokenizedDocument` y `TokenMap`                 | Objetivo local                     |
| E-09 | `SummarySnapshot` y `SummaryCacheEntry`                                               | Objetivo                           |
| E-10 | `AuditEvent` y `OutboxMessage` servidor/local según el flujo                          | Objetivo; diseño físico pendiente  |

## Matriz principal

| Requisito | Formulación verificable                                                                                                     | Estado               | ADR                 | Flujo               | Entidad             | Prueba/evidencia                                                                                                                          |
| --------- | --------------------------------------------------------------------------------------------------------------------------- | -------------------- | ------------------- | ------------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| RQ-001    | El repositorio versiona conjuntamente app, backend, pipeline y docs, sin secretos/datos reales                              | Actual parcial       | ADR-001             | Todos               | Todas               | `package.json:1-33`; CI y secret scan pendiente                                                                                           |
| RQ-002    | El sistema se presenta como prototipo académico con datos sintéticos                                                        | Actual parcial       | ADR-002             | Todos               | Todas               | `app/pubspec.yaml:1-4`; `supabase/seed.sql:1-22`                                                                                          |
| RQ-003    | Auth, Postgres, RLS y Edge usan Supabase; Flutter solo usa clave publishable                                                | Actual               | ADR-003             | F-01/F-02/F-03      | E-01/E-03/E-05      | `app/lib/core/network/supabase_client.dart:4-15`                                                                                          |
| RQ-004    | Anónimo, sin perfil y suspendido no acceden a datos clínicos                                                                | Actual               | ADR-003/005         | F-03                | E-01/E-03/E-05      | `clinical_rls_phase3.test.sql`; `patients_rls.test.sql:18-27`                                                                             |
| RQ-005    | Administrar usuarios no basta para conceder acceso clínico; la excepción demo usa permiso reservado, alcance y RLS          | Actual y objetivo    | ADR-003/005/013     | F-02/F-03           | E-01/E-03/E-05      | `clinical_rls_phase3.test.sql`; `hospitalizations_assignments_phase2.test.sql:168-173`                                                    |
| RQ-006    | Service Role existe solo en servidor y después de autenticar/autorizar caller                                               | Actual backend       | ADR-003             | F-02                | E-01                | `create-practitioner` caller JWT para auth/RPC, Service Role solo Auth admin; tests HTTP Deno; Flutter pendiente                          |
| RQ-007    | Permisos se configuran mediante catálogo/grants y RLS, con denegación por ausencia                                          | Objetivo             | ADR-005/013         | F-02/F-03           | E-01/E-02           | pgTAP grant/revoke/suspendido/concurrencia                                                                                                |
| RQ-027    | Personal clínico solo lee una hospitalización con permiso concreto, `clinical.assigned.read` y asignación vigente           | Actual DB            | ADR-013             | F-02/F-03           | E-02/E-04/E-05      | `20261011270000_clinical_rls_contracts.sql`, `20261011280000_harden_clinical_runtime_writes_and_views.sql`; pgTAP/reset/upgrade aprobados |
| RQ-028    | `clinical.organization.read` solo permite lectura demo desde el rol protegido, no se copia ni delega y RLS no usa nombre/ID | Actual DB            | ADR-013             | F-02/F-03           | E-02/E-04/E-05      | helper clínico scoped y pgTAP de permiso reservado/tenant aprobados                                                                       |
| RQ-008    | FHIR se valida/mapea en una frontera versionada y no atraviesa el dominio                                                   | Objetivo             | ADR-004             | F-04/F-03           | E-03/E-04/E-05/E-06 | contract tests y matriz de mapping                                                                                                        |
| RQ-009    | Reingesta del mismo recurso FHIR no duplica efectos                                                                         | Objetivo             | ADR-004             | F-04                | E-03/E-04/E-05/E-06 | replay secuencial/concurrente                                                                                                             |
| RQ-010    | Audio se captura explícitamente, local y con indicador/límites                                                              | Objetivo             | ADR-006             | F-05                | E-07                | widget/integration: permiso, interrupción, límite                                                                                         |
| RQ-011    | Audio no se envía a Supabase ni cloud                                                                                       | Objetivo             | ADR-006/007         | F-05                | E-07                | E2E sin egress y revisión de red                                                                                                          |
| RQ-012    | ASR se ejecuta local, versionado y sin fallback cloud                                                                       | Objetivo             | ADR-007             | F-05                | E-07/E-08           | SP-01, checksum y fallo offline                                                                                                           |
| RQ-013    | Transcripción permanece como artefacto técnico local; el autor revisa audio y síntesis                                      | Objetivo             | ADR-007             | F-05                | E-08                | widget test de reproducción, síntesis y procedencia                                                                                       |
| RQ-014    | NER/tokenización ocurre localmente con tokens por documento                                                                 | Objetivo             | ADR-008             | F-06                | E-08                | SP-02/SP-03 y corpus adversarial                                                                                                          |
| RQ-015    | Mapa reversible se cifra, separa, autoriza y excluye de logs/proveedor                                                      | Objetivo             | ADR-008             | F-06/F-07           | E-08/E-10           | tests de acceso, logs y adapter                                                                                                           |
| RQ-016    | NER no se etiqueta como anonimización y la salida sigue clasificada sensible                                                | Documentado          | ADR-002/008         | F-06                | E-08                | revisión de UI/docs y risk review                                                                                                         |
| RQ-017    | Proveedor de síntesis está detrás de un puerto reemplazable                                                                 | Objetivo             | ADR-009             | F-07                | E-09                | contract suite común fake/adapter                                                                                                         |
| RQ-018    | Cloud rechaza procedencia real/desconocida y acepta solo sintética                                                          | Objetivo             | ADR-002/009         | F-07                | E-08/E-09           | tests de guard y payload                                                                                                                  |
| RQ-019    | Audio y derivados expiran y se eliminan idempotentemente                                                                    | Objetivo bloqueado   | ADR-010             | F-09                | E-07/E-08/E-10      | cleanup éxito/error/crash/retry                                                                                                           |
| RQ-020    | Resumen usa intervalo `[desde,hasta)`, timezone y fuentes versionadas                                                       | Objetivo             | ADR-011             | F-08                | E-05/E-09           | bordes temporales y golden request                                                                                                        |
| RQ-021    | Cache solo retorna match exacto y vigente, aislado por RLS                                                                  | Objetivo             | ADR-003/011         | F-08                | E-09                | hit/miss/invalidation/isolation                                                                                                           |
| RQ-022    | Logs excluyen PHI/IPS, audio, tokens reversibles, JWT y secretos                                                            | Objetivo transversal | ADR-003/006/008/009 | Todos               | E-10                | tests de ausencia y revisión de muestras                                                                                                  |
| RQ-023    | Mutación y outbox se escriben atómicamente; publicación es idempotente                                                      | Objetivo             | ADR-001/003         | F-04/F-08/F-09/F-10 | E-06/E-09/E-10      | fault injection y workers concurrentes                                                                                                    |
| RQ-024    | Auditoría registra metadatos de acciones críticas sin contenido clínico                                                     | Objetivo             | ADR-003/005/010/013 | F-02/F-06/F-09/F-10 | E-10                | pgTAP permisos/esquema, bootstrap/asignaciones y E2E                                                                                      |
| RQ-025    | Turnos, scheduling y permisos por turno no se implementan                                                                   | Decidido             | ADR-012             | Ninguno             | Ninguna             | revisión de esquema, UI y backlog                                                                                                         |
| RQ-026    | Ninguna entrega afirma cumplimiento o uso productivo sin puerta independiente                                               | Documentado          | ADR-002             | Todos               | Todas               | revisión de release/documentación                                                                                                         |

El gate 5.2 aporta evidencia local acotada para RQ-006/007/024 y RQ-026: Edge/Auth de alta sintética, controles de caller, DML clínico denegado y reset de cleanup. No cambia el estado objetivo de escritura clínica, auditoría de lectura o concurrencia real; los detalles y límites están en EV-SEC-017.

## Trazabilidad inversa por ADR

| ADR     | Requisitos principales                 |
| ------- | -------------------------------------- |
| ADR-001 | RQ-001, RQ-023                         |
| ADR-002 | RQ-002, RQ-016, RQ-018, RQ-026         |
| ADR-003 | RQ-003-RQ-006, RQ-021-RQ-024           |
| ADR-004 | RQ-008, RQ-009                         |
| ADR-005 | RQ-004, RQ-005, RQ-007, RQ-024         |
| ADR-013 | RQ-005, RQ-007, RQ-024, RQ-027, RQ-028 |
| ADR-006 | RQ-010, RQ-011, RQ-022                 |
| ADR-007 | RQ-011-RQ-013                          |
| ADR-008 | RQ-014-RQ-016, RQ-022                  |
| ADR-009 | RQ-017, RQ-018, RQ-022                 |
| ADR-010 | RQ-019, RQ-024                         |
| ADR-011 | RQ-020, RQ-021                         |
| ADR-012 | RQ-025                                 |

## Regla de cierre

Un requisito pasa a **Actual** solo con ruta de implementación y prueba reproducible. Si es imposible automatizarlo, debe existir protocolo, fecha, entorno, responsable, resultado y limitación. La falta de una columna aplicable indica una brecha de diseño y bloquea declarar completo el corte vertical.
