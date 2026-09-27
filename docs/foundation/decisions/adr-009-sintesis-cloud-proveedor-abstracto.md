# ADR-009: Síntesis cloud mediante proveedor abstracto

- Estado: Aceptada con restricción
- Fecha: 2026-09-27
- Alcance: generación experimental de síntesis; solo datos sintéticos

## Contexto

La síntesis puede requerir capacidades cloud y cambiar de proveedor durante la investigación. Acoplar prompts, errores y modelos al dominio dificulta pruebas, comparación y retiro. Enviar información real, incluso tokenizada, no está autorizado por este prototipo.

## Decisión

Definir un puerto `SynthesisProvider` con requests/responses internos, adapter por proveedor y fake determinista. El caso de uso controla timeout, cancelación, idempotencia, versión de prompt/modelo y códigos de error. El adapter traduce contratos externos y no filtra SDK ni payload al dominio.

La integración cloud solo procesa datasets íntegramente sintéticos con procedencia comprobable. Un guard técnico rechaza procedencia real, desconocida o derivada de una persona. No se envían audio, PHI/IPS, mapas reversibles, secretos ni logs clínicos. Cambiar esta restricción exige una ADR sustitutiva y revisión legal/seguridad.

## Alternativas consideradas

- Llamar al proveedor directamente desde Flutter: simple, pero expone credenciales, contratos y contenido.
- Un único proveedor embebido en Edge Function: rápido, pero dificulta fake, comparación y retiro.
- Síntesis totalmente local: mejor privacidad, pero no necesariamente viable; puede añadirse como adapter tras un spike.
- No usar síntesis: elimina riesgo, pero no evalúa la hipótesis académica.

## Consecuencias

- Edge Function u otro backend controlado custodia credenciales del proveedor.
- Pruebas ordinarias usan fake; sandbox cloud es explícito y sintético.
- Respuesta conserva versión/procedencia y se presenta como borrador.
- Costos, rate limits y retención del proveedor se aíslan en adapter/configuración.
- La abstracción no elimina obligaciones del proveedor ni riesgo de egress.

## Riesgos

- Guard de procedencia omitido o falsificado.
- Adapter registra prompt/respuesta por defecto.
- Cambios del proveedor alteran resultados o seguridad.
- Prompt injection dentro de texto sintético afecta integridad de salida.
- Dependencia de red y costos no acotados.

## Evidencia

- `supabase/functions/clinical-summary/index.ts:3-18` autentica y devuelve 501; la integración está diferida.
- `supabase/config.toml:36-40` exige JWT para esa función.
- `package.json:21-26` solo valida estáticamente Edge Functions; aún faltan tests de contrato.
- ADR-002 y `10-security-privacy.md:5-7` ordenan usar solo datos sintéticos en desarrollo.

No hay proveedor, fake, guard de procedencia ni evaluación contractual implementados.
