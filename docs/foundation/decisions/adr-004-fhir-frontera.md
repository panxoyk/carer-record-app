# ADR-004: FHIR como frontera anticorrupción

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: importación e interoperabilidad; no el modelo interno ni la UI

## Contexto

FHIR ofrece recursos y semántica de intercambio, pero sus versiones, perfiles, extensiones y cardinalidades no coinciden necesariamente con un modelo móvil simple. Introducir recursos FHIR directamente en UI y dominio acoplaría toda la aplicación a decisiones externas y haría ambiguas las pérdidas.

## Decisión

FHIR se limita a una frontera de ingesta/adaptación. Un adapter versionado valida recursos y perfiles explícitamente soportados, resuelve referencias y mapea a entidades internas estables. Conserva procedencia e identidad externa suficientes para idempotencia y auditoría, sin convertir `payload` en un depósito opaco de recursos completos.

Cada mapping documenta path fuente, campo destino, transformación, terminología, zona horaria y pérdida aceptada. Recursos inválidos o no soportados entran en cuarentena con razón estable; no se persisten parcialmente de forma silenciosa. No se afirma “compatibilidad FHIR” general.

## Alternativas consideradas

- Usar recursos FHIR como entidades internas: evita mapping inicial, pero filtra complejidad y versionado a todas las capas.
- Guardar JSON completo y consultar dinámicamente: rápido, pero debilita constraints, tipado y evolución.
- Formato propio sin FHIR: simple, pero pierde una frontera de interoperabilidad relevante para la investigación.

## Consecuencias

- Dominio y UI permanecen independientes de SDK y versión FHIR.
- La frontera exige fixtures contractuales y una matriz de mapping.
- Puede haber pérdida deliberada; debe ser visible y probada.
- Reingesta y actualizaciones requieren identidad/versionado de fuente.
- Añadir un perfil es una capacidad explícita, no un efecto accidental.

## Riesgos

- Interpretar incorrectamente perfiles, referencias o terminologías.
- Duplicar pacientes por identidad externa inestable.
- Perder precisión temporal o significado clínico.
- Acumular JSON sin gobernanza bajo presión de demo.

## Evidencia

- `scripts/data_pipeline/main.py:1-15` reserva una entrada para parsing FHIR, pero declara la ingesta diferida.
- `supabase/migrations/20260910000000_initial_clinical_schema.sql:16-39` muestra el modelo interno `patients`/`clinical_events` y sus payloads.
- `app/lib/domains/patient/data/models/patient_model.dart:15-27` mapea filas internas a una entidad, sin tipos FHIR.
- `app/lib/domains/clinical_event/data/models/clinical_event_model.dart:12-21` hace lo mismo para eventos.

No existe aún adapter, matriz de mapping ni prueba FHIR; la decisión es arquitectura objetivo.
