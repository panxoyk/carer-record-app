# ADR-024: Categoría de eventos, profesión del autor y fotos clínicas en FHIR

- Estado: Aceptada
- Fecha: 2026-11-14
- Alcance: diseño definitivo de la app (prototipo Figma v2). Categoría y profesión de las notas de bitácora, servicio en el censo, lectura de administración de medicamentos y balance hídrico, y escritura acotada de fotos de curación en el servidor FHIR.
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
7. **Fotos clínicas en FHIR, nunca acceso móvil directo.**
   - Escritura: Edge Function `clinical-attachment`, invocada con el JWT del usuario. Autoriza con `fhir_authorized_encounter_write_context`, que exige el permiso nuevo `clinical.document.create`, `can_write_context_note` y un episodio abierto. Valida JPEG/PNG por firma, máximo 5 MB, instante de captura no futuro y claves cerradas. Escribe una transacción `Binary` + `DocumentReference` (etiqueta `HTEST`, `context.encounter`, `context.related` con `urn:carer-record:context-note|<client_event_id>`) y responde solo el id.
   - Lectura: `clinical-record` con `purpose: "attachment"` y `documentId`; autoriza como `record`, verifica que el documento sea una foto del mismo paciente y encuentro, revalida y devuelve `{contentType, dataBase64}`.
   - No hay URLs públicas ni Storage de Supabase. Una foto que falla al subir no revierte la nota publicada: la app ofrece reintentar.
8. **Biometría.** El bloqueo con Face ID/huella es una preferencia local del dispositivo (keystore) sobre una sesión ya iniciada; no se guardan contraseñas ni tokens adicionales.

## Consecuencias

- Las notas antiguas sin categoría se muestran como `nota_clinica`.
- El fixture sintético agrega médico tratante, motivo, dosis programadas/administradas, HGT, diuresis, ingresos/egresos y una foto demo (maniquí).
- Pruebas: `supabase/tests/event_category_profession.test.sql`, `supabase/functions/clinical-attachment/handler_test.ts`, `fhir_test.ts` (ADR-024) y `app/test/domains/figma_v2_flows_test.dart`.
- Riesgo abierto: HAPI local sigue sin autenticación; la escritura de fotos solo ocurre desde la pasarela del servidor.
