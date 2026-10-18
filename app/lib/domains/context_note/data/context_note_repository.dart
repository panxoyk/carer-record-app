import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/context_note.dart';
import '../domain/confirmed_milestone_writer.dart';

/// Writes confirmed bitácora milestones to Supabase. RLS is the authority:
/// the `context_notes` policies re-check active membership, `context.note.*`
/// permissions and episode scope before any row is persisted.
///
/// There is no audio upload path. ADR-016 withdrew the stored-audio provision:
/// the recording and its raw transcription are local artifacts and never reach
/// this client, so the write is a single insert with the confirmed text and its
/// non-sensitive provenance.
class ContextNoteRepository implements ConfirmedMilestoneWriter {
  ContextNoteRepository(SupabaseClient client)
    : _remote = SupabaseContextNoteRemote(client);

  ContextNoteRepository.withRemote(this._remote);

  final ContextNoteRemote _remote;

  static const int maxTextLength = maxMilestoneTextLength;

  /// Publishes one milestone the author already confirmed.
  @override
  Future<void> saveMilestone(ContextNoteMilestone milestone) async {
    final text = milestone.content?.trim() ?? '';
    if (text.isEmpty || text.length > maxTextLength) {
      throw const FormatException(
        'El hito debe tener entre 1 y 20000 caracteres.',
      );
    }
    final transcription = milestone.transcription;
    if (milestone.inputMethod == MilestoneInputMethod.text &&
        transcription != null) {
      throw const FormatException(
        'Un hito de texto no puede incluir procedencia de transcripción.',
      );
    }
    if (milestone.inputMethod == MilestoneInputMethod.audio &&
        transcription == null) {
      throw const FormatException(
        'El hito de audio necesita la procedencia de la transcripción local.',
      );
    }
    final payload = Map<String, Object?>.unmodifiable({
      'organization_id': milestone.organizationId,
      'hospitalization_id': milestone.hospitalizationId,
      'patient_id': milestone.patientId,
      'input_method': milestone.inputMethod.wire,
      'content': text,
      if (transcription != null)
        'transcription_metadata': transcription.toJson(),
      'client_event_id': milestone.clientEventId,
    });
    try {
      await _remote.insert(payload);
    } catch (error, stackTrace) {
      try {
        if (await _remote.publicationMatches(payload)) return;
      } catch (_) {
        // Preserve the original insert failure when reconciliation is unavailable.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}

abstract interface class ContextNoteRemote {
  Future<void> insert(Map<String, Object?> payload);
  Future<bool> publicationMatches(Map<String, Object?> payload);
}

class SupabaseContextNoteRemote implements ContextNoteRemote {
  SupabaseContextNoteRemote(this.client);
  final SupabaseClient client;

  @override
  Future<void> insert(Map<String, Object?> payload) async {
    await client.from('context_notes').insert(payload);
  }

  @override
  Future<bool> publicationMatches(Map<String, Object?> payload) async {
    final bool result = await client.rpc(
      'context_note_publication_matches',
      params: {
        'p_organization_id': payload['organization_id'],
        'p_hospitalization_id': payload['hospitalization_id'],
        'p_patient_id': payload['patient_id'],
        'p_input_method': payload['input_method'],
        'p_content': payload['content'],
        'p_transcription_metadata': payload['transcription_metadata'],
        'p_client_event_id': payload['client_event_id'],
      },
    );
    return result == true;
  }
}
