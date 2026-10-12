# ADR-014: Delegación de gestión de asignaciones asistenciales

- Estado: Aceptada
- Fecha: 2026-10-12
- Alcance: composición de permisos y gestión de asignaciones asistenciales en la organización de demostración
- Relación: complementa ADR-013 y sustituye explícitamente su inciso 8; mantiene vigente el resto de ADR-013

## Contexto

ADR-013 separó `clinical.assignment.manage` de `iam.role.assign`, pero limitó inicialmente su concesión al Administrador protegido y dejó fuera un gestor delegado. La decisión explícita posterior acepta que la gestión sea delegable mediante el permiso efectivo, sin depender del nombre o ID del rol.

## Decisión

1. El rol seed protegido de Administrador conserva `clinical.assignment.manage` como receptor inicial.
2. Un administrador efectivo puede componer un rol ordinario con `clinical.assignment.manage` y asignarlo a una membresía elegible conforme a las reglas ordinarias de composición y asignación. La autoridad depende del permiso efectivo y nunca del nombre/ID del rol.
3. La RPC exige `clinical.assignment.manage` efectivo, tenant coincidente y un target elegible. Al conceder, valida que la membresía target esté activa y sea elegible; al revocar, permite actuar sobre la asignación histórica elegible aunque la membresía ya no esté activa. Valida actor y autorización dentro de la transacción y audita concesiones, revocaciones y denegaciones.
4. No se permite autoasignación. La gestión puede mostrar identificador, estado y fecha de los episodios en su vista administrativa, pero por sí sola no concede lectura de censo clínico general, demografía ni recursos clínicos. Para esos datos se requieren los permisos clínicos correspondientes y RLS.
5. La UI de asignaciones permite varios profesionales asociados a una misma hospitalización. El UUID de episodio siempre está visible y es copiable; el nombre del paciente solo se muestra cuando el actor tiene permisos efectivos `clinical.census.read` y `clinical.patient.read`, y RLS autoriza la fila correspondiente.

## Consecuencias

- Se elimina la excepción por identidad del rol protegido para autorizar la gestión de asignaciones, pero el rol seed protegido permanece como receptor inicial.
- La delegación aumenta el riesgo de cambios asistenciales por actores ordinarios; se acepta con validación SQL transaccional, tenant, elegibilidad, no autoasignación, auditoría y autorización RLS independiente para datos clínicos.
- La decisión no convierte el prototipo sintético/local en un sistema productivo ni amplía el acceso clínico.

## Evidencia y límites

La implementación observada y sus pruebas se documentan en el flujo y la evidencia de fase correspondiente. Esta ADR registra la dirección aceptada y no afirma por sí sola que todo el comportamiento esté implementado o validado.
