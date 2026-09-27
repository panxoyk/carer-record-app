# ADR-002: Prototipo académico

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: todas las entregas y afirmaciones del proyecto

## Contexto

El proyecto explora integración clínica, procesamiento local y síntesis, pero carece de controles institucionales, validación clínica, operación, infraestructura y revisión legal necesarios para un producto sanitario. Confundir una demo con un sistema productivo aumentaría el riesgo para personas y evaluación.

## Decisión

Carer Record se declara prototipo académico con datos sintéticos. Su objetivo es demostrar decisiones técnicas, flujos y resultados reproducibles, no atender pacientes, emitir recomendaciones, sustituir una ficha clínica ni acreditar cumplimiento. Toda UI, demo, informe y documentación debe distinguir capacidad implementada, hipótesis, resultado de spike y trabajo futuro.

No se usarán datos reales ni integraciones institucionales hasta completar una puerta independiente de privacidad, seguridad, legalidad y gobernanza. Un resultado de ASR, NER o síntesis se etiqueta como borrador experimental y requiere revisión humana en cualquier evaluación.

## Alternativas consideradas

- Diseñar desde ahora como producto productivo: requiere organización, presupuesto y decisiones regulatorias fuera del alcance académico.
- Prototipo con datos reales controlados: daría mayor realismo, pero introduce riesgos y obligaciones innecesarios para validar arquitectura.
- Mock puramente visual: reduce riesgo, pero no permite evaluar contratos, RLS e idempotencia extremo a extremo.

## Consecuencias

- Se prioriza evidencia reproducible sobre disponibilidad o escala.
- Los proveedores cloud solo reciben fixtures sintéticos.
- Métricas obtenidas no se generalizan a práctica clínica.
- Backups, HA, distribución, certificación y soporte productivo quedan como brechas explícitas.
- El lenguaje evita “seguro”, “cumple”, “anonimizado” o “validado clínicamente” sin evidencia independiente.

## Riesgos

- Una demo convincente puede interpretarse como lista para producción.
- Datos sintéticos pueden ocultar sesgos, ruido y variabilidad reales.
- La restricción reduce validez externa de benchmarks.
- Un colaborador podría importar datos reales por conveniencia.

## Evidencia

- `app/pubspec.yaml:1-4` describe explícitamente un MVP.
- `README.md:100-110` identifica cuentas de demostración.
- `supabase/seed.sql:1-22` marca el seed como desarrollo local y sus pacientes como ficticios.
- `03-scope.md:139-163` deja cumplimiento, datos reales y operación productiva fuera del prototipo académico.

Esta evidencia muestra intención y fixtures sintéticos; no constituye un control automático suficiente contra ingreso accidental de datos reales.
