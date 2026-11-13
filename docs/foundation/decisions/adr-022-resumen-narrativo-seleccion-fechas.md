# ADR-022: Resumen narrativo con selección de fechas

- Estado: Aceptada
- Fecha: 2026-11-12
- Alcance: UX y prompting del resumen de periodo
- Sustituye parcialmente: [ADR-021](adr-021-resumen-periodo-persistido.md); parcialmente sustituida por [ADR-023](adr-023-resumen-factual-y-mejora-nota.md)

## Contexto

La experiencia anterior exponía opciones temporales, filtros, preview y detalle navegable, mientras el resultado podía presentarse como listado de fuentes en vez de una narrativa médica continua. La selección debe ser simple y el resultado legible como relato clínico integrado, sin presentar la validación estructural automatizada como evaluación semántica.

## Decisión

La persona selecciona únicamente fechas: el intervalo va desde días pasados completos hasta hoy, que termina en el instante de captura de la generación; se permite seleccionar un solo día. No se ofrecen fuentes, filtros ni hora. Todas las fuentes internas autorizadas disponibles dentro del intervalo se consideran, sin selector de origen. No hay preview visible ni una acción separada para confirmar o iniciar: hay un único botón para generar.

La salida es una narrativa médica continua, integrada y legible en una pizarra; no es un punteo ni un listado de fuentes. La pizarra presenta el resultado en una tarjeta de solo lectura, con estado guardado o pendiente de reintento. Un reintento de guardado conserva UUID y resultado, sin nueva inferencia. Guardar no navega fuera de la pantalla.

El prompt vigente es `period-summary-v3`: contrato JSON de dominio, Unicode-safe y sin envoltura XML. La validación automática comprueba únicamente patrones estructurales; no prueba coherencia, integración clínica ni calidad semántica. Se mantiene la revisión humana y el guardado no la sustituye.

## Límites y relación con ADR-021

Esta ADR sustituye solo las decisiones de ADR-021 sobre selección y presentación en UI, preview y prompt/salida. ADR-021 sigue vigente para persistencia, RLS, permisos, historial inmutable, identidad UUID, retry, proveedor/modelo local, parámetros y runtime, salvo que esta ADR lo indique expresamente. Los snapshots ya guardados bajo el contrato anterior permanecen históricos y no se reinterpretan ni migran como si hubieran sido generados con v3.

Los diez casos sintéticos y el día de 24 eventos son material de evaluación, no garantía de capacidad, calidad ni ajuste al contexto. No se ha ejecutado inferencia nativa: la calidad de v3 no está demostrada. La revisión real en iPhone/simulador sigue pendiente; el intento de apertura del simulador permanece fallido/abierto.

## Consecuencias

- La selección y el resultado priorizan una acción y una lectura narrativa, sin controles de fuentes, filtros, horas ni preview.
- La evaluación debe distinguir patrones estructurales de calidad semántica, evaluar integración/relato y mantener revisión humana y safety gates.
- [ADR-021](adr-021-resumen-periodo-persistido.md) conserva el contrato persistente y el contexto histórico previo; su mención de `period-summary-v2` describe el antecedente y queda sustituida para nuevas generaciones por v3.
- La validación de presentación y narrativa en dispositivo queda pendiente; no se infiere calidad nativa a partir de tests automatizados.
