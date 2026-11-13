# ADR-021: Resumen de periodo histórico persistido

- Estado: Aceptada
- Fecha: 2026-11-08
- Alcance: MVP de resumen temporal por hospitalización

> **Relación con ADR-022:** Las decisiones históricas de este documento sobre selector UI, preview y prompt/salida fueron sustituidas parcialmente por ADR-022. La selección de fechas, presentación y `period-summary-v2` descritos abajo son el antecedente; para nuevas generaciones rige `period-summary-v3` y la UX definida en ADR-022. Persistencia, RLS, permisos, snapshots, runtime y parámetros de esta ADR permanecen vigentes. Los snapshots existentes conservan su interpretación histórica.

## Contexto

ADR-011 definió un snapshot/cache invalidable. El MVP conserva cada resumen generado como una pieza histórica inmutable, sin presentarlo como fuente clínica ni regenerarlo cuando cambian sus fuentes; no existe un paso de confirmación del autor. La síntesis continúa local conforme a ADR-017; guardar el resultado generado en Supabase persiste texto clínico sensible sujeto a RLS. No se envían fuentes ni prompt a un servicio de IA según la arquitectura implementada, pero la inspección manual de tráfico del dispositivo sigue pendiente.

## Decisión

Cada generación crea un resumen histórico propio, identificado por UUID y asociado al autor, organización, paciente, hospitalización, rango UTC semiabierto exacto y zona IANA institucional. No se edita ni elimina desde la app, no se comparte en una historia común y no se invalida ante eventos posteriores. Consultar el historial o iniciar otra generación son acciones distintas.

Se usa un único permiso `clinical.summary.use` para crear y leer, junto con los permisos clínicos vigentes de las fuentes y el acceso al episodio. Se concede inicialmente a roles clínicos de demo y al administrador; el administrador no recibe override: conserva las mismas restricciones de acceso propio al episodio.

La decisión histórica de UI presentaba historial, creación y detalle como pantallas alcanzables desde el episodio del paciente, nunca modal. Ofrecía ventanas de 6, 12, 24 o 48 horas, 7 días y rango personalizado de fecha/hora, con 24 horas por defecto. Fechas sin hora incluían el día calendario local seleccionado; fuentes sin fecha se excluían y su cantidad se informaba. Filtros opcionales no autorizaban fuentes adicionales. ADR-022 sustituye parcialmente estas decisiones de UX.

Solo se usan notas confirmadas y la timeline FHIR autorizada del episodio. La preparación de fuentes debe ser completa, no truncada ni errónea. El preview descrito históricamente no estimaba tokens ni imponía un límite arbitrario de 1000 bytes; durante generación el adapter cuenta el chat template completo y reserva 512 tokens de salida más un margen de 32 dentro del contexto menor entre manifest y engine (actualmente 2048). Si el conteo no está disponible, el presupuesto no cabe o la finalización no es completa, no se genera ni persiste una respuesta parcial. No se incorpora pipeline de chunks en el MVP. Esta ADR registró `period-summary-v2`, que queda como antecedente: nuevas generaciones usan `period-summary-v3` según ADR-022. Se informa advertencia al generar. Reintentar el guardado reutiliza el mismo UUID y resultado, nunca vuelve a inferir. La cancelación lógica puede descartar un resultado local, sin prometer aborto nativo del motor.

No hay publicación automática como nota, regeneración automática, caché con invalidación, edición ni acción de borrado. Las limitaciones de runtime y cualquier advertencia disponible se presentan al momento de generar.

## Consecuencias

- Se requieren migración aditiva, permiso de catálogo, tabla tipada/RLS y contratos JSON tipados en Flutter.
- El resumen persistido contiene texto generado clínicamente sensible y queda sujeto a RLS por autor/organización/episodio y a la política de retención del entorno.
- ADR-011 permanece como antecedente para intervalo, procedencia y riesgos; quedan sustituidas para este MVP sus decisiones de caché, invalidación, clave de fingerprint e idempotencia de generación.
- El MVP sintético/local está implementado con pruebas automatizadas; benchmark nativo y revisión manual de privacidad/red en dispositivo siguen pendientes.

## Evaluación de calidad pendiente

El corpus sintético y el harness opt-in se alojan en `app/test/domains/period_summary/`, sin alterar el runtime ni sus parámetros. El harness requiere GGUF local verificado por manifest y emplea el adapter real; no instala modelos ni accede a servicios. Los casos especifican señales para revisión humana, no salidas de referencia. La rúbrica y safety gates están en el [flujo de resumen](../flows/period-summary.md#protocolo-de-evaluación-del-resumen). No se ha ejecutado inferencia ni se declara calidad clínica; la validación en iPhone físico sigue pendiente.
