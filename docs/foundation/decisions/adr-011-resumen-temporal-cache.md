# ADR-011: Resumen temporal versionado y caché

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: síntesis de eventos de una ventana temporal

## Contexto

Una síntesis sin ventana, zona horaria o versión de fuentes puede mezclar información y quedar obsoleta. Regenerarla siempre agrega latencia, costo y variabilidad. El timeline actual ordena eventos por `occurred_at` (`app/lib/domains/clinical_event/data/clinical_event_repository.dart:10-16`) pero no define resumen ni cache.

## Decisión

Cada solicitud usa intervalo semiabierto `[desde, hasta)`, zona horaria explícita, paciente, conjunto/versiones de eventos, versión de prompt, modelo y proveedor. El resultado es un `SummarySnapshot` inmutable con procedencia, estado y timestamps; se presenta como derivado experimental, no como evento fuente.

La caché usa una clave derivada de todos esos componentes. Solo un match exacto y no expirado es hit. Una nueva versión de evento, cambio de permiso, eliminación relevante o cambio de modelo/prompt invalida o vuelve inalcanzable la entrada. RLS aplica igual que a la fuente. Se evita incluir texto clínico en la clave o logs.

## Alternativas consideradas

- Regenerar siempre: simple y fresco, pero lento, costoso y no determinista.
- Cachear solo por paciente: rápido, pero devuelve ventanas o versiones incorrectas.
- Guardar resumen como `clinical_event`: reutiliza timeline, pero confunde fuente con derivado y su invalidación.
- Resumen exclusivamente cliente: reduce backend, pero complica autorización compartida, proveedor y auditoría.

## Consecuencias

- Deben normalizarse zona horaria, bordes e identidad de fuentes.
- Cache y snapshot pueden ser la misma tabla solo si se preserva procedencia.
- La UI muestra ventana, generación y estado de actualización.
- Se requieren locks/idempotencia para evitar generación duplicada.
- La retención del resumen se gobierna independientemente del audio.

## Riesgos

- Resumen obsoleto usado como dato vigente.
- Colisión o clave incompleta mezcla pacientes/versiones.
- Invalidación concurrente con una generación.
- Una síntesis omite contexto clínico importante.

## Evidencia

- `supabase/functions/clinical-summary/index.ts:3-18` conserva una frontera autenticada, pero no implementa síntesis.
- `supabase/migrations/20260910000000_initial_clinical_schema.sql:28-39` registra `occurred_at` e índice temporal.
- `supabase/migrations/20260910110000_clinical_timeline.sql:45-51` exige resumen fuente en payload.
- `baseline/carer-record-app.md:123-127` registra que la UI observada no implementaba conversión de zona horaria.

No existe snapshot, cache, invalidación ni permiso asociado; la ADR define el contrato objetivo.
