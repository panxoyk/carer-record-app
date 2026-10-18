// Uses the secure-storage platform interface to substitute deterministic local storage.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/context_note/data/draft_vault.dart';

class MemorySecureStorage extends FlutterSecureStoragePlatform {
  final values = <String, String>{};
  Future<void> Function(String key)? beforeDelete;

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async => values[key];
  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async => values;
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async => values[key] = value;
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    await beforeDelete?.call(key);
    values.remove(key);
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async => values.containsKey(key);
  @override
  Future<void> deleteAll({required Map<String, String> options}) async =>
      values.clear();
}

void main() {
  late MemorySecureStorage storage;
  late FlutterSecureStoragePlatform previous;
  setUp(() {
    previous = FlutterSecureStoragePlatform.instance;
    storage = MemorySecureStorage();
    FlutterSecureStoragePlatform.instance = storage;
  });
  tearDown(() => FlutterSecureStoragePlatform.instance = previous);

  test(
    'capture registry exists before transcript and purge waits for deletion',
    () async {
      final gate = Completer<void>();
      var deletionStarted = false;
      final vault = DraftVault(
        storage: const FlutterSecureStorage(),
        deleteRecording: (_) async {
          deletionStarted = true;
          await gate.future;
        },
      );
      await vault.registerCapture('op', '/private/capture.wav');
      expect(await vault.pendingRecordingPath('op'), '/private/capture.wav');
      expect(await vault.readDraft('op'), isNull);
      await vault.putDraft(
        'op',
        transcription: 'draft',
        recordingPath: '/private/capture.wav',
      );
      final purging = vault.purge('op');
      await Future<void>.delayed(Duration.zero);
      expect(deletionStarted, isTrue);
      expect(await vault.pendingRecordingPath('op'), '/private/capture.wav');
      gate.complete();
      await purging;
      expect(await vault.pendingRecordingPath('op'), isNull);
    },
  );

  test('missing recording is idempotent', () async {
    final vault = DraftVault(storage: const FlutterSecureStorage());
    await vault.registerCapture('missing', '/missing/capture.wav');
    await vault.purge('missing');
    await vault.purge('missing');
    expect(await vault.pendingRecordingPath('missing'), isNull);
  });

  test('failed recording deletion retains registry for retry', () async {
    final vault = DraftVault(
      storage: const FlutterSecureStorage(),
      deleteRecording: (_) async => throw StateError('delete failed'),
    );
    await vault.registerCapture('retry', '/private/capture.wav');
    await expectLater(vault.purge('retry'), throwsStateError);
    expect(await vault.pendingRecordingPath('retry'), '/private/capture.wav');
  });

  test(
    'purgeAll deduplicates known ids and ignores unknown prefixed keys',
    () async {
      var deletes = 0;
      final vault = DraftVault(
        storage: const FlutterSecureStorage(),
        deleteRecording: (_) async => deletes++,
      );
      await vault.registerCapture('same', '/private/capture.wav');
      storage.values['cra.dictation.unknown.same'] = 'untouched';
      await vault.purgeAll();
      expect(deletes, 1);
      expect(storage.values['cra.dictation.unknown.same'], 'untouched');
    },
  );
}
