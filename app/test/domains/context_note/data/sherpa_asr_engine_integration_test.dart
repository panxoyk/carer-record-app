@Tags(['asr-model'])
library;

import 'dart:io';

import 'package:carer_record_app/domains/context_note/data/asr_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/sherpa_asr_engine.dart';
import 'package:carer_record_app/domains/context_note/domain/asr_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Spike SP-01 — motor real contra el modelo declarado.
///
/// No forma parte de la suite ordinary: necesita los pesos instalados y una
/// muestra de audio. Se ejecuta solo cuando `CRA_ASR_MODEL_DIR` apunta al
/// directorio con el modelo verificado y `CRA_ASR_SAMPLE` a un WAV sintético.
///
/// Uso:
///
/// ```sh
/// CRA_ASR_MODEL_DIR=E:/cra-models/sherpa-onnx-whisper-base \
/// CRA_ASR_SAMPLE=E:/cra-models/sherpa-onnx-whisper-base/test_wavs/0.wav \
///   flutter test test/domains/context_note/data/sherpa_asr_engine_integration_test.dart
/// ```
void main() {
  final modelDir = Platform.environment['CRA_ASR_MODEL_DIR'];
  final sample = Platform.environment['CRA_ASR_SAMPLE'];
  final enabled = modelDir != null && sample != null;

  test('loads the declared model and decodes a sample offline', () async {
    final stopwatch = Stopwatch()..start();
    final engine = SherpaAsrEngine(
      manifest: AsrModelManifest.parse(_shippedManifest()),
      modelDirectory: Directory(modelDir!),
    );
    addTearDown(engine.dispose);

    expect(await engine.load(), isTrue, reason: 'el motor debe cargar');
    expect(engine.isAvailable, isTrue);
    final loaded = stopwatch.elapsed;

    stopwatch.reset();
    final transcript = await engine.transcribe(sample!);
    final elapsed = stopwatch.elapsed;

    // ignore: avoid_print
    print(
      'SP-01 host: load=${loaded.inMilliseconds}ms '
      'decode=${elapsed.inMilliseconds}ms '
      'chars=${transcript.text.length}',
    );

    expect(transcript.text.trim(), isNotEmpty);
    expect(transcript.metadata.engine, 'sherpa_onnx');
    expect(transcript.metadata.durationMs, isNotNull);
    expect(transcript.metadata.durationMs, greaterThan(0));
    expect(transcript.metadata.toJson().keys, contains('asr_engine'));
    expect(transcript.metadata.toJson().keys, isNot(contains('transcript')));
  }, skip: enabled ? false : 'requiere CRA_ASR_MODEL_DIR y CRA_ASR_SAMPLE');

  test('fails closed without the declared weights', () async {
    final empty = await Directory.systemTemp.createTemp('cra-asr-empty-');
    addTearDown(() async {
      if (empty.existsSync()) empty.deleteSync(recursive: true);
    });
    final engine = SherpaAsrEngine(
      manifest: AsrModelManifest.parse(_shippedManifest()),
      modelDirectory: empty,
    );
    addTearDown(engine.dispose);
    expect(await engine.load(), isFalse);
    expect(engine.isAvailable, isFalse);
    expect(
      () => engine.transcribe('missing.wav'),
      throwsA(isA<AsrUnavailableException>()),
    );
  });
}

String _shippedManifest() =>
    const String.fromEnvironment('CRA_ASR_MANIFEST') == ''
    ? _defaultManifest
    : const String.fromEnvironment('CRA_ASR_MANIFEST');

const String _defaultManifest = '''
{
  "id": "sherpa-onnx-whisper-base",
  "family": "whisper",
  "language": "es",
  "engine": "sherpa_onnx",
  "engine_version": "1.13.8",
  "version": "base-int8",
  "license": "MIT",
  "source_url": "https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models",
  "archive_sha256": "911b2083efd7c0dca2ac3b358b75222660dc09fb716d64fbfc417ba6c99ff3de",
  "archive_bytes": 207557382,
  "parts": {
    "encoder": "base-encoder.onnx",
    "decoder": "base-decoder.onnx",
    "tokens": "base-tokens.txt"
  },
  "files": [
    {
      "name": "base-encoder.int8.onnx",
      "sha256": "0b8fb1304b6109976038efff5ace81720e00386f3ff6b54ee8c75291ca0a1e11",
      "bytes": 29120534
    },
    {
      "name": "base-decoder.int8.onnx",
      "sha256": "9759d217388a01b3a4c7c15533201067b48ae819c4daafc8624e64b9409dc02d",
      "bytes": 130672026
    },
    {
      "name": "base-tokens.txt",
      "sha256": "b34b360dbb493e781e479794586d661700670d65564001f23024971d1f2fa126",
      "bytes": 816730
    }
  ],
  "parameters": { "num_threads": 2 }
}
''';
