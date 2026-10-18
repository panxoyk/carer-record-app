# Control de acceso

El reemplazo de policies clínicas se implementa en `20261011270000_clinical_rls_contracts.sql` y se endurece en `20261011280000_harden_clinical_runtime_writes_and_views.sql`: lectura exacta por hospitalización, permiso concreto y una de dos rutas (Administrador con `clinical.organization.read` reservado o Personal clínico con `clinical.assigned.read` y asignación vigente). La fila de censo incluye demografía, por lo que acumula `clinical.census.read` y `clinical.patient.read` a través de RLS de `patients`. Las vistas clínicas son `security_invoker`/`security_barrier` y no sustituyen RLS ni grants del invocador. No hay DML clínico runtime en `patients` ni `clinical_events`, incluido `service_role`; `context_notes` sí permite la inserción autorizada de hitos confirmados bajo RLS/RPC, con reconciliación de publicación controlada. Solo propietario/migraciones y bridges `SECURITY DEFINER` controlados escriben las demás tablas clínicas.

## Objetivo

Este documento define el modelo objetivo de autenticación, autorización y Row Level Security (RLS) de CRA. Es normativo para nuevas tablas y flujos, pero distingue expresamente el esquema propuesto de las políticas capturadas en el baseline.

El principio rector es mínimo privilegio con denegación por defecto. Una sesión válida no concede acceso clínico. La autoridad IAM requiere además una organización activa. Para Personal clínico, el usuario debe tener perfil activo, membresía activa en la organización, permisos concretos del catálogo fijo y una asignación asistencial vigente a la hospitalización. Para el Administrador de demo, RLS exige el permiso reservado `clinical.organization.read`, alcance organizacional y el permiso concreto del recurso; no evalúa el nombre ni el ID del rol. Ningún filtro de Flutter, ruta de GoRouter, nombre de rol, organization ID recibido del cliente ni posesión de la clave publishable reemplaza esa evaluación.

La descripción de fases 2.1/2.2 que sigue corresponde al estado histórico previo al reemplazo de policies, no al contrato clínico actual. Fase 2.1 añadió las tablas de hospitalización/asignación y RLS acotada; fase 2.2 añadió RPCs administrativas tipadas, transaccionales, autorizadas e idempotentes y auditoría append-only. El contrato vigente de lectura exacta y DML se describe arriba.

## Evidencia del baseline

Hoy `practitioners` combina perfil, estado y un único rol enum, y su PK es directamente `auth.users.id` (`supabase/migrations/20260910000000_initial_clinical_schema.sql:4-14`, `supabase/migrations/20260910010000_auth_administration.sql:2-5`). Los helpers autorizan por listas de roles globales: un administrador activo administra practitioners y tres roles asistenciales activos leen todos los pacientes (`supabase/migrations/20260910010000_auth_administration.sql:12-32`, `supabase/migrations/20260910100000_patient_read_access.sql:3-23`).

Las políticas capturadas preservan dos contratos que el objetivo conserva:

- una cuenta suspendida pierde acceso;
- administración no implica acceso clínico.

Ambos comportamientos están comprobados por pgTAP (`supabase/tests/practitioners_rls.test.sql:71-107`, `supabase/tests/patients_rls.test.sql:105-130`). El router repite esta separación para UX, pero no es la autoridad (`app/lib/core/router/app_router.dart:28-45`).

El objetivo sustituye el rol global por permisos organizacionales con alcance. No debe interpretarse como descripción de políticas ya migradas.

## Vocabulario de seguridad

| Concepto               | Definición                                                                                                                    |
| ---------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Identidad autenticada  | Usuario de Supabase Auth identificado por `auth.uid()`                                                                        |
| Perfil                 | Persona utilizable por CRA y vinculada de forma única a una identidad Auth                                                    |
| Organización           | Tenant institucional; en la demo corresponde al hospital de demostración                                                      |
| Membresía              | Relación activa o suspendida entre perfil y organización                                                                      |
| Permiso                | Capacidad atómica, estable y versionada por CRA                                                                               |
| Rol                    | Conjunto nombrado de permisos configurado dentro de una organización                                                          |
| Asignación de rol      | Concesión temporal de un rol a una membresía con alcance organizacional o de unidad                                           |
| Unidad                 | Servicio o unidad clínica jerárquica dentro de una organización                                                               |
| Asignación asistencial | Relación individual vigente entre una membresía y una hospitalización; condición obligatoria de lectura para Personal clínico |
| Recurso objetivo       | Fila cuya organización, unidad y hospitalización determinan el alcance exigido                                                |

“Hospital” y “organización” son equivalentes en la frontera de autorización inicial. Si una red sanitaria con varios hospitales necesita un nivel superior, se agregará explícitamente; no se sobrecarga ahora `organization_id` con dos significados.

## Capas de decisión

Una operación se permite solo si supera todas las capas:

```mermaid
flowchart TD
    A[JWT válido y auth.uid disponible]
    B[Perfil activo]
    C[Membresía activa en la organización de la fila]
    D[Asignación de rol vigente]
    E[Rol contiene el permiso fijo requerido]
    F[Alcance cubre organización o unidad]
    G[Restricciones propias de la operación]
    H[Permitir]
    X[Denegar]

    A -->|sí| B
    A -->|no| X
    B -->|sí| C
    B -->|no| X
    C -->|sí| D
    C -->|no| X
    D -->|sí| E
    D -->|no| X
    E -->|sí| F
    E -->|no| X
    F -->|sí| G
    F -->|no| X
    G -->|cumple| H
    G -->|no cumple| X
```

Para Personal clínico, la asignación individual agrega una condición obligatoria y más estrecha, no una excepción informal: debe coexistir con `clinical.assigned.read` y el permiso específico del recurso. El alcance organizacional o de unidad del rol no abre una ruta alternativa. El Administrador de demo es la única excepción inicial: RLS exige `clinical.organization.read` reservado, alcance organizacional y el permiso específico; la administración ordinaria no puede conceder ni copiar ese permiso.

## Catálogo fijo de permisos

Los códigos son contratos de aplicación: solo una migración versionada de CRA puede agregarlos, retirarlos o cambiar su semántica. Una organización puede decidir qué permisos componen sus roles, pero no crear códigos arbitrarios.

### Identidad y estructura

| Código                  | Operación protegida                                 | Observación                                       |
| ----------------------- | --------------------------------------------------- | ------------------------------------------------- |
| `iam.membership.read`   | Listar perfiles y membresías de la organización     | No incluye datos clínicos                         |
| `iam.membership.manage` | Invitar, activar, suspender y actualizar membresías | Operación privilegiada mediante Edge Function/RPC |
| `iam.role.read`         | Leer roles, permisos y asignaciones                 | No concede uso de esos permisos                   |
| `iam.role.manage`       | Crear roles locales y componerlos desde el catálogo | No puede modificar el catálogo                    |
| `iam.role.assign`       | Asignar o revocar roles y alcances                  | Impide autoelevación mediante reglas adicionales  |
| `org.unit.read`         | Consultar unidades                                  | Necesario para navegación y selección de alcance  |
| `org.unit.manage`       | Crear, actualizar, cerrar o reparentar unidades     | Debe preservar jerarquía y tenant                 |

La vista Flutter de composición requiere ambos permisos efectivos, `iam.role.read` y `iam.role.manage`. Esto también habilita a cualquier rol futuro que posea ambos; no hay excepción por nombre o UUID. La interfaz filtra el catálogo a permisos activos ordinarios que el actor posee, pero la RPC `replace_iam_role_permissions` es la autoridad y revalida actor, membresía/tenant, rol ordinario, estado y pertenencia/delegabilidad de cada permiso en la transacción. La UI no concede ni sustituye autorización RLS.

### Consulta clínica

| Código                             | Operación protegida                                                   | Alcance evaluado                                                                           |
| ---------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
| `clinical.census.read`             | Listar hospitalizaciones y ubicación vigente                          | Personal clínico: hospitalización asignada; Admin demo: organización con permiso reservado |
| `clinical.patient.read`            | Ver demografía mínima del paciente vinculada a un episodio autorizado | Derivado de hospitalización accesible                                                      |
| `clinical.patient.identifier.read` | Ver identificadores completos no incluidos en la demografía mínima    | Hospitalización accesible; la vista ordinaria puede enmascararlos                          |
| `clinical.timeline.read`           | Ver `clinical_events`                                                 | Hospitalización; la unidad no restringe Personal clínico en demo                           |
| `clinical.condition.read`          | Ver condiciones/diagnósticos                                          | Hospitalización                                                                            |
| `clinical.medication.read`         | Ver solicitudes de medicación                                         | Hospitalización                                                                            |
| `clinical.observation.read`        | Ver observaciones y resultados                                        | Hospitalización                                                                            |
| `clinical.procedure.read`          | Ver procedimientos                                                    | Hospitalización                                                                            |
| `clinical.document.read`           | Ver informes y metadatos documentales                                 | Hospitalización; contenido puede exigir control adicional                                  |
| `clinical.provenance.read`         | Ver metadatos de fuente y enlaces de trazabilidad                     | No habilita payload bruto automáticamente                                                  |
| `clinical.assigned.read`           | Condición de acceso individual a hospitalizaciones asignadas          | Se concede a Personal clínico junto con permisos concretos                                 |
| `clinical.organization.read`       | Lectura clínica organizacional reservada                              | Solo rol seed protegido de Administrador de demo; no delegable                             |
| `clinical.assignment.manage`       | Crear, revocar y consultar asignaciones asistenciales                 | Permiso efectivo delegable a roles ordinarios según ADR-014; RPC de servidor auditada      |

### Contexto originado en CRA y operación

| Código                      | Operación protegida                                    | Observación                                             |
| --------------------------- | ------------------------------------------------------ | ------------------------------------------------------- |
| `context.note.read`         | Leer notas de contexto confirmadas                     | Mismo alcance que la hospitalización                    |
| `context.note.create`       | Crear borrador/nota de contexto                        | Escritura futura, no implícita por lectura              |
| `context.note.confirm`      | Confirmar contenido antes de hacerlo visible al equipo | Conserva autor y versión                                |
| `context.note.correct`      | Sustituir una nota mediante corrección trazable        | No edita historial destructivamente                     |
| `audit.read`                | Consultar auditoría de la organización                 | Restringido y separado de administración ordinaria      |
| `integration.source.read`   | Ver fuentes y estado de sincronización                 | No revela secretos                                      |
| `integration.source.manage` | Configurar/desactivar fuentes                          | Edge Function; secretos fuera de tablas expuestas       |
| `integration.run.read`      | Consultar ejecuciones y errores sanitizados            | Sin payload clínico bruto salvo permiso separado futuro |

No existe un permiso “superusuario” implícito. Service Role es una capacidad técnica de servidor y no un rol de negocio.

## Roles configurables por hospital

`roles` pertenece a una organización y contiene nombre, descripción y estado. `role_permissions` lo relaciona con el catálogo fijo. CRA puede sembrar plantillas sugeridas, pero una organización puede renombrarlas, clonarlas y ajustar su composición.

La demo siembra esta composición mínima normativa para la primera entrega:

| Rol local        | Permisos de primera entrega                                                                                                                                                                                                                                                                            | Regla de autorización                                                                                                                                             |
| ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Administrador    | `iam.membership.read`, `iam.membership.manage`, `iam.role.read`, `iam.role.manage`, `iam.role.assign`, `org.unit.read`, `clinical.organization.read`, `clinical.assigned.read`, `clinical.census.read`, `clinical.patient.read`, `clinical.timeline.read`, `clinical.assignment.manage` y `audit.read` | Rol seed protegido con todos los permisos de funcionalidades entregadas; RLS evalúa permiso reservado, permisos concretos y tenant, no nombre/ID; no Service Role |
| Personal clínico | `clinical.assigned.read`, `clinical.census.read`, `clinical.patient.read` y `clinical.timeline.read`                                                                                                                                                                                                   | Cada lectura exige además una `care_assignment` vigente a la hospitalización                                                                                      |

`clinical.assigned.read` también pertenece al Administrador protegido como parte de la composición completa de funcionalidades entregadas. Por sí solo no concede filas al Administrador: RLS exige `clinical.organization.read` reservado para su ruta organizacional, y la composición protegida solo cambia mediante migración.

La tabla no reproduce automáticamente el baseline. En las políticas capturadas, physician, nurse y technician tienen exactamente la misma lectura clínica global (`supabase/migrations/20260910100000_patient_read_access.sql:10-48`; `supabase/tests/patients_rls.test.sql:56-130`). En el objetivo, cada hospital elige una composición explícita y comprobable; ningún rol configurable adicional recibe acceso clínico por defecto.

La policy de `public.units` exige exclusivamente `org.unit.read` efectivo en la organización de la fila. Tener membresía activa o permisos clínicos de censo/asignación no habilita la enumeración directa de unidades; Personal clínico asignado sí conserva la lectura autorizada de `hospitalization_locations`, incluidos `unit_id` y cama.

Reglas de administración:

- Un nombre de rol es único dentro de la organización, no global.
- El rol seed Administrador es protegido: no se elimina, desactiva, clona ni modifica por la administración ordinaria. Su permiso `clinical.organization.read` solo puede pertenecer a ese rol y no es delegable ni copiable a un rol clínico ordinario.
- `protected_kind` e `is_system` tienen efectos distintos y no intercambiables. `protected_kind` bloquea toda acción administrativa ordinaria, incluida la composición. `is_system` marca solo la procedencia —un rol entregado por CRA— y bloquea renombrar y desactivar, pero admite reemplazo de composición. Por eso el rol seed `Personal clínico` se degrada a configuración del tenant en `20261011400000_demote_clinician_role.sql`: componer, renombrar y desactivar quedan disponibles durante el onboarding sin tocar la marca que protege al Administrador de demo.
- Un rol desactivado no puede recibir nuevas asignaciones y sus asignaciones vigentes dejan de conceder permisos.
- Nadie puede asignar un permiso que su propia autoridad administrativa no le permita gestionar. Como mínimo, la operación exige `iam.role.assign`; para evitar autoelevación, la función compara el conjunto solicitado con el conjunto delegable definido por política de plataforma. La asignación del rol Administrador protegido es una operación separada, solo ejecutable por otro Administrador efectivo sobre una membresía activa de la misma organización.
- Cambiar la composición de un rol tiene efecto inmediato en RLS y genera auditoría.
- Administración institucional no incluye permisos `clinical.*` ni `context.*` salvo el rol seed protegido de demo definido por ADR-013.
- `clinical.assignment.manage` es delegable a roles ordinarios según ADR-014; el permiso efectivo autoriza la RPC sin conferir acceso clínico. El rol seed protegido sigue siendo su receptor inicial.

## Alcances

### Alcance de organización

Una asignación con `scope_type = organization` cubre todas las unidades y hospitalizaciones de esa organización para los permisos contenidos en el rol. No cruza a otra organización aunque el mismo perfil tenga otra membresía.

Se utiliza para funciones realmente institucionales, por ejemplo administración de membresías o auditoría. Conceder lectura clínica a alcance organizacional es posible, pero debe ser una decisión explícita y excepcional del hospital.

En la primera entrega, esta excepción se limita al permiso reservado `clinical.organization.read` del Administrador de demo definido en ADR-013. Una asignación de rol con alcance organizacional no concede lectura clínica a Personal clínico sin su `care_assignment` vigente.

### Alcance de unidad

Una asignación con `scope_type = unit` referencia una unidad de la misma organización. Cubre la unidad y, si la organización lo configura, sus descendientes. La primera implementación debe elegir una semántica única:

- recomendación: cubrir descendientes mediante una jerarquía materializada/closure table o un path mantenido por servidor;
- alternativa simple: alcance exacto, obligando a asignar cada unidad.

No se debe recorrer recursivamente una jerarquía arbitraria dentro de cada política RLS si eso vuelve impredecible el plan de consulta. La semántica elegida debe materializarse e indexarse.

El alcance de unidad puede restringir operaciones institucionales, pero en esta demo no restringe la lectura de Personal clínico: su única frontera clínica es la `care_assignment` vigente al episodio.

La unidad se conserva para estructura, ubicación y operaciones institucionales, no para limitar lectura clínica de Personal clínico en esta demo. La consulta no puede depender de `patients.care_unit`, que en el baseline era solo texto y no tenía historia (`supabase/migrations/20260910110000_clinical_timeline.sql:1-5`).

### Asignación individual obligatoria para Personal clínico

`care_assignments` relaciona una membresía con una hospitalización, registra vigencia y motivo/rol asistencial opcional. Para Personal clínico, es la frontera ordinaria de lectura: exige además `clinical.assigned.read` y el permiso concreto de la operación. Una asignación no autoriza otro episodio del mismo paciente ni se deduce de unidad, autoría o una consulta previa.

La administración de asignaciones usa RPCs PostgreSQL separadas de concesión y revocación para actores con `clinical.assignment.manage` efectivo sobre datos sintéticos. ADR-014 permite delegar ese permiso a roles ordinarios; el actor se deriva de `auth.uid()` y no puede autoasignarse. La RPC exige elegibilidad y tenant coincidente. La idempotencia serializa por tenant/actor/operación/clave y compara el payload persistido solo tras revalidar organización activa y permiso efectivo. Si la autoridad se revoca, el replay se deniega opacamente sin revelar el resultado/objetivo previo. La clave única impide añadir otra auditoría para ese intento: se conserva el evento original inmutable; una primera denegación resoluble sigue generando su evento. Los conflictos de intervalo se resuelven además mediante la exclusión GiST de la tabla. No forma parte de esta entrega:

- autoasignación o solicitudes de acceso desde la app;
- acceso de emergencia;
- inferencia desde `recorded_by`, autoría de una nota o haber abierto previamente al paciente;
- acceso por asignación vencida o revocada;
- reemplazo del permiso: permiso y asignación deben coexistir.

Una asignación está vigente dentro de `[valid_from, valid_until)`, no está revocada y pertenece a una membresía activa. El alta conserva la lectura histórica mientras se cumpla esa vigencia; una cancelación o invalidación del episodio deniega acceso y una corrección que crea otro episodio no hereda asignaciones. Un traslado mantiene la asignación de la misma hospitalización.

## Matriz de decisión objetivo

| Actor/condición                             | Administración IAM                       | Censo y paciente              | Timeline y recursos clínicos                            | Escritura de contexto                     | Auditoría                             |
| ------------------------------------------- | ---------------------------------------- | ----------------------------- | ------------------------------------------------------- | ----------------------------------------- | ------------------------------------- |
| Anónimo                                     | Denegada                                 | Denegada                      | Denegada                                                | Denegada                                  | Denegada                              |
| Auth sin perfil                             | Denegada                                 | Denegada                      | Denegada                                                | Denegada                                  | Denegada                              |
| Perfil suspendido                           | Denegada                                 | Denegada                      | Denegada                                                | Denegada                                  | Denegada                              |
| Membresía suspendida                        | Denegada en esa organización             | Denegada en esa organización  | Denegada en esa organización                            | Denegada                                  | Denegada                              |
| Administrador sin permiso clínico           | Según permisos IAM                       | Denegada                      | Denegada                                                | Denegada                                  | Según `audit.read`                    |
| Administrador de demo con permiso reservado | Según permisos IAM y operación protegida | Organización de demo          | `clinical.organization.read`, permiso granular y tenant | Denegada                                  | Según `audit.read`                    |
| Personal clínico con alcance de rol         | Sin permiso IAM                          | Denegada sin asignación       | Denegada sin asignación                                 | Denegada                                  | Denegada                              |
| Personal clínico asignado                   | Sin permiso IAM                          | Solo hospitalización asignada | Solo permisos y asignación vigentes                     | Solo si además tiene permiso de escritura | Denegada                              |
| Worker de ingesta                           | Sin sesión humana                        | No usa APIs de usuario        | Escribe solo tablas de ingesta/canónicas autorizadas    | Denegada                                  | Emite auditoría técnica               |
| Service Role                                | Capacidad técnica, no actor de negocio   | Omite RLS                     | Omite RLS                                               | Omite RLS                                 | Debe registrar actor/origen explícito |

## Contrato de RLS

### Principios

1. RLS se habilita en toda tabla de `public` expuesta o potencialmente alcanzable por PostgREST.
2. No tener política es la condición normal para una operación no soportada.
3. Grants y RLS se combinan: un grant no basta y una policy no compensa un grant excesivo.
4. Las policies llaman helpers de autorización estables y acotados; no duplican lógica compleja en decenas de expresiones.
5. Los helpers derivan identidad de `auth.uid()`. Nunca aceptan un `profile_id`, membership ID u organization ID como sustituto de identidad.
6. Toda policy compara el tenant de la fila con el de membresías, roles, unidades y hospitalizaciones relacionadas.
7. Las escrituras validan tanto la fila previa (`USING`) como la nueva (`WITH CHECK`) para impedir mover datos entre tenants o alcances.
8. Los propietarios de tablas y roles de migración no se usan como roles de runtime. Para `patients` y `clinical_events`, ni siquiera `service_role` conserva DML; las guardas rechazan runtime DML si se reintroducen grants. Solo migraciones y bridges `SECURITY DEFINER` controlados/propiedad del owner pueden escribir.
9. Funciones `security definer` fijan `search_path`, califican relaciones y revocan ejecución de `public` y `anon`, siguiendo el endurecimiento vigente (`supabase/migrations/20260912000000_harden_function_privileges.sql:1-56`).

### Predicados conceptuales

No son firmas SQL ni una migración; son contratos de comportamiento:

| Helper conceptual                      | Resultado                                                                                                                                                                                                            |
| -------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `current_profile()`                    | Perfil activo vinculado a `auth.uid()`, o ninguno                                                                                                                                                                    |
| `active_membership(org)`               | Membresía activa del perfil actual en `org`                                                                                                                                                                          |
| `has_permission(org, code)`            | Existe rol/asignación vigente y activa que contiene `code`                                                                                                                                                           |
| `has_org_scope(org, code)`             | El permiso proviene de una asignación organizacional vigente                                                                                                                                                         |
| `has_unit_scope(org, unit, code)`      | El permiso proviene de una asignación que cubre `unit`                                                                                                                                                               |
| `has_care_assignment(hospitalization)` | Existe asignación individual vigente de la membresía actual                                                                                                                                                          |
| `can_access_hospitalization(id, code)` | Administrador demo: tenant, membresía, `clinical.organization.read`, permiso concreto y alcance organizacional; Personal clínico: tenant, membresía, `clinical.assigned.read`, permiso concreto y asignación vigente |

Los helpers deben poder evaluarse con índices por `auth_user_id`, `organization_id`, estado, vigencia, permission code y scope. Su uso se validará con `EXPLAIN` sobre volúmenes representativos antes de producción.

## Políticas por familia de tablas

| Familia                          | `SELECT` de usuario                                                                                                   | `INSERT/UPDATE/DELETE` de usuario                                    | Escritor privilegiado                                                          |
| -------------------------------- | --------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| `profiles`                       | Propio perfil; administradores ven perfiles unidos a su organización con `iam.membership.read`                        | Propio perfil no cambia estado/autoridad; administración vía función | Edge Function de identidad                                                     |
| `organizations`, `units`         | Membresía activa y permisos de estructura cuando corresponda                                                          | Sin DML directo salvo RPC controlada                                 | Administración institucional                                                   |
| Membresías, roles y asignaciones | Permisos IAM de la misma organización                                                                                 | Sin mutación directa para operaciones que puedan elevar privilegios  | Edge Function/RPC auditada                                                     |
| `permission_catalog`             | Autenticados activos pueden leer códigos necesarios para UI                                                           | Sin DML de tenant                                                    | Migraciones CRA                                                                |
| `patients`                       | Solo si existe al menos una hospitalización accesible; respuesta minimizada                                           | Sin DML runtime, incluso para `service_role`                         | Sin writer runtime autorizado en este corte; owner/migración/bridge controlado |
| `hospitalizations`, ubicaciones  | `clinical.census.read`; Personal clínico además requiere asignación vigente y Admin demo `clinical.organization.read` | Sin DML directo                                                      | Ingesta; futuras operaciones CRA explícitas                                    |
| Tablas clínicas canónicas        | Permiso granular y acceso a la hospitalización                                                                        | Sin DML directo                                                      | Worker/proceso canónico                                                        |
| `context_notes`                  | `context.note.read` y episodio accesible                                                                              | Permisos separados; corrección append-only                           | Usuario bajo RLS/RPC, moderación excepcional                                   |
| `clinical_events`                | `clinical.timeline.read` y episodio accesible                                                                         | Sin DML runtime, incluso para `service_role`                         | Sin writer runtime autorizado en este corte; owner/migración/bridge controlado |
| `source_resources`               | Solo metadatos limitados con `clinical.provenance.read`; payload no expuesto por defecto                              | Ninguna                                                              | Worker de ingesta                                                              |
| `ingestion_runs/errors`          | `integration.run.read` de la organización, con error sanitizado                                                       | Ninguna                                                              | Worker de ingesta                                                              |
| `audit_events`                   | `audit.read` de la organización y filtros definidos                                                                   | Ninguna modificación                                                 | RPCs controladas; append-only                                                  |

### Regla de acceso a paciente

Un paciente no tiene una unidad “actual” universal. RLS permite leer su demografía solo cuando el usuario puede acceder al menos a una hospitalización del paciente en esa organización. Si existe más de una hospitalización, consultar el paciente por ID no debe revelar episodios no autorizados. Las vistas/API deben entregar la demografía junto al episodio autorizado y evitar agregados que infieran actividad en unidades ocultas.

### Regla de acceso a recursos clínicos

Cada recurso clínico consumible referencia una hospitalización. Si una fuente no puede atribuirlo todavía, queda en staging/procedencia y no se publica al timeline hasta una reconciliación segura. Esta regla evita conceder acceso por el mero `patient_id`, que podría abarcar episodios en otras unidades o instituciones.

### Regla de eventos derivados

`clinical_events` repite `organization_id` y `hospitalization_id` para filtrar e indexar, pero esas columnas se derivan de la entidad fuente y deben ser coherentes mediante proyección controlada. RLS exige `clinical.timeline.read` sobre la hospitalización. Nadie obtiene acceso al evento porque figure como `recorded_by`.

## Operaciones privilegiadas

### Creación y administración de usuarios

El patrón vigente de `create-practitioner` separa un cliente del llamador y un cliente Service Role (`supabase/functions/create-practitioner/index.ts:29-45`, `supabase/functions/create-practitioner/index.ts:74-104`). El objetivo conserva esa separación y la amplía:

1. validar método, JWT y payload;
2. resolver organización desde la operación solicitada y comprobar `iam.membership.manage`;
3. crear o invitar en Auth;
4. crear/reutilizar perfil y membresía en forma compensable;
5. asignar roles solo si pertenecen a la organización y son delegables;
6. auditar éxito o fallo sin registrar contraseña;
7. eliminar/compensar una cuenta recién creada si falla el dominio, como intentaba el flujo del baseline.

No se permite que Flutter inserte perfiles, membresías o asignaciones con autoridad arbitraria.

### Bootstrap y continuidad de Administración

El primer Administrador sintético se crea mediante bootstrap controlado junto con la organización de demo, su perfil, membresía activa, rol protegido y permisos seed. La operación para agregar otro Administrador exige que el llamador sea ya un Administrador efectivo en la misma organización y asigna el mismo rol protegido a otra membresía activa; no permite asignarse a sí mismo ni modificar la composición del rol.

Suspender una membresía Administrador, revocar su asignación del rol protegido o retirar cualquiera de los permisos requeridos se resuelve en una transacción que bloquea el conjunto de Administradores efectivos y deniega el cambio si el resultado sería cero. Ninguna validación de Flutter ni posesión de Service Role sustituye esta regla.

El gate local de cierre 5.2 verifica los recorridos HTTP de alta/replay/conflicto y deniega un caller clínico y un JWT Service Role como actor, sin ampliar el catálogo ni la autoridad. El bloqueo concurrente entre dos sesiones del último Administrador permanece como evidencia pendiente; pgTAP no simula esa carrera.

La fase 1 solo protege el bootstrap y deniega DML IAM directo; no expone todavía esa operación transaccional ni afirma implementada la garantía del último Administrador. La operación auditada que la materializa queda para la fase de administración.

### Ingesta

El gateway no usa una sesión humana ni Service Role general. La credencial identifica `organization_id` y `source_system_id`; el servidor ignora esos valores si vienen como autoridad en el body y usa los vinculados a la credencial. El writer de ingesta puede modificar recursos de su fuente, no roles, otras organizaciones ni datos originados en CRA.

### Generación de resúmenes

La Edge Function `clinical-summary` del baseline solo validaba la existencia de un usuario y estaba intencionalmente sin implementar. ADR-017 la retiró: hoy la síntesis corre en el dispositivo y la autorización depende por completo de RLS:

- la app solo sintetiza las filas que RLS ya le devolvió;
- el modelo local no consulta la base de datos y no tiene credenciales de servidor;
- se registra modelo, versión, fuentes, timestamp y actor;
- la salida se marca como generada y revisable;
- el resumen nunca se convierte en fuente clínica ni revela filas fuera de alcance.

## Claims, caché y revocación

Los permisos no se almacenan como fuente de verdad en JWT. Pueden existir claims de UX no autoritativos, pero RLS consulta el estado vigente. Así, suspender una membresía, revocar una asignación o retirar un permiso surte efecto en la siguiente consulta aunque el access token siga criptográficamente válido.

Flutter puede cachear datos de presentación durante una sesión solo bajo una política futura explícita. Al cerrar sesión, cambiar de organización, quedar suspendido o recibir una respuesta de autorización, debe invalidar cachés relacionadas. Ocultar una ruta tras leer el perfil, como hacía GoRouter en el baseline (`app/lib/core/router/app_router.dart:28-45`), sigue siendo útil pero nunca suficiente.

## Auditoría

Se auditan como mínimo:

- altas, invitaciones, activaciones y suspensiones de membresía;
- creación/desactivación de roles y cambios en su composición;
- asignación, revocación y cambio de alcance;
- creación, revocación y fallo de asignaciones asistenciales;
- escrituras y correcciones de contexto CRA;
- configuración y ejecución de fuentes de ingesta;
- uso de funciones privilegiadas y reconstrucción de proyecciones;
- accesos clínicos, según política de cumplimiento definida antes de producción.

La auditoría registra actor Auth, perfil/membresía cuando exista, organización, acción, tipo e ID de objetivo, resultado, instante y correlation ID. No guarda contraseñas, JWT, Service Role keys ni payloads clínicos completos. Es append-only para usuarios; correcciones generan otro evento.

## Pruebas obligatorias

La estrategia canónica exige pgTAP para todo cambio de política, rol, estado u operación de acceso, con caso permitido y denegado ([testing y validación](11-testing-validation.md#pgtap-y-base-de-datos)). Para el modelo objetivo, cada familia debe cubrir al menos:

- anónimo y autenticado sin perfil;
- perfil y membresía activos frente a cada estado suspendido;
- organización A frente a fila de organización B;
- permiso presente frente a ausente;
- rol activo frente a desactivado;
- asignación vigente, futura, vencida y revocada;
- alcance organización, unidad cubierta y unidad ajena;
- administrador sin `clinical.organization.read`, Administrador de demo con permiso reservado y rol clínico ordinario que intenta copiar/delegar ese permiso;
- intento de mover una fila a otra organización mediante `UPDATE`;
- intento de asignar rol/unidad de otra organización;
- Personal clínico asignado/no asignado, vigencia, revocación y múltiples episodios;
- escritor de ingesta limitado a su organización y fuente;
- ausencia de privilegios RPC para `anon` y funciones internas no ejecutables por `authenticated`.

Las pruebas capturadas ofrecen el patrón de identidad simulada mediante `request.jwt.claim.sub`, casos permitidos/denegados y rollback (`supabase/tests/patients_rls.test.sql:1-53`, `supabase/tests/patients_rls.test.sql:56-169`). No deben depender del seed.

## Alternativas descartadas

### Conservar el enum global de roles

Descartado porque impide configuración por hospital, asignaciones múltiples y permisos granulares. También mezcla el nombre organizacional de un rol con la decisión técnica que RLS necesita evaluar.

### Guardar permisos completos en el JWT

Descartado porque retrasa revocaciones, aumenta tamaño y obliga a sincronizar claims con configuración mutable. La identidad viene del JWT; la autoridad vigente viene de PostgreSQL.

### Autorizar solo por `organization_id`

Descartado porque pertenecer a un hospital no significa poder consultar todos sus pacientes. Para Personal clínico se exige permiso y asignación asistencial vigente; el alcance de rol no sustituye esa frontera.

### Conceder acceso a quien registró un evento

Descartado porque autoría y autorización son dimensiones distintas. Un autor que cambia de unidad o queda suspendido no conserva acceso por haber creado una fila.

### Usar exclusivamente Edge Functions para ocultar RLS

Descartado porque centralizaría todo acceso en código con Service Role y haría que un error de función expusiera múltiples tenants. Las Edge Functions coordinan privilegios; RLS protege cualquier camino de datos de usuario.

### Permitir permisos definidos libremente por tenant

Descartado porque RLS no puede interpretar de forma segura cadenas con semántica desconocida y las pruebas dejarían de cubrir el universo autorizado. El catálogo es fijo; las composiciones de rol son configurables.

## Criterios de aceptación

- Una misma identidad puede participar en varias organizaciones sin mezclar roles ni estado.
- Suspender una membresía revoca solo esa organización; suspender el perfil revoca todas.
- Cada rol pertenece a una organización y solo referencia permisos del catálogo fijo.
- Las asignaciones tienen exactamente un alcance organizacional o de unidad y una vigencia comprobable.
- Toda consulta clínica se autoriza a través de una hospitalización y no solo de un paciente.
- El administrador no obtiene datos clínicos sin permisos clínicos deliberados; el Administrador de demo los recibe solo mediante `clinical.organization.read` reservado, permisos concretos, alcance organizacional y RLS.
- Personal clínico solo obtiene datos clínicos con permiso concreto, `clinical.assigned.read` y asignación asistencial vigente; el alcance de rol no la sustituye.
- Las operaciones privilegiadas autentican, autorizan y auditan antes de usar Service Role.
- Las pruebas prueban aislamiento entre tenants, alcance, estado, temporalidad y operaciones de escritura.
