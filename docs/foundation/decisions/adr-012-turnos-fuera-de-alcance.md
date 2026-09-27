# ADR-012: Turnos fuera de alcance

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: roadmap académico actual

## Contexto

“Turno” puede significar jornada laboral, asignación de paciente, encuentro clínico, ventana temporal o handoff. Incorporar scheduling y dotación abre reglas laborales, zonas horarias, reemplazos, asistencia, notificaciones y nuevos permisos que no son necesarios para validar ingesta, audio o síntesis.

## Decisión

Excluir gestión de turnos del prototipo: no se crearán calendarios, asignaciones de jornada, asistencia, cobertura, handoff ni permisos derivados de estar “de turno”. Las ventanas de resumen son intervalos temporales explícitos y no entidades de turno. La ubicación del paciente tampoco implica asignación profesional.

Los fixtures pueden mencionar “durante el turno” como texto sintético sin crear semántica de dominio. Cualquier necesidad futura requiere investigación de usuarios y una ADR nueva con modelo, autoridad, zona horaria y privacidad.

La continuidad asistencial y los cambios de turno pueden motivar el problema de producto, pero no habilitan un dominio de scheduling, cierre ni permisos por turno. Los resúmenes de periodo usan intervalos explícitos y configurables sin afirmar que representan jornadas laborales.

## Alternativas consideradas

- Implementar turnos mínimos por fecha: parece simple, pero genera expectativas de autorización y operación.
- Inferir turno desde eventos o ubicación: produce autoridad implícita y ambigua.
- Integrar un sistema institucional: excede alcance y requiere contratos externos.

## Consecuencias

- Los permisos no dependen de horario ni asignación de turno.
- El resumen temporal recibe fechas explícitas.
- UI y esquema evitan términos que sugieran scheduling implementado.
- El prototipo no demuestra continuidad operacional entre equipos.

## Riesgos

- Stakeholders pueden asumir que “timeline” o “durante el turno” implica gestión de turnos.
- Requisitos futuros podrían exigir rediseñar permisos y resumen.
- Sin contexto de asignación, los datos sintéticos no modelan segmentación institucional real.

## Evidencia

- `supabase/migrations/20260910000000_initial_clinical_schema.sql:4-39` define roles, pacientes y eventos, sin entidad de turno.
- `app/lib/domains/patient/domain/entities/patient.dart:13-20` modela ubicación, no asignación de practitioner.
- `supabase/seed.sql:117-140` usa “turno” solo dentro de texto ficticio.
- `baseline/carer-record-app.md:9-13` registra que el baseline se limitaba a usuarios y lectura clínica.

La ausencia actual coincide con la decisión adoptada. Reincorporar turnos, scheduling o handoff exige una ADR sustitutiva y evidencia de usuarios, RRHH y operación institucional.
