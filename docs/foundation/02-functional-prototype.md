# Definición del prototipo funcional académico

## Definición

**Decidido.** Un prototipo funcional académico de Carer Record es un artefacto móvil ejecutable, reproducible en un entorno controlado y operado exclusivamente con datos sintéticos, que permite demostrar de extremo a extremo un conjunto acotado de flujos de contexto hospitalario y producir evidencia verificable sobre su comportamiento.

No basta con disponer de maquetas, tablas, endpoints aislados o componentes que compilan. Un flujo se considera funcional cuando una persona puede iniciarlo desde Flutter, recorrer las capas involucradas, observar un resultado persistido o consultado y repetirlo desde una instalación limpia siguiendo instrucciones versionadas.

**Decidido.** La calidad académica del prototipo depende de distinguir con claridad:

- lo que está implementado y verificado;
- lo que existe parcialmente o solo como frontera técnica;
- lo que se propone evaluar en una entrega posterior;
- lo que no puede interpretarse como validación clínica o aptitud productiva.

La necesidad de esta separación surge porque el repositorio hermano califica el trabajo como prototipo parcial y reconoce que la validación clínica y varias funciones centrales siguen pendientes (`../carer-record/informe/Indice/Revision del Prototipo/alcance-del-prototipo.tex:3`, `../carer-record/informe/Indice/Revision del Prototipo/limitaciones-identificadas.tex:14`).

## Criterios mínimos

| Criterio                | Condición de aceptación académica                                                  | Estado en CRA                                                                                                                               |
| ----------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| Ejecutable              | Flutter y sus servicios locales arrancan con instrucciones versionadas.            | **Confirmado**: el README define instalación, Supabase local, reset y ejecución (`README.md:14`, `README.md:27`, `README.md:49`).           |
| Reproducible            | La base se reconstruye desde migraciones y seed sintético.                         | **Confirmado**: `pnpm db:reset` aplica migraciones y datos de demostración (`README.md:41`, `README.md:100`).                               |
| Datos seguros           | No requiere pacientes, credenciales ni infraestructura hospitalaria reales.        | **Decidido** por ADR-002 y reglas del repositorio (`AGENTS.md:15-18`).                                                                      |
| Flujo vertical          | La demostración atraviesa interfaz, dominio/repositorio y persistencia o servicio. | **Confirmado** para acceso, administración y consulta clínica; **Pendiente** para captura e ingesta.                                        |
| Autorización observable | Existen casos permitidos y denegados definidos por rol y estado.                   | **Confirmado** por pruebas RLS (`supabase/tests/patients_rls.test.sql:29-169`).                                                             |
| Evidencia               | Los contratos críticos cuentan con pruebas o protocolo manual explícito.           | **Parcial**: RLS y privacidad tienen pruebas; el baseline no incluye pruebas HTTP, widget ni Auth (`baseline/carer-record-app.md:165-189`). |
| Delimitación            | No se presenta como producto clínico ni como integración institucional real.       | **Decidido**.                                                                                                                               |

## Tres niveles que no deben confundirse

### Visión de producto

**Decidido.** Describe la capa de contexto hospitalario completa: integración de fuentes, vista unificada, trazabilidad, captura complementaria y apoyo de IA bajo revisión humana. Es una dirección de largo plazo y no una descripción del baseline.

### Prototipo funcional objetivo

**Decidido.** Es el conjunto mínimo de flujos que una evaluación académica pretende demostrar de forma reproducible. Puede incorporar capacidades nuevas por incrementos, siempre que cada una tenga permisos, datos sintéticos, criterios de aceptación y evidencia.

### Línea base implementada en CRA

**Confirmado en el baseline.** La fotografía de CRA registra una línea funcional más estrecha:

1. inicio y cierre de sesión con email y contraseña;
2. solicitud y actualización de contraseña mediante deep link;
3. bloqueo de cuenta suspendida;
4. listado, creación y actualización de practitioners por un administrador activo;
5. listado, búsqueda y filtro local de pacientes para roles asistenciales activos;
6. consulta de ficha, ubicación y timeline de eventos clínicos en modo de solo lectura;
7. consulta del perfil y cierre de sesión;
8. reconstrucción local de Supabase con datos sintéticos.

La fotografía del baseline registra acceso, recuperación, administración y consulta clínica de solo lectura (`baseline/carer-record-app.md:9-13`). El router capturado aplica las rutas según sesión, estado y rol (`app/lib/core/router/app_router.dart:16`), y los repositorios observados consultan directamente las tablas protegidas por RLS (`app/lib/domains/patient/data/patient_repository.dart:12`, `app/lib/domains/clinical_event/data/clinical_event_repository.dart:10`).

## Flujos funcionales de la línea base

### PF-01 Acceso y sesión

**Confirmado.** El usuario ingresa email y contraseña; Flutter delega en Supabase Auth y reacciona a cambios de sesión (`app/lib/domains/auth/data/auth_repository.dart:11`, `app/lib/domains/auth/presentation/auth_providers.dart:22`). Sin sesión, el router limita la navegación a acceso y recuperación (`app/lib/core/router/app_router.dart:18`).

**Criterio observable.** Una cuenta activa llega a la ruta correspondiente a su rol; credenciales inválidas muestran un error genérico; cerrar sesión vuelve a la zona pública.

### PF-02 Recuperación de contraseña

**Confirmado parcialmente.** El repositorio implementa solicitud, deep link y actualización de contraseña (`app/lib/domains/auth/data/auth_repository.dart:20`, `app/lib/domains/auth/presentation/auth_screens.dart:143`). Supabase local permite el redirect configurado (`supabase/config.toml:18`).

**Pendiente.** La fotografía del baseline no contiene evidencia reproducible del recorrido con la aplicación abierta y cerrada (`baseline/carer-record-app.md:61-65`). Por ello, el flujo existe en código, pero no se declara validado de extremo a extremo.

### PF-03 Administración de practitioners

**Confirmado.** Un administrador activo puede listar perfiles, crear cuentas, cambiar roles y suspender o activar cuentas (`app/lib/domains/users/presentation/users_screen.dart:18`, `app/lib/domains/users/presentation/users_screen.dart:87`). La creación usa una Edge Function que valida al llamador y reserva la Service Role para el cliente de servidor (`supabase/functions/create-practitioner/index.ts:26`, `supabase/functions/create-practitioner/index.ts:74`).

**Confirmado.** Las políticas permiten al practitioner leer su perfil y al administrador activo listar y actualizar perfiles (`supabase/migrations/20260910010000_auth_administration.sql:23`). Las pruebas pgTAP cubren lectura propia, denegación de autoelevación, administración activa y pérdida de privilegios al suspenderse (`supabase/tests/practitioners_rls.test.sql:27`, `supabase/tests/practitioners_rls.test.sql:71`, `supabase/tests/practitioners_rls.test.sql:95`).

### PF-04 Consulta de pacientes

**Confirmado.** Los roles asistenciales activos listan pacientes, buscan por nombre o RUT y filtran por unidad (`app/lib/domains/patient/presentation/patient_screens.dart:63`, `app/lib/domains/patient/domain/entities/patient.dart:24`). El RUT se enmascara en las tarjetas y la regla cuenta con unit tests (`app/lib/domains/patient/domain/entities/patient.dart:41`, `app/test/domains/patient/domain/entities/patient_test.dart:5`).

**Confirmado.** La ficha expone identificación, referencia externa, fecha de nacimiento, RUT, unidad, cama y navegación a la bitácora (`app/lib/domains/patient/presentation/patient_screens.dart:658`).

### PF-05 Timeline clínico de solo lectura

**Confirmado.** La app consulta eventos por paciente, los ordena por `occurred_at` descendente y permite filtrar visualmente entre clínica, procedimientos y observaciones (`app/lib/domains/clinical_event/data/clinical_event_repository.dart:10`, `app/lib/domains/patient/presentation/patient_screens.dart:465`).

**Confirmado.** Las políticas permiten leer pacientes y eventos a `physician`, `nurse` y `technician` activos, y niegan acceso a administradores, cuentas suspendidas, anónimos y sesiones sin perfil (`supabase/migrations/20260910100000_patient_read_access.sql:10`, `supabase/tests/patients_rls.test.sql:29`, `supabase/tests/patients_rls.test.sql:105`, `supabase/tests/patients_rls.test.sql:118`).

**Confirmado.** No existe escritura clínica: las pruebas demuestran que los roles asistenciales no pueden crear, modificar ni eliminar pacientes o eventos (`supabase/tests/patients_rls.test.sql:56`, `supabase/tests/patients_rls.test.sql:133`).

## Capacidades del prototipo académico ampliado

La siguiente matriz evita interpretar objetivos académicos como comportamiento ya implementado.

| Capacidad              | Definición de demostración                                                       | Clasificación documental                                                                                                             |
| ---------------------- | -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| Consulta contextual    | Acceso autorizado a pacientes, ficha y timeline sintético.                       | **Confirmado** en CRA.                                                                                                               |
| Captura textual        | Crear contexto asociado a una hospitalización y derivar autoría desde la sesión. | **Decidido** como objetivo; todavía no existe en CRA.                                                                                |
| Captura de audio       | Grabar audio sintético local, transcribir, sintetizar y eliminar temporales.     | **Decidido** como objetivo, condicionado a spikes ASR/NER; no existe en CRA.                                                         |
| Confirmación del autor | Escuchar audio, editar la síntesis y confirmar sin cola de revisión externa.     | **Decidido** como objetivo; todavía no existe en CRA.                                                                                |
| Ingesta FHIR simulada  | Cargar FHIR R4 sintético, normalizar y demostrar idempotencia y procedencia.     | **Decidido** como objetivo; CRA solo tiene scaffold (`scripts/data_pipeline/main.py:14`).                                            |
| HL7v2 simulado         | Recibir mensajes sintéticos, validar, normalizar y consultar el resultado.       | **Fuera de alcance**; no existe en CRA.                                                                                              |
| Resumen temporal       | Sintetizar fuentes autorizadas de un intervalo como vista con caché invalidable. | **Decidido** como objetivo; la función protegida responde `501 not_implemented` (`supabase/functions/clinical-summary/index.ts:17`). |
| Turnos y handoff       | Gestionar jornadas, RRHH, entregas o permisos dependientes del turno.            | **Fuera de alcance** según ADR-012.                                                                                                  |
| Operación offline      | Sincronizar todo el dominio y resolver conflictos generales.                     | **Fuera de alcance**; solo se decide una outbox acotada para captura pendiente.                                                      |

## Evidencia esperada por capacidad nueva

**Decidido.** Antes de declarar funcional una capacidad futura debe existir:

1. contrato funcional y estados de error;
2. matriz explícita de permisos;
3. modelo de datos y procedencia;
4. recorrido ejecutable desde Flutter;
5. datos exclusivamente sintéticos;
6. prueba automatizada para autorización, privacidad o integridad crítica;
7. protocolo manual para navegación y experiencia de uso;
8. resultado registrado, no solo una expectativa de diseño.

Este orden coincide con la regla de implementación de CRA: permisos, migración/RLS, pruebas, repositorio/modelo y finalmente interfaz (`AGENTS.md:13-18`).

## Qué no demuestra el prototipo

**Fuera de alcance.** Incluso cuando todos los flujos académicos definidos funcionen, el prototipo no demuestra:

- seguridad suficiente para datos clínicos reales;
- cumplimiento legal o certificación institucional;
- interoperabilidad certificada con una FCE o SIH real;
- eficacia clínica o reducción comprobada de eventos adversos;
- disponibilidad, respaldo, observabilidad o recuperación de nivel productivo;
- aceptación por personal clínico sin ejecutar el protocolo correspondiente;
- capacidad de una IA para tomar decisiones clínicas.

La documentación académica existente exige evidencia reproducible antes de considerar validado el prototipo final (`../carer-record/informe/Indice/Verificacion y Validacion/validacion-del-prototipo.tex:18`).

## Criterio de término de la línea base

**Decidido.** La evidencia del baseline permite describirlo como prototipo funcional de consulta clínica de solo lectura, sujeto a sus validaciones documentadas. No debe presentarse como el prototipo completo de captura, integración e IA ni usarse para inferir el estado posterior del código.
