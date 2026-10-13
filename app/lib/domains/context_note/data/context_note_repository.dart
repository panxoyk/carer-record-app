import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/entities/context_note.dart';

/// Writes confirmed bitácora milestones to Supabase. RLS is the authority:
/// the `context_notes` policies and the `context-note-audio` storage
/// policies re-check active membership, `context.note.*` permissions and
/// episode scope before any row or audio object is persisted.
class ContextNoteRepository {
  ContextNoteRepository(this._client);

  final SupabaseClient _client;

  static const String audioBucket = 'context-note-audio';
  static const int maxTextLength = 20000;

  /// Publishes one milestone. For `audio`, the local [audioFile] is uploaded
  /// to the private bucket first; if the row cannot be created the object is
  /// removed again so no orphan audio is left behind.
  Future<void> saveMilestone(
    ContextNoteMilestone milestone, {
    File? audioFile,
  }) async {
    if (milestone.inputMethod == MilestoneInputMethod.text) {
      final text = milestone.content?.trim() ?? '';
      if (text.isEmpty || text.length > maxTextLength) {
        throw const FormatException(
          'El hito de texto debe tener entre 1 y 20000 caracteres.',
        );
      }
      await _client.from('context_notes').insert({
        'organization_id': milestone.organizationId,
        'hospitalization_id': milestone.hospitalizationId,
        'patient_id': milestone.patientId,
        'input_method': milestone.inputMethod.wire,
        'content': text,
        'client_event_id': milestone.clientEventId,
      });
      return;
    }

    final storagePath = milestone.audioStoragePath;
    if (storagePath == null || storagePath.isEmpty || audioFile == null) {
      throw const FormatException('El hito de audio no está completo.');
    }
    try {
      await _client.storage
          .from(audioBucket)
          .uploadBinary(
            storagePath,
            await audioFile.readAsBytes(),
            fileOptions: const FileOptions(
              headers: {'Content-Type': 'audio/mp4'},
            ),
          );
      await _client.from('context_notes').insert({
        'organization_id': milestone.organizationId,
        'hospitalization_id': milestone.hospitalizationId,
        'patient_id': milestone.patientId,
        'input_method': milestone.inputMethod.wire,
        'storage_path': storagePath,
        'audio_duration_ms': milestone.audioDurationMs ?? 0,
        'client_event_id': milestone.clientEventId,
      });
    } catch (error) {
      try {
        await _client.storage.from(audioBucket).remove([storagePath]);
      } catch (_) {
        // Best-effort compensation; the original error wins.
      }
      rethrow;
    }
  }

  /// Short-lived URL to play a stored milestone audio object.
  Future<String> signedAudioUrl(String storagePath, {int expirySeconds = 120}) {
    return _client.storage
        .from(audioBucket)
        .createSignedUrl(storagePath, expirySeconds);
  }
}
