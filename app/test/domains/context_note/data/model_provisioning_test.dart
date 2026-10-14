import 'dart:io';

import 'package:carer_record_app/domains/context_note/data/asr_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/llm_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/model_provisioning.dart';
import 'package:flutter_test/flutter_test.dart';

/// The manifests pin origin, licence, version and digests; these tests pin the
/// behaviour that makes a fresh clone usable without a committed blob.
///
/// Sizes here are deliberately tiny: the provisioner only compares lengths, so
/// the real 1.3 GB would buy nothing but a full disk.
const _speech = AsrModelManifest(
  id: 'sherpa-onnx-whisper-base',
  family: 'whisper',
  language: 'es',
  engine: 'sherpa_onnx',
  engineVersion: '1.13.8',
  version: 'base-int8',
  license: 'MIT',
  sourceUrl: 'https://example.test/asr-models',
  archiveSha256: 'aa',
  archiveBytes: 200,
  parts: {'encoder': 'e', 'decoder': 'd', 'tokens': 't'},
  files: [
    AsrModelFile(name: 'e', sha256: 'e', bytes: 100),
    AsrModelFile(name: 'd', sha256: 'd', bytes: 100),
  ],
  parameters: {},
);

const _writing = LlmModelManifest(
  id: 'qwen3',
  runtime: 'llamadart',
  runtimeVersion: '0.11.1',
  language: 'es',
  license: 'Apache-2.0',
  sourceUrl: 'https://example.test/llm',
  file: 'q.gguf',
  fileName: 'q.gguf',
  sha256: 'bb',
  bytes: 500,
  parameters: {},
);

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('provision-');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  List<ModelTask> describe(Directory speechTarget, Directory writingTarget) =>
      const ModelProvisioner().describe(
        speech: _speech,
        writing: _writing,
        speechTarget: speechTarget,
        writingTarget: writingTarget,
      );

  test('reports both models as missing on a clean device', () {
    final tasks = describe(
      Directory('${root.path}/asr'),
      Directory('${root.path}/llm'),
    );

    expect(tasks, hasLength(2));
    expect(tasks.map((task) => task.status), everyElement(ModelStatus.missing));
    expect(tasks.first.model, LocalModel.speech);
    expect(tasks.last.model, LocalModel.writing);
  });

  test('reports a model ready once its weights sit on disk at full size', () {
    final speechTarget = Directory('${root.path}/asr')..createSync();
    final writingTarget = Directory('${root.path}/llm')..createSync();
    File('${speechTarget.path}/e').writeAsBytesSync(List<int>.filled(100, 1));
    File('${speechTarget.path}/d').writeAsBytesSync(List<int>.filled(100, 1));
    File('${writingTarget.path}/q.gguf')
        .writeAsBytesSync(List<int>.filled(500, 1));

    expect(
      describe(speechTarget, writingTarget).map((task) => task.status),
      everyElement(ModelStatus.ready),
    );
  });

  test('does not treat a truncated weight as installed', () {
    final speechTarget = Directory('${root.path}/asr')..createSync();
    File('${speechTarget.path}/e').writeAsBytesSync([1, 2, 3]);
    File('${speechTarget.path}/d').writeAsBytesSync(List<int>.filled(100, 1));

    final tasks = describe(speechTarget, Directory('${root.path}/llm'));

    expect(tasks.first.status, ModelStatus.missing);
  });

  test('carries the licence and version a reviewer needs', () {
    final task = describe(
      Directory('${root.path}/asr'),
      Directory('${root.path}/llm'),
    ).first;

    expect(task.version, 'base-int8');
    expect(task.license, 'MIT');
    expect(task.purpose, isNotEmpty);
  });

  test('totalBytes adds up what a first run has to pull', () {
    expect(
      const ModelProvisioner().totalBytes([
        _task(bytes: 207557382),
        _task(bytes: 1107409472),
      ]),
      207557382 + 1107409472,
    );
  });

  test('sizeLabel speaks in GB above 1000 MB', () {
    expect(_task(bytes: 1107409472).sizeLabel, '1.06 GB');
    expect(_task(bytes: 207557382).sizeLabel, '197.9 MB');
  });
}

ModelTask _task({required int bytes}) => ModelTask(
  model: LocalModel.speech,
  title: 'Dictado',
  purpose: 'x',
  version: 'base-int8',
  license: 'MIT',
  bytes: bytes,
  status: ModelStatus.missing,
);
