# ADR-006: Captura de audio local y explícita

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: entrada de audio del flujo experimental
- Relación: ADR-015 sustituyó en parte su regla de no subida para el audio de hitos de bitácora confirmados; **ADR-016 reactiva esa regla** al retirar el audio almacenado, y el flujo de dictado pasa de experimental a producción del hito de audio; el resto de la decisión (captura explícita) permanece vigente

## Contexto

El audio clínico puede contener identidad, contexto, voces de terceros y datos imposibles de redactar antes de capturar. Es un activo de alta exposición y la app actual no declara dependencia, permiso ni entidad de audio.

## Decisión

La captura será iniciada y detenida explícitamente por la persona, con indicador persistente, propósito visible, límite de duración/tamaño y manejo de interrupciones. Para el prototipo solo se usarán guiones y voces sintéticas o de participantes autorizados sin datos reales.

El archivo se mantiene en almacenamiento privado local temporal, con nombre opaco y sin backup/sincronización. No se sube a Supabase ni a proveedores. Una interfaz de `AudioCapture` aísla plugins y plataforma del caso de uso. Cada sesión tiene estado y cleanup idempotente gobernado por ADR-010.

## Alternativas consideradas

- Subir audio para procesamiento cloud: reduce requisitos del dispositivo, pero expone el activo más sensible.
- Grabación continua/background: puede mejorar captura, pero es desproporcionada y difícil de consentir.
- No conservar archivo y procesar streaming: minimiza retención, pero puede no ser viable para el spike inicial; se evaluará sin cambiar la regla local.

## Consecuencias

- Se necesitan permisos nativos, almacenamiento privado y pruebas en dispositivos objetivo.
- La UI debe representar grabando, pausado, procesando, error y eliminado.
- El audio no forma parte de la ficha clínica ni del seed remoto.
- ASR consume un stream o archivo local detrás de una interfaz.
- Consentimiento y base jurídica productiva siguen sin resolver.

## Riesgos

- Archivos temporales sobreviven a crash, reinstalación o backup.
- El indicador no refleja una grabación iniciada por el OS/plugin.
- Captura accidental de terceros o notificaciones.
- Metadatos y nombres filtran identidad.

## Evidencia

- `app/pubspec.yaml:10-20` no contenía dependencia de audio ni ASR en el baseline.
- `supabase/migrations/20260910000000_initial_clinical_schema.sql:7-39` no define artefactos de audio.
- ADR-002 y `10-security-privacy.md:5-7` restringen el desarrollo a datos sintéticos y entornos controlados.

La ausencia confirma que esta capacidad no está implementada; no demuestra controles de plataforma.
