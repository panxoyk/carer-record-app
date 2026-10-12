# Alcance

## Regla de interpretación

Este documento distingue la fotografía del baseline, el alcance decidido para el prototipo y la visión de largo plazo. Una capacidad mencionada como futura no se presume implementada; el código y las pruebas deben verificarse directamente.

| Estado               | Uso en este documento                                                     |
| -------------------- | ------------------------------------------------------------------------- |
| **Confirmado**       | Disponible en el repositorio y respaldado por evidencia.                  |
| **Decidido**         | Límite adoptado para orientar el trabajo.                                 |
| **Propuesto**        | Candidato a un incremento futuro, aún no comprometido.                    |
| **Pendiente**        | Necesita implementación, diseño o validación.                             |
| **Fuera de alcance** | No se realizará en el incremento actual o en la etapa académica indicada. |

## Baseline histórico de CRA

**Confirmado en el baseline.** La fotografía inicial registra una aplicación móvil de acceso controlado, administración de practitioners y consulta clínica de solo lectura sobre Supabase local con datos sintéticos (`baseline/carer-record-app.md:9-13`). Esta sección no se mantiene como inventario del estado posterior.

### Incluido

| Área             | Capacidad incluida                                                              | Evidencia                                                                                                                      |
| ---------------- | ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ |
| Entorno          | Flutter móvil con configuración Supabase inyectada mediante `--dart-define`.    | `app/lib/main.dart:8`, `scripts/run-app.sh:1`                                                                                  |
| Identidad        | Acceso y cierre de sesión con email y contraseña.                               | `app/lib/domains/auth/data/auth_repository.dart:11`                                                                            |
| Recuperación     | Solicitud y actualización de contraseña con deep link local.                    | `app/lib/domains/auth/data/auth_repository.dart:20`, `supabase/config.toml:18`                                                 |
| Estado de cuenta | Estados `active` y `suspended`; una cuenta suspendida solo puede cerrar sesión. | `supabase/migrations/20260910000000_initial_clinical_schema.sql:8`, `app/lib/core/router/app_router.dart:28`                   |
| Roles            | `administrator`, `physician`, `nurse` y `technician`.                           | `supabase/migrations/20260910000000_initial_clinical_schema.sql:4`                                                             |
| Administración   | Listar, crear, cambiar rol y activar/suspender practitioners.                   | `app/lib/domains/users/presentation/users_screen.dart:18`, `app/lib/domains/users/presentation/users_screen.dart:87`           |
| Pacientes        | Listar, buscar por nombre o RUT, filtrar por unidad y consultar ficha.          | `app/lib/domains/patient/presentation/patient_screens.dart:63`, `app/lib/domains/patient/domain/entities/patient.dart:24`      |
| Timeline         | Consultar eventos por paciente y filtrar categorías en la interfaz.             | `app/lib/domains/patient/presentation/patient_screens.dart:465`                                                                |
| Perfil           | Consultar nombre, rol, estado, correo y cerrar sesión.                          | `app/lib/domains/patient/presentation/patient_screens.dart:954`                                                                |
| Autorización     | RLS para perfil propio, administración y lectura clínica según rol/estado.      | `supabase/migrations/20260910010000_auth_administration.sql:23`, `supabase/migrations/20260910110000_clinical_timeline.sql:53` |
| Datos            | Migraciones versionadas y seed exclusivamente sintético.                        | `README.md:41`, `README.md:100`                                                                                                |
| Calidad          | Checks de Flutter, documentación, Deno, pipeline y pruebas dirigidas.           | `package.json:15-33`, `.github/workflows/verify.yml:19-35`                                                                     |

### Permisos incluidos

**Confirmado en el baseline.** La matriz capturada es:

| Rol o estado                | Practitioners                                     | Pacientes           | Eventos clínicos    |
| --------------------------- | ------------------------------------------------- | ------------------- | ------------------- |
| `administrator` activo      | Listar, crear y actualizar.                       | Sin acceso.         | Sin acceso.         |
| `physician` activo          | Leer perfil propio.                               | Listar y consultar. | Consultar timeline. |
| `nurse` activo              | Leer perfil propio.                               | Listar y consultar. | Consultar timeline. |
| `technician` activo         | Leer perfil propio.                               | Listar y consultar. | Consultar timeline. |
| Cualquier rol suspendido    | Sin privilegios adicionales; puede cerrar sesión. | Sin acceso.         | Sin acceso.         |
| Anónimo o sesión sin perfil | Sin acceso.                                       | Sin acceso.         | Sin acceso.         |

La tabla deriva de las pruebas RLS (`supabase/tests/patients_rls.test.sql:29-169`). No sustituye el contrato objetivo de [`05-access-control.md`](05-access-control.md).

## Excluido del baseline

### Escritura clínica

**Fuera del baseline.** Las políticas capturadas no permiten crear, editar ni eliminar pacientes o eventos (`supabase/tests/patients_rls.test.sql:133-169`). La escritura objetivo solo puede incorporarse con permisos y pruebas explícitos.

Esto excluía en el baseline:

- notas clínicas o de contexto;
- registro manual de eventos;
- grabación, carga, reproducción o transcripción de audio;
- confirmación de contenido generado;
- altas, cierres de caso o cambios de turno;
- asignación de pacientes a profesionales;
- edición de ubicación o antecedentes.

### Integración e IA

**Fuera del baseline.** No se incluían ingesta FHIR, HL7v2, archivos hospitalarios, IA generativa, NER ni clasificación clínica. El pipeline FHIR solo validaba que su scaffold estaba reservado (`scripts/data_pipeline/main.py:9`) y `clinical-summary` solo autenticaba antes de responder que no estaba implementado (`supabase/functions/clinical-summary/index.ts:3`).

### Producción y distribución

**Fuera del prototipo académico.** No se incluyen despliegue productivo, cumplimiento, uso de datos reales ni requisitos de distribución. Los límites normativos se definen en ADR-002 y [`10-security-privacy.md`](10-security-privacy.md).

### Escala

**Fuera del baseline.** No se implementaban paginación, búsqueda remota ni estrategia para grandes volúmenes. La configuración capturada limita las respuestas API a 1000 filas (`supabase/config.toml:3`), y el repositorio observado carga listas completas (`app/lib/domains/patient/data/patient_repository.dart:12`).

## Brechas observadas en el baseline

| Pendiente                                      | Motivo                                                                                                  | Evidencia                                                                                      |
| ---------------------------------------------- | ------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| Validar recuperación con app abierta y cerrada | La fotografía no contiene evidencia reproducible del recorrido completo.                                | `baseline/carer-record-app.md:61-65`                                                           |
| Sustituir textos no respaldados                | “bajo tu atención”, “Ficha activa”, “Hospitalización activa” y “HOY” no derivaban de datos suficientes. | `app/lib/domains/patient/presentation/patient_screens.dart:57`                                 |
| Implementar zona horaria                       | Los eventos se formateaban directamente desde `DateTime`; foundation ya decidió UTC + zona IANA.        | `app/lib/domains/patient/presentation/patient_screens.dart:1100`, `07-domain-model.md:528-534` |
| Completar error y retry                        | Creación/actualización, recuperación y consultas no tenían estados uniformes.                           | `baseline/carer-record-app.md:95-99`                                                           |
| Ampliar evidencia de UI/Auth                   | La fotografía no contiene pruebas HTTP, widget ni integración automatizada para esos flujos.            | `baseline/carer-record-app.md:185-189`                                                         |

## Próximo corte de autorización clínica

**Subtarea DB 3.2, consulta Flutter 4.4 y revisión integrada 4.5 completadas; gate final 5.2 cerrado para demo sintética/local.** La migración aditiva `20261011280000_harden_clinical_runtime_writes_and_views.sql` corrige DML runtime de tablas clínicas y completa los contratos mínimos del censo y timeline. Las vistas se consumen con modelos y repositorios por hospitalización; la integración local verifica censo, demografía específica, timeline, UUID manipulado y revocación.

Este corte no incluye ingesta FHIR completa, escritura clínica, solicitudes de acceso, acceso de emergencia, rol `technician` nuevo ni identificadores completos de paciente. La gestión delegable de asignaciones se rige por [ADR-014](decisions/adr-014-delegacion-gestion-asignaciones.md): exige permiso efectivo y no concede acceso clínico. El upgrade migra cuentas sintéticas de forma aditiva según [ADR-013](decisions/adr-013-acceso-clinico-por-asignacion.md). Fases 3 y 4 forman un único corte desplegable y se integraron únicamente para demo sintética/local; no se afirma concurrencia de dos sesiones, producción ni datos reales.

## Futuro propuesto

**Propuesto.** El orden siguiente reduce el riesgo y evita trasladar capacidades del repositorio hermano sin sus controles faltantes.

### Incremento A: cerrar la consulta de solo lectura

- resolver los textos no sustentados por datos;
- implementar la política de zona horaria decidida;
- completar estados de error y retry;
- registrar evidencia manual del deep link y de los recorridos por rol.

### Incremento B: ingesta sintética reproducible

- definir un contrato FHIR mínimo y una fuente sintética;
- agregar procedencia y claves idempotentes antes de persistir;
- demostrar primera carga, repetición sin duplicados y rechazo controlado;
- conservar la lectura clínica como única exposición móvil.

**Decidido.** La fundación selecciona FHIR R4 y ocho recursos de dominio para la primera integración; el contrato, procedencia y criterios de aceptación están en [`06-fhir-integration.md`](06-fhir-integration.md).

### Incremento C: captura contextual

- definir qué constituye un evento propio de Carer Record;
- diseñar permisos de creación, lectura, corrección e inmutabilidad;
- derivar paciente y autor desde recursos autorizados, no desde campos confiados al cliente;
- implementar primero el contrato textual y reutilizar sus invariantes de autoría, publicación e idempotencia en audio.

**Propuesto.** Esta capacidad acerca el producto a la visión, pero no puede incorporarse hasta acordar la matriz de escritura y sus pruebas RLS.

### Incremento D: audio, ASR, NER y síntesis

- mantener audio y transcripción en el dispositivo y definir su retención temporal;
- medir ASR con vocabulario sintético y dispositivos objetivo;
- ejecutar NER y tokenización reversible local antes de cualquier síntesis cloud;
- presentar audio y síntesis editable para confirmación del mismo autor;
- exigir trazabilidad entre salida, entrada y versión del modelo;
- integrar el proveedor cloud detrás de una interfaz abstracta y usando solo datos sintéticos.

**Pendiente.** El baseline no contiene proveedor, modelo, almacenamiento de audio ni contrato de síntesis en CRA; cada capacidad se incorpora solo al completar el corte y su evidencia.

### Incremento E: resumen temporal

- permitir seleccionar un intervalo explícito con zona horaria institucional;
- resumir únicamente fuentes autorizadas y versionadas;
- aplicar minimización, NER/tokenización y proveedor abstracto;
- conservar como máximo un cache invalidable, no una nota ni un evento clínico;
- mostrar periodo, generación, fuentes y estado de vigencia.

**Decidido.** Gestión de turnos, scheduling, handoff y RRHH quedan fuera del prototipo. Los periodos de resumen no crean una entidad de turno ni permisos dependientes de horario, según [ADR-012](decisions/adr-012-turnos-fuera-de-alcance.md).

## Fuera del alcance académico

**Fuera de alcance.** Salvo una nueva decisión explícita, no forman parte del prototipo académico:

- conexión, certificación o despliegue dentro de un hospital real;
- uso de datos clínicos reales;
- reemplazo o escritura de vuelta en una FCE/SIH;
- diagnóstico, prescripción, alertas autónomas o priorización clínica automatizada;
- comunicación directa con familiares;
- Master Patient Index entre instituciones;
- operación productiva con SLA, soporte y continuidad asistencial;
- afirmaciones de eficacia clínica o cumplimiento normativo.

La visión original limita el producto al contexto hospitalario interno y excluye reemplazar sistemas oficiales o automatizar decisiones (`../carer-record/carer-record.md:193`). El plan heredado también excluye escritura de vuelta y un MPI en su migración inicial (`../carer-record/infra/MIGRATION_TO_SUPABASE.md:64`).

## Regla para ampliar alcance

**Decidido.** Una capacidad pasa de futura a incluida solo cuando:

1. se documenta su objetivo y criterio de aceptación;
2. se define la matriz de permisos;
3. se implementan primero persistencia, RLS y pruebas de autorización;
4. se completa el recorrido móvil;
5. se valida con datos sintéticos;
6. se actualizan roadmap de entrega, ADR, flujo, riesgos, trazabilidad y evidencia de esta fundación.

La presencia de código experimental en `carer-record` no cambia por sí sola el alcance de CRA.
