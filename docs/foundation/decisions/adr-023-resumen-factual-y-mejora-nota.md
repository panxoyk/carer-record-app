# ADR-023: Resumen factual y mejora de nota

- Estado: Aceptada
- Fecha: 2026-11-13
- Alcance: opciones de periodo y contrato de presentación/prompt del resumen; prompt de mejora de nota
- Sustituye parcialmente: [ADR-022](adr-022-resumen-narrativo-seleccion-fechas.md)

## Contexto

La evaluación de la narrativa y de la presentación del resumen requiere separar la información factual de la selección temporal y evitar que una síntesis introduzca interpretación clínica. La mejora de nota también debe conservar la autoría del texto y no insertar marca por iniciativa del modelo.

## Decisión

La selección del resumen ofrece ventanas de las últimas 6, 12 o 24 horas, o fechas elegidas manualmente sin horas. El encabezado contiene únicamente el rango en forma legible, sin zona horaria, hora de generación ni advertencias. El cuerpo contiene únicamente una síntesis factual: no incluye introducción ni repite el rango seleccionado, y no añade análisis, interpretación, diagnósticos generados ni recomendaciones. Las fechas clínicas necesarias para comprender hechos documentados se preservan. Un diagnóstico documentado solo se presenta como hecho atribuido a su fuente y sin confirmación por la IA.

La mejora de nota usa el identificador `note-improve.v2`. Su prompt de sistema no añade el texto «Carer Record»; si el autor ya lo escribió, la mejora conserva la marca.

## Límites y relación con ADR-021/022

Esta ADR sustituye parcialmente ADR-022 únicamente respecto de las opciones temporales y la presentación/prompt factual del resumen. ADR-022 conserva las decisiones narrativas no reemplazadas; ADR-021 permanece vigente para persistencia, RLS, permisos, historial inmutable, identidad, retry, proveedor/modelo y runtime. Las demás restricciones de ADR-021/022 permanecen intactas.

La versión de resumen es `period-summary-v4` tanto en el contrato del dominio como en el harness de evaluación. Los snapshots históricos no se reescriben ni se reinterpretan.

## Consecuencias y evidencia pendiente

- Los criterios de evaluación humana verifican rango legible sin metadatos adicionales, salida factual sin repetición del periodo y atribución de diagnósticos documentados.
- La validación estructural y las pruebas de contrato no garantizan calidad clínica ni comportamiento general del modelo.
- La revisión humana con inferencia nativa, la validación en dispositivo y la inspección de red siguen pendientes; el intento fallido de apertura del simulador permanece abierto.
