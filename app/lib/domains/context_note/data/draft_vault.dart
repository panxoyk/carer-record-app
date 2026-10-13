import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Owns every temporary artifact of an in-flight dictation and deletes it when
/// the flow ends (ADR-016 decision 7, ADR-010).
///
/// Recordings are ordinary files inside the application sandbox, which the
/// platform already protects per app and keeps out of shared storage. The small
/// text artifacts — the transcription draft, the pending outbox entry and the
/// expiry ledger — go through the platform's encrypted storage instead, so a
/// file listing or a device backup never exposes them in the clear.
class DraftVault {
  DraftVault({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _transcriptionKey = 'cra.dictation.transcription.';
  static const String _outboxKey = 'cra.dictation.outbox.';
  static const String _recordingPrefix = 'cra_dictation_';
  static const String _expiryPrefix = 'cra.dictation.expiresAt.';

  /// Local security TTL: a capture pending for longer than this is swept.
  static const Duration pendingLifetime = Duration(hours: 24);

  final FlutterSecureStorage _storage;

  /// Stores the transcribed draft and registers when it must be swept.
  Future<void> putDraft(
    String operationId, {
    required String transcription,
    required String recordingPath,
  }) async {
    await _storage.write(
      key: '$_transcriptionKey$operationId',
      value: transcription,
    );
    await _storage.write(
      key: '$_expiryPrefix$operationId',
      value: DateTime.now().add(pendingLifetime).toIso8601String(),
    );
    await _storage.write(key: '$_outboxKey$operationId', value: recordingPath);
  }

  /// Reads a pending draft back, for example after the app was killed.
  Future<String?> readDraft(String operationId) {
    return _storage.read(key: '$_transcriptionKey$operationId');
  }

  Future<String?> pendingRecordingPath(String operationId) {
    return _storage.read(key: '$_outboxKey$operationId');
  }

  /// Deletes the recording, the transcription and the outbox entry.
  ///
  /// Idempotent by contract: purging twice, or purging something already gone,
  /// succeeds and never throws. Callers run it on confirm, discard, sign-out,
  /// failure and expiry.
  Future<void> purge(String operationId, {String? recordingPath}) async {
    final registered = await _storage.read(key: '$_outboxKey$operationId');
    for (final key in [
      '$_transcriptionKey$operationId',
      '$_outboxKey$operationId',
      '$_expiryPrefix$operationId',
    ]) {
      await _storage.delete(key: key);
    }
    final path = recordingPath ?? registered;
    if (path == null || path.isEmpty) return;
    // The recording lives in a directory owned by this operation, so removing
    // the directory takes the wav and any decoder scratch file with it.
    final directory = File(path).parent;
    if (directory.existsSync()) {
      unawaited(directory.delete(recursive: true));
    }
  }

  /// Removes every expired operation without opening it. Runs on startup and
  /// before a new dictation, so a crash cannot leave artifacts behind forever.
  Future<int> sweepExpired({DateTime? now}) async {
    final instant = now ?? DateTime.now();
    final entries = await _storage.readAll();
    var removed = 0;
    for (final entry in entries.entries) {
      if (!entry.key.startsWith(_expiryPrefix)) continue;
      final deadline = DateTime.tryParse(entry.value);
      if (deadline != null && deadline.isAfter(instant)) continue;
      await purge(entry.key.substring(_expiryPrefix.length));
      removed++;
    }
    return removed;
  }

  /// Drops every artifact of every operation. Used on sign-out so a shared
  /// device never leaks the previous user's drafts.
  Future<void> purgeAll() async {
    final entries = await _storage.readAll();
    for (final key in entries.keys) {
      if (!key.startsWith('cra.dictation.')) continue;
      final operationId = key
          .substring('cra.dictation.'.length)
          .replaceFirst('transcription.', '')
          .replaceFirst('outbox.', '')
          .replaceFirst('expiresAt.', '');
      await purge(operationId);
    }
  }

  /// Sandbox directory that owns every artifact of one dictation operation.
  static Directory recordingDirectory(String root, String operationId) =>
      Directory('$root${Platform.pathSeparator}$_recordingPrefix$operationId');

  /// Stable, non-identifying name for a recording inside the sandbox.
  static String recordingFileName(String operationId) =>
      '$_recordingPrefix$operationId.wav';
}

/// Builds a fresh operation id without pulling a UUID dependency into the vault.
String newDictationOperationId() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}
