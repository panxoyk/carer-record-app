# ADR-015: Hitos de bitácora como notas de contexto en texto o audio almacenado

- Estado: Aceptada
- Fecha: 2026-10-12
- Alcance: hitos publicados por usuarios en la bitácora de una hospitalización; persistencia y acceso al audio crudo de hitos de audio
- Relación: sustituye en parte a ADR-006 y ADR-010 (reglas de no subida y no persistencia remota) para el audio de hitos confirmados; el flujo experimental de dictado con ASR/NER (ADR-007/008/009) queda sin cambios; depende de ADR-005, ADR-013 y ADR-014

## Contexto

La bitácora (timeline clínico) solo proyectaba eventos generados por el sistema. Se decidió permitir que el personal autorizado registre hitos propios por episodio, en texto o como grabación de audio corta. El catálogo de permisos ya define `context.note.read/create/confirm/correct` y el modelo objetivo ya separa la nota de contexto confirmada del `clinical_events` reconstruible. El flujo experimental de dictado (ADR-006/007/010) permanece bloqueado en el spike de ASR local y prohíbe subir audio, por lo que el hito de audio necesitaba una decisión explícita propia.

## Decisión

1. Un hito es una fila `context_notes` confirmada por organización y hospitalización, publicada en un solo paso con `status = 'confirmed'` e `input_method` `text` (contenido no vacío, hasta 20000 caracteres) o `audio` (`storage_path` y `audio_duration_ms` obligatorios). El cliente genera `client_event_id` (único por organización, `context_notes_client_event_unique`) para garantizar idempotencia ante reintentos.
2. El audio de un hito se almacena crudo (m4a/AAC-LC) en el bucket privado `context-note-audio` bajo `<hospitalization_id>/<client_event_id>.m4a` y se reproduce con URL firmada de 120 s. Con esta excepción acotada se sustituyen la regla de no subida de ADR-006 y la de no persistencia remota de ADR-010 para esta categoría: el audio de un hito confirmado forma parte del registro publicado y persiste mientras exista el hito. El flujo experimental de dictado conserva ADR-006/007/008/010 intactas: su audio nunca sale del dispositivo.
3. Publicar exige perfil/membresía activos, `context.note.create` y `context.note.confirm` efectivos y alcance sobre la hospitalización según ADR-013 (permiso concreto más asignación asistencial vigente para Personal clínico; `clinical.organization.read` reservado para el Administrador de demo). RLS es la autoridad de autorización, tanto en `context_notes` como en el bucket; el guard de UI solo reproduce el mismo requisito.
4. Los hitos son inmutables: sin grants de UPDATE/DELETE en runtime sobre `context_notes` y sin políticas RLS de UPDATE/DELETE sobre `storage.objects`. Una corrección es una nota nueva; `context.note.correct` permanece en el catálogo sin flujo propio en este corte.
5. El seed concede `context.note.read/create/confirm` a Personal clínico y al Administrador de demo protegido. Para este último no es una excepción clínica: la regla de delegación efectiva exige que el administrador delegante posea todos los permisos del rol que delega, y por tanto el administrador puede publicar hitos sobre cualquier episodio de la organización.
6. La vista `clinical_timeline_by_hospitalization` integra los hitos confirmados en la bitácora con `source_kind` (`clinical_event`/`context_note`), `kind` ampliada a texto (`milestone`/`milestone_audio`), `audio_storage_path` y `audio_duration_ms`; la vista sigue siendo `security_invoker`/`security_barrier`.
7. La transcripción en el dispositivo del audio de hito es una capacidad futura condicionada a ADR-007; este corte no envía ese audio a ningún servicio.

## Consecuencias

- El audio crudo sale del dispositivo y permanece en un bucket privado: la exposición crece respecto del estado anterior; se acepta con bucket no público, RLS por episodio, URLs firmadas cortas, datos exclusivamente sintéticos y alcance académico (ADR-002).
- El Administrador de demo pasa de lectura a lectura y publicación de hitos (decisión 5); el registro de riesgos documenta ese administrador con capacidad de escritura.
- La app declara `RECORD_AUDIO` y una dependencia de grabación; la subida ocurre solo tras la confirmación explícita del autor y en el folder de su propio episodio.
- La bitácora mezcla eventos clínicos y hitos en un único orden cronológico; la corrección de un hito exige una nota nueva, no una edición.

## Evidencia y límites

- `supabase/migrations/20261012000000_context_note_milestones.sql`: tabla, funciones RLS, bucket, políticas y vista de timeline.
- `supabase/tests/context_notes_milestones.test.sql`: 27 aserciones (estructura, contrato de columnas, alcance, tenant, inmutabilidad, storage, suspendido y sin rol).
- `supabase/seed.sql`: grants `context.note.*` para ambos roles demo.
- `app/lib/domains/context_note/`: contrato tipado, repositorio con URL firmada y UI en la ficha del paciente.
- Pruebas de app: `app/test/domains/patient/presentation/patient_screens_test.dart` (guard, hoja de captura y fila de audio) y `app/test/domains/clinical_event/data/models/clinical_event_model_test.dart` (proyección del timeline).
- Validado solo sobre demo sintética/local; no afirma transcripción, retención productiva, concurrencia ni uso con datos reales.
