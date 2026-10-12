# ADR-005: Permisos configurables

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: autorización de negocio clínica y administrativa

## Contexto

Hoy la autorización clínica está codificada en SQL: tres roles activos pueden leer y el administrador no (`supabase/migrations/20260910100000_patient_read_access.sql:10-23`). Ese modelo es adecuado para el baseline, pero no permite cambiar capacidades de forma auditable sin migración ni expresar permisos por operación o ámbito.

## Decisión

Evolucionar hacia un catálogo cerrado de permisos configurables, aplicado por RLS. Los nombres de permiso y su semántica siguen versionados en código. Cada organización define roles, combina permisos del catálogo y los asigna a membresías con alcance inicial de organización o unidad. La ausencia de asignación deniega. Estado suspendido y restricciones de ámbito prevalecen sobre cualquier grant.

La configuración solo puede ser modificada por una autoridad administrativa explícita, con validación para impedir autoelevación y auditoría. La UI consume decisiones, pero no las impone. [ADR-013](adr-013-acceso-clinico-por-asignacion.md) complementa esta decisión: adelanta la asignación individual por hospitalización como frontera obligatoria para Personal clínico y define la excepción explícita del Administrador de demo. No se implementa un lenguaje arbitrario de políticas ni permisos configurables por columna.

La subtarea 4.1 implementa las operaciones IAM administrativas en PostgreSQL mediante RPCs `SECURITY DEFINER` autenticadas, idempotentes y auditadas (`20261011290000_iam_administrative_operations.sql`). El alta Edge se verifica en integración local con identidades sintéticas y reset del entorno desechable; esto no amplía permisos ni acredita operación remota/productiva.

La composición de roles es la parte de la configuración que la administración ordinaria puede cambiar. `20261011390000_allow_system_role_permission_composition.sql` separa las dos marcas de la autorización: `protected_kind` sigue bloqueando toda acción, mientras `is_system` —procedencia de un rol entregado por CRA— bloquea renombrar y desactivar pero admite reemplazo de composición. `20261011400000_demote_clinician_role.sql` degrada el rol seed `Personal clínico` a configuración del tenant, para que componerlo, renombrarlo y desactivarlo no dependa de una marca que solo refleja su origen; el Administrador de demo conserva ambas marcas. El permiso reservado `clinical.organization.read` permanece indelegable mediante dos controles independientes. La regla completa está en [05-access-control.md](../05-access-control.md). Flutter aún no expone alta, renombrado ni desactivación de roles.

## Alternativas consideradas

- Mantener roles hard-coded: simple y seguro para el alcance actual, pero rígido.
- Autorización solo por claims JWT: rápida, pero puede quedar obsoleta y complica revocación inmediata.
- Motor externo de políticas: expresivo, pero excesivo para el prototipo y agrega otra frontera crítica.

## Consecuencias

- RLS consulta grants y permisos, no listas de roles embebidas.
- Cambios de configuración no requieren desplegar SQL, pero sí quedan auditados.
- Se necesitan constraints, índices y pruebas combinatorias cuidadosas.
- El catálogo no permite crear permisos arbitrarios desde UI.
- Debe definirse comportamiento de sesiones abiertas y cache de autorización.

## Riesgos

- Explosión de combinaciones y configuración incoherente.
- Un grant amplio puede exponer todos los pacientes si no existe ámbito.
- Dependencias recursivas de RLS o degradación de consultas.
- Confundir “configurable” con “sin gobernanza”.

## Evidencia

- `supabase/migrations/20260910010000_auth_administration.sql:12-32` separa autoridad administrativa.
- `supabase/migrations/20260910100000_patient_read_access.sql:3-23` implementa la matriz clínica estática.
- `supabase/tests/patients_rls.test.sql:56-130` prueba roles, administrador y suspendido.
- `supabase/tests/patients_rls.test.sql:56-169` documenta la matriz de solo lectura capturada en el baseline.
- `supabase/migrations/20261011290000_iam_administrative_operations.sql` implementa las operaciones IAM auditadas e idempotentes; `20261011300000_harden_iam_role_delegation_and_signatures.sql` endurece la delegación.
- `supabase/tests/iam_administration_phase4.test.sql` prueba composición, rechazo del permiso no delegable y denegaciones por tenant, autoasignación y último Administrador.
- `app/lib/domains/users/presentation/roles_permissions_screen_test.dart` prueba la composición en Flutter bajo doble permiso efectivo.

El esquema de permisos, RLS, administración, auditoría y pgTAP existen en el repositorio; la evidencia de ejecución se registra en [evidence-index.md](../appendices/evidence-index.md). La evidencia es de demo sintética/local: no acredita producción ni concurrencia de dos sesiones. La invalidación de sesión/caché tras una revocación continúa como pregunta de implementación, pero no cambia el modelo aprobado.
