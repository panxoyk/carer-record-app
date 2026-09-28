# Índice de evidencia

## Cómo leer este índice

- **Implementado:** existe código/configuración observable.
- **Probado:** existe prueba automatizada relevante en el repositorio.
- **Documentado:** existe decisión o regla, sin evidencia suficiente de ejecución.
- **Brecha:** no existe implementación o validación necesaria.

Las referencias `ruta:líneas` describen el estado observado el 2026-09-27 y pueden desplazarse con cambios. Este índice no certifica producción ni cumplimiento.

## Evidencia de producto y arquitectura

| ID     | Afirmación acotada                                | Fuente                                                      | Fuerza                     | Limitación                                |
| ------ | ------------------------------------------------- | ----------------------------------------------------------- | -------------------------- | ----------------------------------------- |
| EV-001 | El repositorio reúne Flutter, Supabase y pipeline | `app/`; `supabase/`; `scripts/data_pipeline/main.py:1-15`   | Observado                  | No demuestra sincronía remota             |
| EV-002 | El cliente usa URL y clave publishable            | `app/lib/core/network/supabase_client.dart:4-15`            | Implementado               | No prueba almacenamiento seguro de sesión |
| EV-003 | El registro público local está deshabilitado      | `supabase/config.toml:18-30`                                | Implementado local         | No acredita configuración productiva      |
| EV-004 | La app separa repositorios de entidades           | `app/lib/domains/patient/data/patient_repository.dart:1-30` | Implementado               | Cobertura limitada a dominios actuales    |
| EV-005 | FHIR está diferido                                | `scripts/data_pipeline/main.py:1-15`                        | Implementado como scaffold | No hay parser ni mapping                  |
| EV-006 | Resumen está diferido                             | `supabase/functions/clinical-summary/index.ts:3-19`         | Implementado como stub     | Devuelve 501                              |
| EV-007 | La demo presenta instantes en `America/Santiago`  | `app/lib/core/time/clinical_time.dart:4-24`                 | Implementado y probado     | La zona aún no se obtiene de organización |

## Seguridad y privacidad

| ID         | Afirmación acotada                                      | Fuente                                                                   | Fuerza                 | Limitación                                        |
| ---------- | ------------------------------------------------------- | ------------------------------------------------------------------------ | ---------------------- | ------------------------------------------------- |
| EV-SEC-001 | RLS está habilitado en tablas iniciales                 | `supabase/migrations/20260910000000_initial_clinical_schema.sql:41-47`   | Implementado           | Políticas iniciales fueron luego sustituidas      |
| EV-SEC-002 | Administración y clínica se separan                     | `supabase/migrations/20260910010000_auth_administration.sql:7-35`        | Implementado           | Modelo administrativo aún simple                  |
| EV-SEC-003 | Roles asistenciales activos leen pacientes              | `supabase/migrations/20260910100000_patient_read_access.sql:3-23`        | Implementado           | Lista estática, sin ámbitos                       |
| EV-SEC-004 | Eventos reutilizan autoridad clínica                    | `supabase/migrations/20260910110000_clinical_timeline.sql:53-68`         | Implementado           | Solo lectura                                      |
| EV-SEC-005 | Helpers privilegiados fijan search path y grants        | `supabase/migrations/20260912000000_harden_function_privileges.sql:1-56` | Implementado y probado | No cubre funciones futuras                        |
| EV-SEC-006 | Anónimo, sin perfil, admin y suspendido no leen clínica | `supabase/tests/patients_rls.test.sql:29-130`                            | Probado                | Solo esquema/escenarios locales                   |
| EV-SEC-007 | Mutaciones clínicas están denegadas                     | `supabase/tests/patients_rls.test.sql:63-79,133-169`                     | Probado                | No hay escritura clínica autorizada               |
| EV-SEC-008 | Service Role solo aparece en cliente servidor separado  | `supabase/functions/create-practitioner/index.ts:74-95`                  | Implementado           | No hay test HTTP ni escaneo acreditado            |
| EV-SEC-009 | RUT se enmascara en presentación                        | `app/lib/domains/patient/domain/entities/patient.dart:41-49`             | Implementado y probado | Valor completo llega al cliente                   |
| EV-SEC-010 | Seed declara datos ficticios                            | `supabase/seed.sql:1-22`                                                 | Documentado            | No es prevención automática                       |
| EV-SEC-011 | Audio, ASR y NER no existen                             | `app/pubspec.yaml:10-20`                                                 | Brecha observada       | Ausencia de dependencia no descarta código futuro |
| EV-SEC-012 | Auditoría/outbox no están en esquema actual             | `supabase/migrations/20260910000000_initial_clinical_schema.sql:7-39`    | Brecha observada       | Requiere revisar migraciones futuras              |

## Calidad y entrega

| ID         | Afirmación acotada                            | Fuente                                                                                                                     | Fuerza       | Limitación                               |
| ---------- | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ------------ | ---------------------------------------- |
| EV-TST-001 | CI ejecuta base, checks y Flutter tests       | `.github/workflows/verify.yml:19-35`                                                                                       | Implementado | No contiene E2E nuevos                   |
| EV-TST-002 | Hay scripts para pgTAP                        | `package.json:9-14`                                                                                                        | Implementado | Requiere runtime local/Docker            |
| EV-TST-003 | Edge solo tiene checks estáticos por defecto  | `package.json:21-26`                                                                                                       | Implementado | Sin tests HTTP                           |
| EV-TST-004 | pgTAP cubre privilegios de helpers            | `supabase/tests/function_privileges.test.sql:1-47`                                                                         | Probado      | Solo funciones existentes                |
| EV-TST-005 | Flutter cubre enmascaramiento y búsqueda      | `app/test/domains/patient/domain/entities/patient_test.dart:1-49`                                                          | Probado      | No hay widget/integration tests          |
| EV-TST-006 | La suite del baseline es mínima               | `baseline/carer-record-app.md:165-189`                                                                                     | Observado    | Debe ampliarse por cortes de alto riesgo |
| EV-TST-007 | Flutter cubre fechas institucionales y textos | `app/test/core/time/clinical_time_test.dart:5-32`; `app/test/domains/patient/presentation/patient_screens_test.dart:25-81` | Probado      | Sin validación E2E                       |

## Evidencia pendiente por decisión

| ADR     | Evidencia requerida para llamar “implementada”                           |
| ------- | ------------------------------------------------------------------------ |
| ADR-004 | adapter FHIR, matriz de mapping, fixtures, contract tests e idempotencia |
| ADR-005 | esquema de permisos, RLS, administración, auditoría y pgTAP              |
| ADR-006 | interfaz de captura, permisos, storage privado y pruebas de interrupción |
| ADR-007 | motor local, checksum/licencia, SP-01 y test sin egress                  |
| ADR-008 | taxonomía, formato token, mapa cifrado, SP-02/SP-03 y tests              |
| ADR-009 | puerto/adapters, fake, guard sintético y tests HTTP/contractuales        |
| ADR-010 | política aprobada, state machine, barrido y prueba de borrado            |
| ADR-011 | modelo temporal/cache, RLS, invalidación, idempotencia y E2E             |
| ADR-012 | revisión de lenguaje/requisitos que confirme exclusión de turnos         |

## Reglas de actualización

Una evidencia debe indicar entorno, commit, comando y resultado cuando provenga de ejecución. Capturas de pantalla aisladas no demuestran autorización ni idempotencia. Los resultados de spikes se registran con protocolo, hardware, corpus sintético, versiones y limitaciones. Si código y documentación discrepan, prevalece el comportamiento verificado y se abre una corrección documental.
