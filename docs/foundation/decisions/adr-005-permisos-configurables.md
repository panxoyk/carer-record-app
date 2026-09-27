# ADR-005: Permisos configurables

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: autorización de negocio clínica y administrativa

## Contexto

Hoy la autorización clínica está codificada en SQL: tres roles activos pueden leer y el administrador no (`supabase/migrations/20260910100000_patient_read_access.sql:10-23`). Ese modelo es adecuado para el baseline, pero no permite cambiar capacidades de forma auditable sin migración ni expresar permisos por operación o ámbito.

## Decisión

Evolucionar hacia un catálogo cerrado de permisos configurables, aplicado por RLS. Los nombres de permiso y su semántica siguen versionados en código. Cada organización define roles, combina permisos del catálogo y los asigna a membresías con alcance inicial de organización o unidad. La ausencia de asignación deniega. Estado suspendido y restricciones de ámbito prevalecen sobre cualquier grant.

La configuración solo puede ser modificada por una autoridad administrativa explícita, con validación para impedir autoelevación y auditoría. La UI consume decisiones, pero no las impone. Una futura asignación individual por hospitalización queda contemplada por el modelo, pero no forma parte del primer flujo operativo. No se implementa un lenguaje arbitrario de políticas ni permisos configurables por columna.

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

No hay tablas ni UI de permisos configurables. La invalidación de sesión/caché tras una revocación continúa como pregunta de implementación, pero no cambia el modelo aprobado.
