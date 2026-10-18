import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../domain/dictation_audio.dart';

/// Owns every temporary artifact of an in-flight dictation and deletes it when
/// the flow ends (ADR-016 decision 7, ADR-010).
///
/// Recordings are ordinary files inside the application sandbox, which the
/// platform already protects per app and keeps out of shared storage. The small
/// text artifacts — the transcription draft, the pending outbox entry and the
/// expiry ledger — go through the platform's encrypted storage instead, so a
/// file listing or a device backup never exposes them in the clear.
class DraftVault implements DictationArtifacts {
  DraftVault({
    FlutterSecureStorage? storage,
    Future<void> Function(String path)? deleteRecording,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _deleteRecording = deleteRecording ?? _deleteRecordingDirectory;

  static const String _transcriptionKey = 'cra.dictation.transcription.';
  static const String _outboxKey = 'cra.dictation.outbox.';
  static const String _recordingPrefix = 'cra_dictation_';
  static const String _expiryPrefix = 'cra.dictation.expiresAt.';

  /// Local security TTL: a capture pending for longer than this is swept.
  static const Duration pendingLifetime = Duration(hours: 24);

  final FlutterSecureStorage _storage;
  final Future<void> Function(String path) _deleteRecording;

  static Future<void> _deleteRecordingDirectory(String path) async {
    final directory = File(path).parent;
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  /// Registers a capture before the recorder writes its first byte.
  @override
  Future<void> registerCapture(String operationId, String recordingPath) async {
    await _storage.write(
      key: '$_expiryPrefix$operationId',
      value: DateTime.now().add(pendingLifetime).toIso8601String(),
    );
    await _storage.write(key: '$_outboxKey$operationId', value: recordingPath);
  }

  /// Stores the transcribed draft and registers when it must be swept.
  @override
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
  /// Missing artifacts are idempotent. I/O failures are propagated so callers
  /// can report cleanup failure and the registry can be retried. Callers run it on confirm, discard, sign-out,
  /// failure and expiry.
  @override
  Future<void> purge(String operationId, {String? recordingPath}) async {
    final registered = await _storage.read(key: '$_outboxKey$operationId');
    final path = recordingPath ?? registered;
    if (path != null && path.isNotEmpty) {
      // Keep the encrypted registry until filesystem deletion succeeds. Missing
      // directories are already clean and therefore idempotent.
      await _deleteRecording(path);
    }
    for (final key in [
      '$_transcriptionKey$operationId',
      '$_outboxKey$operationId',
      '$_expiryPrefix$operationId',
    ]) {
      await _storage.delete(key: key);
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
    final operationIds = <String>{};
    for (final key in entries.keys) {
      for (final prefix in [_transcriptionKey, _outboxKey, _expiryPrefix]) {
        if (key.startsWith(prefix) && key.length > prefix.length) {
          operationIds.add(key.substring(prefix.length));
          break;
        }
      }
    }
    for (final operationId in operationIds) {
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
