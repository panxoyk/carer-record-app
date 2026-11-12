# ADR-021: Resumen de periodo histórico persistido

- Estado: Aceptada
- Fecha: 2026-11-08
- Alcance: MVP de resumen temporal por hospitalización

## Contexto

ADR-011 definió un snapshot/cache invalidable. El MVP conserva cada resumen generado como una pieza histórica inmutable, sin presentarlo como fuente clínica ni regenerarlo cuando cambian sus fuentes; no existe un paso de confirmación del autor. La síntesis continúa local conforme a ADR-017; guardar el resultado generado en Supabase persiste texto clínico sensible sujeto a RLS. No se envían fuentes ni prompt a un servicio de IA según la arquitectura implementada, pero la inspección manual de tráfico del dispositivo sigue pendiente.

## Decisión

Cada generación crea un resumen histórico propio, identificado por UUID y asociado al autor, organización, paciente, hospitalización, rango UTC semiabierto exacto y zona IANA institucional. No se edita ni elimina desde la app, no se comparte en una historia común y no se invalida ante eventos posteriores. Consultar el historial o iniciar otra generación son acciones distintas.

Se usa un único permiso `clinical.summary.use` para crear y leer, junto con los permisos clínicos vigentes de las fuentes y el acceso al episodio. Se concede inicialmente a roles clínicos de demo y al administrador; el administrador no recibe override: conserva las mismas restricciones de acceso propio al episodio.

La UI presenta historial, creación y detalle como pantallas alcanzables desde el episodio del paciente, nunca modal. Ofrece ventanas de 6, 12, 24 o 48 horas, 7 días y rango personalizado de fecha/hora, con 24 horas por defecto. Fechas sin hora incluyen el día calendario local seleccionado y se muestran explícitamente sin hora; fuentes sin fecha se excluyen y su cantidad se informa. Filtros opcionales no autorizan fuentes adicionales.

Solo se usan notas confirmadas y la timeline FHIR autorizada del episodio. La preparación de fuentes debe ser completa, no truncada, no errónea y caber dentro del presupuesto conservador del contexto actual de 2048 tokens; en cualquier otro caso no se genera. No se incorpora pipeline de chunks en el MVP. La generación usa el `SynthesisProvider` local. Se informa advertencia al generar. Reintentar el guardado reutiliza el mismo UUID y resultado, nunca vuelve a inferir. La cancelación lógica puede descartar el resultado, sin prometer aborto nativo del motor.

No hay publicación automática como nota, regeneración automática, caché con invalidación, edición ni acción de borrado. Las limitaciones de runtime y cualquier advertencia disponible se presentan al momento de generar.

## Consecuencias

- Se requieren migración aditiva, permiso de catálogo, tabla tipada/RLS y contratos JSON tipados en Flutter.
- El resumen persistido contiene texto generado clínicamente sensible y queda sujeto a RLS por autor/organización/episodio y a la política de retención del entorno.
- ADR-011 permanece como antecedente para intervalo, procedencia y riesgos; quedan sustituidas para este MVP sus decisiones de caché, invalidación, clave de fingerprint e idempotencia de generación.
- El MVP sintético/local está implementado con pruebas automatizadas; benchmark nativo y revisión manual de privacidad/red en dispositivo siguen pendientes.
