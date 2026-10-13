import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/context_note.dart';

/// Writes confirmed bitácora milestones to Supabase. RLS is the authority:
/// the `context_notes` policies re-check active membership, `context.note.*`
/// permissions and episode scope before any row is persisted.
///
/// There is no audio upload path. ADR-016 withdrew the stored-audio provision:
/// the recording and its raw transcription are local artifacts and never reach
/// this client, so the write is a single insert with the confirmed text and its
/// non-sensitive provenance.
class ContextNoteRepository {
  ContextNoteRepository(this._client);

  final SupabaseClient _client;

  static const int maxTextLength = 20000;

  /// Publishes one milestone the author already confirmed.
  Future<void> saveMilestone(ContextNoteMilestone milestone) async {
    final text = milestone.content?.trim() ?? '';
    if (text.isEmpty || text.length > maxTextLength) {
      throw const FormatException(
        'El hito debe tener entre 1 y 20000 caracteres.',
      );
    }
    final transcription = milestone.transcription;
    if (milestone.inputMethod == MilestoneInputMethod.audio &&
        transcription == null) {
      throw const FormatException(
        'El hito de audio necesita la procedencia de la transcripción local.',
      );
    }
    await _client.from('context_notes').insert({
      'organization_id': milestone.organizationId,
      'hospitalization_id': milestone.hospitalizationId,
      'patient_id': milestone.patientId,
      'input_method': milestone.inputMethod.wire,
      'content': text,
      if (transcription != null)
        'transcription_metadata': transcription.toJson(),
      'client_event_id': milestone.clientEventId,
    });
  }
}
