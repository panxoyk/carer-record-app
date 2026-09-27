# ADR-008: NER y tokenización reversible

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: reducción experimental de identificadores en texto sintético

## Contexto

Una transcripción puede contener identificadores directos e indirectos. Eliminar nombres con expresiones regulares no preserva consistencia ni cubre contexto. A la vez, algunos flujos experimentales necesitan restaurar términos localmente para revisión.

## Decisión

Aplicar NER local y sustituir entidades detectadas por tokens opacos versionados. El mapa reversible se cifra y almacena separado del texto, con acceso mínimo y auditoría. Los tokens son estables dentro de un documento, no globalmente, para reducir correlación. La reversión ocurre solo en entorno local autorizado.

NER y tokenización son reducción de exposición, no anonimización. Tanto texto tokenizado como mapa mantienen clasificación sensible. Para el prototipo, ninguna salida originada en personas reales se envía a nube, aun tokenizada.

## Alternativas consideradas

- Redacción irreversible: minimiza reidentificación, pero impide el flujo reversible requerido.
- Tokens globales deterministas: facilitan correlación, pero amplían daño y seguimiento entre documentos.
- LLM cloud para detectar entidades: potencialmente flexible, pero expone texto antes de protegerlo.
- Solo regex: reproducible, pero insuficiente para variación lingüística y contexto.

## Consecuencias

- Se necesita taxonomía, formato de tokens, versionado, manejo de offsets y corpus sintético.
- El mapa se convierte en secreto de alto impacto y tiene ciclo de vida propio.
- La UI debe mostrar incertidumbre y permitir corrección.
- Cambiar modelo o reglas puede cambiar tokens; la procedencia debe conservarse.
- El proveedor de síntesis nunca recibe mapa ni valores originales.

## Riesgos

- Falsos negativos conservan identidad; falsos positivos destruyen utilidad.
- Texto residual permite reidentificación por contexto.
- Colisiones, tokens manipulados o pérdida del mapa impiden reversión segura.
- Logs o errores pueden filtrar pares token/valor.

## Evidencia

- `app/lib/domains/patient/domain/entities/patient.dart:41-49` solo enmascara RUT para presentación; no procesa texto libre.
- `supabase/migrations/20260910110000_clinical_timeline.sql:45-51` exige un `summary` libre en cada evento.
- `app/lib/domains/clinical_event/domain/entities/clinical_event.dart:19-22` modela ese resumen como texto.

No existe NER, mapa, cifrado ni prueba de reversión. SP-02 y SP-03 son evidencia requerida.
