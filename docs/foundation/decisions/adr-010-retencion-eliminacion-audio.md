# ADR-010: Retención mínima y eliminación de audio

- Estado: Aceptada
- Fecha: 2026-09-27
- Alcance: audio y derivados temporales del flujo experimental
- Relación: ADR-015 sustituyó en parte su regla de no persistencia remota para el audio de hitos de bitácora confirmados; **ADR-016 reactiva esa regla** al retirar el bucket `context-note-audio`, de modo que no hay retención remota de audio que gobernar; el ciclo de eliminación local permanece vigente

## Contexto

El audio es el activo de mayor exposición del flujo. Conservarlo “por si acaso” amplía impacto, superficie de backup y dificultad de responder a una eliminación. Todavía no se han definido plazos institucionales ni almacenamiento móvil.

## Decisión

Adoptar retención mínima: el audio existe solo mientras sea necesario para ASR local, reproducción y confirmación inmediata del mismo autor. Se elimina al confirmar, descartar o alcanzar el vencimiento de seguridad. No se persiste remotamente ni se incorpora al registro clínico. El plazo máximo de una captura pendiente requiere resolver `Q-PRIV-03` antes de implementación, pero no puede convertirse en retención indefinida.

La eliminación es idempotente y cubre archivo, chunks, buffers, waveform, temporales del motor, trabajos y referencias que permitan recuperar contenido. Primero se bloquean nuevas lecturas, luego se elimina y finalmente se registra resultado sin contenido. Un barrido recupera residuos tras crash.

## Alternativas consideradas

- Conservar indefinidamente: facilita reanálisis, pero es incompatible con minimización.
- Retención fija remota: centraliza control, pero introduce transferencia, backups y autorizaciones fuera de alcance.
- Borrar inmediatamente tras ASR: minimiza más, pero impide al autor escuchar la fuente al revisar la síntesis y se descarta para este flujo.

## Consecuencias

- No se puede reprocesar una muestra eliminada; debe capturarse otra sintética.
- El modelo de estados necesita expiración, deleting, deleted y failed con retry.
- El cleanup se ejecuta en éxito, cancelación, error, startup y vencimiento.
- Backups del dispositivo deben excluir el directorio.
- Auditoría registra hecho, actor/causa y resultado, no audio.

## Riesgos

- APIs del sistema no garantizan borrado físico forense.
- Crash o permisos dejan huérfanos.
- Derivados no inventariados sobreviven al original.
- Plazo ambiguo termina convirtiéndose en retención indefinida.

## Evidencia

- `app/pubspec.yaml:10-20` no incluye almacenamiento/captura de audio.
- `supabase/migrations/20260910000000_initial_clinical_schema.sql:7-39` no persiste audio.
- `AGENTS.md` define la purga de datos reales introducidos por error, pero no sustituye el ciclo específico de audio de esta ADR.

No hay implementación ni prueba de borrado. El TTL máximo de una operación pendiente permanece abierto, pero la eliminación tras confirmar o descartar es vinculante.
