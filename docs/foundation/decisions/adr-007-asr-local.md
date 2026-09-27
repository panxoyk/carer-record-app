# ADR-007: ASR local

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: transcripción de audio experimental

## Contexto

Enviar audio a ASR cloud aumenta exposición y dependencia externa. El prototipo necesita evaluar si el reconocimiento en dispositivo puede sostener una demostración en español bajo hardware conocido, sin presentar resultados como dictado clínico validado.

## Decisión

Ejecutar ASR local mediante una interfaz independiente del motor. Audio y texto identificable no salen del dispositivo. El modelo se distribuye o instala con versión y checksum; idioma, parámetros, duración, latencia e incertidumbre se registran sin contenido. No existe fallback automático a cloud.

La transcripción es un borrador editable. Segmentos inciertos deben conservar confianza o marca equivalente cuando el motor la ofrezca. Un spike define dispositivos soportados y presupuesto de RAM, batería, tamaño y real-time factor antes de integrar UI.

## Alternativas consideradas

- ASR cloud: mejor calidad potencial y menor carga local, pero incompatible con minimización del audio para este prototipo.
- Servicio ASR on-premise: controlable, aunque agrega infraestructura que el alcance académico no sostiene.
- Transcripción manual: segura para prototipo, pero no evalúa la hipótesis técnica.

## Consecuencias

- La calidad puede ser menor y dependiente del dispositivo.
- Se requiere gestión de modelos y licencias.
- Los benchmarks se ejecutan con corpus sintético y hardware declarado.
- La capa de dominio no conoce SDK, formato nativo o ruta de modelo.
- Fallar localmente significa informar fallo, no enviar a red.

## Riesgos

- Falsas transcripciones cambian significado clínico.
- Modelo demasiado pesado o lento.
- Licencia incompatible con distribución.
- Telemetría del SDK podría activar egress inadvertido.

## Evidencia

- `app/pubspec.yaml:10-20` no declara motor ASR.
- `baseline/carer-record-app.md` no registra procesamiento de audio en la fotografía inicial.
- `package.json:6-33` no contiene comando de modelos o benchmark ASR.

No existe evidencia de factibilidad. SP-01 y las preguntas `Q-ASR-01`/`Q-ASR-02` deben resolverse antes de elegir motor.
