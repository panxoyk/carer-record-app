# ADR-024: Categoría de eventos, profesión del autor y fotos clínicas

- Estado: Aceptada
- Fecha: 2026-11-14
- Alcance: diseño definitivo de la app (prototipo Figma v2). Categoría y profesión de las notas de bitácora, servicio en el censo, lectura de administración de medicamentos y balance hídrico, y fotos de curación (tomadas en la app en Supabase Storage; las del sistema clínico, leídas desde FHIR).
- Relación: complementa ADR-020 (contrato de la pasarela) y ADR-016 (dictado local); sustituye para fotos clínicas la clasificación `D`/`F` de `Media`, `DocumentReference` y `Binary` en `docs/foundation/appendices/fhir-resource-selection.md`.

## Contexto

El diseño definitivo clasifica cada evento de la bitácora (Nota clínica, Signos vitales, Procedimiento, Farmacología, Comunicación, Movilidad, Nutrición, TENS, Rutina), filtra por profesión del autor (Medicina, Enfermería, TENS, Kinesiología, Nutrición), agrupa el censo por servicio y muestra tarjetas de signos vitales, exámenes, horario de medicamentos, balance hídrico y fotos de curación. Nada de eso existía en el modelo.

## Decisión

1. **Categoría elegida por el profesional.** `context_notes.category` (texto con check cerrado, por defecto `nota_clinica`) es escribible solo al insertar. La IA local nunca la propone: el profesional la elige en una lista de botones antes de publicar. La reconciliación idempotente (`context_note_publication_matches`) compara también la categoría.
2. **Profesión del autor como snapshot.** `organization_memberships.profession` (nullable, check cerrado) la administra IAM. Un trigger `security definer` copia la profesión de la membresía activa de `auth.uid()` a `context_notes.author_profession` al insertar; el cliente no puede escribirla.
3. **Bitácora.** `clinical_timeline_by_hospitalization` expone `category`, `author_profession` y `client_event_id` (nulos para `clinical_events`). El `client_event_id` permite asociar una foto a su nota sin exponer `author_id`.
4. **Servicio en el censo.** `private.census_unit_display_name` resuelve `units.display_name` solo si el llamador puede leer el episodio; no se concede `org.unit.read` al personal clínico. Las vistas de censo agregan `unit_display_name`.
5. **Contexto IAM.** `iam_current_context` agrega `profession` y `local_identifier` para Ajustes.
6. **Lectura FHIR ampliada (ADR-020).** La pasarela lee `MedicationAdministration` (búsqueda por `context`) y `DocumentReference` de categoría `clinical-photo`. Cada entrada agrega `value`, `flag` (de `interpretation` o `referenceRange`, sin umbrales propios), `code`, `category`, `administeredAt` y `noteRef`. Secciones nuevas: `administrations` (dosis programadas en `MedicationRequest.dosageInstruction.timing.event`, emparejadas con la administración de la misma orden más cercana dentro de ±3 h) y `photos` (solo metadatos). El episodio agrega `attendingPhysician` (`Encounter.participant` ATND) y `reason` (`reasonCode` o diagnóstico principal). El balance hídrico usa Observations con categoría local `fluid-intake`/`fluid-output`.
7. **Fotos clínicas: las de la app en Supabase Storage, las del sistema clínico en FHIR.**
   - Fotos tomadas en la app (revisión de esta ADR, decisión del equipo): se guardan en el bucket privado `clinical-photos` de Supabase Storage (JPEG/PNG, máximo 5 MB, sin URL pública), junto a la nota a la que pertenecen. La ruta es fija, `<organization_id>/<hospitalization_id>/<client_event_id>.jpg|png`. RLS sobre `storage.objects` solo permite **subir** si el usuario tiene `clinical.document.create`, puede escribir notas en el episodio, el episodio está abierto y existe una nota confirmada **suya** con ese `client_event_id`; **leer** exige el mismo alcance que leer las notas del episodio. No hay políticas de actualización ni borrado: la foto es inmutable como la nota. La bitácora expone `photo_path` por nota.
   - Fotos del sistema clínico: se leen desde FHIR (`DocumentReference` de categoría `clinical-photo` + `Binary`) con `clinical-record`, `purpose: "attachment"` y `documentId`; la pasarela autoriza como `record`, verifica que el documento sea una foto del mismo paciente y encuentro y devuelve `{contentType, dataBase64}`. La app nunca escribe en FHIR.
   - Una foto que falla al subir no revierte la nota publicada: la app ofrece reintentar, y reintentar después de una respuesta perdida es seguro (la ruta ya existe).
   - Motivo de la revisión: nota y foto quedan en el mismo sistema, con las mismas reglas de acceso y sin depender de la pasarela para escribir. Consecuencia: un `db:reset` borra ambas juntas.
8. **Biometría.** El bloqueo con Face ID/huella es una preferencia local del dispositivo (keystore) sobre una sesión ya iniciada; no se guardan contraseñas ni tokens adicionales.

## Consecuencias

- Las notas antiguas sin categoría se muestran como `nota_clinica`.
- El fixture sintético agrega médico tratante, motivo, dosis programadas/administradas, HGT, diuresis, ingresos/egresos y una foto demo (maniquí).
- Pruebas: `supabase/tests/event_category_profession.test.sql` (incluye las políticas de Storage), `fhir_test.ts` (ADR-024), `app/test/domains/fhir_record/data/clinical_attachment_repository_test.dart` y `app/test/domains/figma_v2_flows_test.dart`.
- Riesgo abierto: HAPI local sigue sin autenticación; la app solo lo lee a través de la pasarela.
