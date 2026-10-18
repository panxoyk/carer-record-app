# ADR-017: Síntesis local con modelo en el dispositivo

- Estado: Aceptada
- Fecha: 2026-10-12
- Alcance: generación de texto asistido para notas de contexto y resúmenes de periodo; sustituye íntegramente a ADR-008 y ADR-009
- Relación: **sustituye a** ADR-008 (NER y tokenización reversible) y ADR-009 (síntesis cloud con proveedor abstracto); depende de ADR-006, ADR-007, ADR-010, ADR-011 y ADR-016

## Contexto

ADR-009 decidió invocar un proveedor cloud de síntesis mediante una Edge Function y un adaptador abstracto, limitado a datasets íntegramente sintéticos. ADR-008 añadió tokenización reversible para reducir identificadores antes de ese envío. El objetivo era evitar el acoplamiento del dominio a un SDK de proveedor y limitar el egreso de contenido.

El resultado implementado fue un stub: `supabase/functions/clinical-summary` autentica y responde `501 not_implemented`, sin proveedor. Ninguna parte del pipeline llegó a existir, y el diseño arrastra un coste estructural permanente: Edge Function, proveedor abstracto, contrato de tokens, mapa reversible, validación de integridad, guard de procedencia sintética y `awaiting`-free review, todo para enviar texto fuera del dispositivo.

La disponibilidad de un runtime de inferencia GGUF en el dispositivo (`llamadart`, sobre llama.cpp) cambia la ecuación: el modelo puede residir en el teléfono y el texto nunca necesita cruzar la red. Con ello, la mayor parte de la complejidad defensiva de ADR-008/009 deja de tener objeto.

## Decisión

1. **La síntesis es íntegramente local.** Un modelo GGUF se distribuye o descarga en el dispositivo y se ejecuta on-device. No existe proveedor cloud, ni credenciales de proveedor, ni Edge Function de síntesis, ni salida de texto de notas por la red.
2. **`SynthesisProvider` es el puerto del dominio.** El caso de uso depende de la interfaz, no del runtime. Hay un adaptador GGUF real y un fake determinista para pruebas; cambiar el fake por el adaptador no modifica ningún caso de uso, tests incluidos. El dominio no importa SDK ni tipos del runtime (`ADR-009:13`).
3. **La síntesis es asistencia, nunca un bloqueo.** Si el motor falla, el modelo no está instalado o el caso de uso agota su timeout, el hito se publica directamente con el texto del autor. La asistencia nunca impide escribir la nota clínica.
4. **Se retira la tokenización reversible.** No existe mapa token-valor porque nada sale del dispositivo. ADR-008 queda sustituida íntegramente: la protección ya no es reducir lo enviado, es no enviarlo. El NER local se conserva únicamente como señalización de entidades al autor, sin sustitución de texto ni ningún mapa que custodiar.
5. **`Q-AI-03` deja de ser bloqueante.** La procedencia sintética verificable en runtime era la salvaguarda exigida por ADR-009:15 para impedir que texto real llegara al proveedor. Sin proveedor al que enviar, no hay egreso que verificar en runtime; la ausencia de egreso es la garantía más fuerte disponible y es comprobable por inspección de red.
6. **Se elimina `clinical-summary`.** La Edge Function, su configuración en `supabase/config.toml`, su entrada en los scripts de validación y sus tipos se retiran por completo. Ninguna referencia residual sobrevive en `app/`, `scripts/`, `docs/` ni `.github/`.
7. **El modelo no se commitea.** Sus pesos se distribuyen con descarga explícita y progreso en el primer arranque, o por preinstalación. Un manifiesto versionado registra origen, licencia, versión, checksum y tamaño esperado. La ausencia del modelo no impide publicar texto.
8. **Salida estructurada cuando el modelo la soporte.** El caso de uso controla timeout, cancelación, idempotencia, versión de prompt y de modelo y códigos de error estables. El modelo nunca publica: su salida es un borrador editable que el autor revisa antes de confirmar, igual que la transcripción en ADR-016.
9. **Uso ordenado.** Primero mejora del texto del hito escrito a mano; después NER local para señalar entidades al autor; el resumen de periodo (ADR-011) es la última adición.
10. **El SDK sube como prerrequisito propio.** `llamadart` exige Dart ≥3.10.7 / Flutter ≥3.38.0. La actualización del SDK se ejecuta como cambio aislado con su propia validación completa antes de integrar esta ADR.

### Operación de modelos en la app

La implementación administra transcripción y asistencia de texto como capacidades independientes. En cada arranque comprueba sus archivos y un registro local de verificación asociado a identidad, versión, checksum y ruta; el registro se crea solo después de validar el modelo. La comprobación rápida compara existencia y tamaño, por lo que no detecta corrupción que conserve el tamaño; gestión ofrece verificación completa, limpieza y reinstalación por capacidad. La omisión de la pantalla inicial solo evita descargar durante esa ejecución y no altera la comprobación del siguiente arranque. La instalación comunica etapa y progreso. El resumen de periodo no está expuesto en la app; esta decisión no afirma que esté implementado.

## Alternativas consideradas

- **Mantener el pipeline cloud de ADR-008/ADR-009:** preserva la decisión fundacional y permite comparar proveedores, pero mantiene egreso, credenciales, Edge Function y un mapa reversible que hoy no tiene consumidor.
- **Síntesis local con modelos pequeños o medianos:** suficiente para señalar entidades y estructurar texto, pero con calidad de redacción limitada; se acepta porque el autor siempre revisa.
- **Sin síntesis, solo ASR:** máxima simplicidad, pero no evalúa la hipótesis de asistencia de texto, que es el segundo objetivo académico del prototipo.
- **Síntesis cloud sin tokenización (descartada):** elimina el mapa pero mantiene el egreso, que es justo lo que se decide evitar.

## Consecuencias

- `SynthesisProvider` pasa a ser un puerto local; el adaptador GGUF y el fake siguen la misma interfaz y los mismos códigos de error.
- Se eliminan del modelo de amenazas: custodio del mapa token-valor, validación de integridad de tokens, inversión de entidades, guard de procedencia en runtime y contrato de proveedor en la Edge Function.
- `Q-NER-02` (dónde cifrar el mapa reversible) queda sin objeto y se cierra.
- La app crece en tamaño por pesos del modelo y en consumo de batería, RAM y temperatura; se mide sobre corpus sintético y no se afirma calidad clínica.
- Subir el SDK de Flutter es un cambio transversal del repositorio, con riesgo de romper dominios no relacionados; se aísla en su propio corte.
- La base de código pierde `dart:io`-free portabilidad para síntesis: el runtime GGUF limita las plataformas a las soportadas por `llamadart`.

## Evidencia y límites

- `app/lib/domains/on_device_ai/domain/`: puerto `SynthesisProvider` y contratos de request/response sin tipos del runtime.
- `app/lib/domains/on_device_ai/data/`: adaptador GGUF y fake determinista intercambiables.
- `app/lib/domains/context_note/`: casos de uso y presentación de asistencia permanecen en la feature y nunca bloquean la publicación.
- `app/assets/llm_model_manifest.json`: origen, licencia, versión, checksum y tamaño del modelo; los pesos no se versionan.
- `package.json:29` y `supabase/config.toml`: la función `clinical-summary` deja de existir y los scripts se ajustan en el mismo corte.
- No se afirma calidad de redacción clínica, equivalencia con un proveedor cloud, ni comportamiento con datos reales. La medición se realiza sobre corpus sintético en español clínico y se registra como evidencia de rendimiento, no de utilidad clínica.
