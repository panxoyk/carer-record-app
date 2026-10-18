import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carer_record_app/domains/context_note/data/asr_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/local_capability_repository_impl.dart';
import 'package:carer_record_app/domains/context_note/data/llm_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/llm_model_installer.dart';
import 'package:carer_record_app/domains/context_note/domain/local_capability_repository.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const bytes = 'synthetic model bytes';
  final digest = sha256.convert(utf8.encode(bytes)).toString();

  Future<LocalCapabilityRepositoryImpl> repository(
    Directory root, {
    String? checksum,
    String id = 'synthetic-model',
    LlmModelInstaller? writingInstaller,
  }) async => LocalCapabilityRepositoryImpl(
    speech: const AsrModelManifest(
      id: '',
      family: '',
      language: 'es',
      engine: 'test',
      engineVersion: '',
      version: '',
      license: '',
      sourceUrl: '',
      archiveSha256: '',
      archiveBytes: 0,
      parts: {},
      files: [],
      parameters: {},
    ),
    writing: LlmModelManifest(
      id: id,
      runtime: 'test',
      runtimeVersion: '1',
      language: 'es',
      license: 'synthetic',
      sourceUrl: 'https://example.invalid',
      file: 'weights.gguf',
      fileName: 'weights.gguf',
      sha256: checksum ?? digest,
      bytes: bytes.length,
      parameters: const {},
    ),
    speechDirectory: Directory('${root.path}/speech'),
    writingDirectory: Directory('${root.path}/writing'),
    writingInstaller: writingInstaller,
  );

  late Directory root;
  setUp(
    () async => root = await Directory.systemTemp.createTemp('capability-'),
  );
  tearDown(() async => root.delete(recursive: true));

  test(
    'adopts existing synthetic file on first query and saves identity',
    () async {
      final repo = await repository(root);
      await repo.writingDirectory.create(recursive: true);
      await File('${repo.writingDirectory.path}/weights.gguf')
          .writeAsString(bytes);
      expect((await repo.query()).last.status, LocalCapabilityStatus.ready);
      expect(
        await File('${repo.writingDirectory.path}/.verified-model.json')
            .exists(),
        isTrue,
      );
    },
  );

  test(
    'startup uses metadata after one-time adoption; explicit verify hashes',
    () async {
      final installer = CountingInstaller();
      final repo = await repository(root, writingInstaller: installer);
      await repo.writingDirectory.create(recursive: true);
      final file = File('${repo.writingDirectory.path}/weights.gguf');
      await file.writeAsString(bytes);

      expect((await repo.query()).last.status, LocalCapabilityStatus.ready);
      expect(installer.verifyCalls, 1);
      final restarted = await repository(root, writingInstaller: installer);
      expect(
        (await restarted.query()).last.status,
        LocalCapabilityStatus.ready,
      );
      expect(installer.verifyCalls, 1);
      expect(installer.installCalls, 0);

      await file.writeAsString(List.filled(bytes.length, 'X').join());
      expect(await restarted.verify(LocalCapability.textAssistance), isFalse);
      expect(installer.verifyCalls, 2);
    },
  );

  test(
    'restarts from sidecar without requiring network or rehashing',
    () async {
      final repo = await repository(root);
      await repo.writingDirectory.create(recursive: true);
      await File('${repo.writingDirectory.path}/weights.gguf')
          .writeAsString(bytes);
      expect(await repo.verify(LocalCapability.textAssistance), isTrue);
      final restarted = await repository(root);
      expect(
        (await restarted.query()).last.status,
        LocalCapabilityStatus.ready,
      );
    },
  );

  test('different identity cannot adopt same-sized file as ready', () async {
    final repo = await repository(root);
    await repo.writingDirectory.create(recursive: true);
    await File('${repo.writingDirectory.path}/weights.gguf')
        .writeAsString(bytes);
    expect(await repo.verify(LocalCapability.textAssistance), isTrue);
    final changed = await repository(
      root,
      id: 'other-model',
      checksum: sha256.convert(utf8.encode('X' * bytes.length)).toString(),
    );
    expect((await changed.query()).last.status, LocalCapabilityStatus.missing);
  });

  test('truncated file is missing', () async {
    final repo = await repository(root);
    await repo.writingDirectory.create(recursive: true);
    await File('${repo.writingDirectory.path}/weights.gguf')
        .writeAsString('short');
    expect((await repo.query()).last.status, LocalCapabilityStatus.missing);
  });

  test('same-sized corruption invalidates sidecar and stays missing', () async {
    final repo = await repository(root);
    await repo.writingDirectory.create(recursive: true);
    final file = File('${repo.writingDirectory.path}/weights.gguf');
    await file.writeAsString(bytes);
    expect(await repo.verify(LocalCapability.textAssistance), isTrue);
    await file.writeAsString(List.filled(bytes.length, 'X').join());
    expect(await repo.verify(LocalCapability.textAssistance), isFalse);
    expect(
      await File('${repo.writingDirectory.path}/.verified-model.json').exists(),
      isFalse,
    );
    expect((await repo.query()).last.status, LocalCapabilityStatus.missing);
  });

  test('clean removes only selected capability files and sidecar', () async {
    final repo = await repository(root);
    await repo.writingDirectory.create(recursive: true);
    await repo.speechDirectory.create(recursive: true);
    final weight = File('${repo.writingDirectory.path}/weights.gguf');
    await weight.writeAsString(bytes);
    await repo.verify(LocalCapability.textAssistance);
    final speechSidecar = File(
      '${repo.speechDirectory.path}/.verified-model.json',
    );
    await speechSidecar.writeAsString('{}');
    await repo.clean(LocalCapability.textAssistance);
    expect(await weight.exists(), isFalse);
    expect(
      await File('${repo.writingDirectory.path}/.verified-model.json').exists(),
      isFalse,
    );
    expect(await speechSidecar.exists(), isTrue);
  });

  test(
    'clean rejects an installing capability but allows the other capability',
    () async {
      final gate = Completer<void>();
      final started = Completer<void>();
      final repo = await repository(
        root,
        writingInstaller: PausedInstaller(gate, started),
      );
      final installation = repo
          .install(LocalCapability.textAssistance)
          .drain<void>();
      await started.future;
      await expectLater(
        repo.clean(LocalCapability.textAssistance),
        throwsStateError,
      );
      await expectLater(repo.clean(LocalCapability.transcription), completes);
      gate.complete();
      await installation;
    },
  );

  test('clean removes only model-owned temporary files', () async {
    final repo = await repository(root);
    await repo.speechDirectory.create(recursive: true);
    await repo.writingDirectory.create(recursive: true);
    final archive = File('${repo.speechDirectory.path}/.tar.bz2');
    final tar = File('${repo.speechDirectory.path}/.tar.bz2.tar');
    final partial = File('${repo.writingDirectory.path}/weights.gguf.part');
    final other = File('${repo.writingDirectory.path}/other.gguf.part');
    await archive.writeAsString('temporary');
    await tar.writeAsString('temporary');
    await partial.writeAsString('temporary');
    await other.writeAsString('user data');

    await repo.clean(LocalCapability.transcription);
    await repo.clean(LocalCapability.textAssistance);

    expect(await archive.exists(), isFalse);
    expect(await tar.exists(), isFalse);
    expect(await partial.exists(), isFalse);
    expect(await other.readAsString(), 'user data');
  });
}

class PausedInstaller extends LlmModelInstaller {
  PausedInstaller(this.gate, this.started);
  final Completer<void> gate;
  final Completer<void> started;

  @override
  Future<void> install(
    LlmModelManifest manifest,
    Directory target, {
    void Function(LlmDownloadProgress)? onProgress,
    HttpClient? client,
  }) async {
    started.complete();
    await gate.future;
  }

  @override
  Future<bool> isInstalled(LlmModelManifest manifest, Directory target) async =>
      true;
}

class CountingInstaller extends LlmModelInstaller {
  int verifyCalls = 0;
  int installCalls = 0;

  @override
  Future<void> install(
    LlmModelManifest manifest,
    Directory target, {
    void Function(LlmDownloadProgress)? onProgress,
    HttpClient? client,
  }) async {
    installCalls++;
  }

  @override
  Future<bool> isInstalled(LlmModelManifest manifest, Directory target) async {
    verifyCalls++;
    final bytes = await File('${target.path}/${manifest.fileName}')
        .readAsBytes();
    return sha256.convert(bytes).toString() == manifest.sha256;
  }
}
