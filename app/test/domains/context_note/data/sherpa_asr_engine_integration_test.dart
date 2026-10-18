@Tags(['asr-model'])
library;

import 'dart:io';

import 'package:carer_record_app/domains/on_device_ai/data/asr_model_manifest.dart';
import 'package:carer_record_app/domains/on_device_ai/data/sherpa_asr_engine.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/asr_engine.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

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

  late String manifestSource;
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    manifestSource = await rootBundle.loadString(
      'assets/asr_model_manifest.json',
    );
  });

  test('loads the declared model and decodes a sample offline', () async {
    final stopwatch = Stopwatch()..start();
    final engine = SherpaAsrEngine(
      manifest: AsrModelManifest.parse(manifestSource),
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
      manifest: AsrModelManifest.parse(manifestSource),
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
