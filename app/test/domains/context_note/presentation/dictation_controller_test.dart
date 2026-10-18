import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/asr_engine.dart';
import 'package:carer_record_app/domains/context_note/domain/dictation_audio.dart';
import 'package:carer_record_app/domains/context_note/domain/entities/context_note.dart';
import 'package:carer_record_app/domains/context_note/domain/entities/dictation_stage.dart';
import 'package:carer_record_app/domains/context_note/presentation/controllers/dictation_controller.dart';

void main() {
  test('captures then transcribes and stores the local draft', () async {
    final audio = _Audio();
    final artifacts = _Artifacts();
    final controller = _controller(audio, artifacts);
    await controller.toggleRecording();
    await controller.toggleRecording();
    expect(controller.session.transcript?.text, 'nota');
    expect(artifacts.draft, 'nota');
    controller.dispose();
  });

  test('permission denial never starts capture', () async {
    final audio = _Audio()..permission = false;
    final controller = _controller(audio, _Artifacts());
    await controller.toggleRecording();
    expect(audio.started, isFalse);
    expect(controller.session.error, contains('micrófono'));
    controller.dispose();
  });

  test('empty transcript stays editable and reports explanatory error', () async {
    final audio = _Audio();
    final controller = DictationController(
      audioFactory: () => audio,
      artifactsFactory: _Artifacts.new,
      loadEngine: () async => _Engine()..empty = true,
      newId: () => 'id',
    );
    await controller.toggleRecording();
    await controller.toggleRecording();
    expect(controller.session.stage, DictationStage.readyToConfirm);
    expect(controller.session.draftText, '');
    expect(controller.session.canConfirm, isFalse);
    expect(
      controller.session.error,
      'La transcripción local quedó vacía. Vuelve a grabar o escribe el hito.',
    );
    controller.dispose();
  });

  test(
    'controller owns and disposes its audio instance once on close',
    () async {
      final audio = _Audio();
      final controller = _controller(audio, _Artifacts());
      expect(audio.disposals, 0);
      await controller.toggleRecording();
      expect(audio.disposals, 0);
      controller.dispose();
      await Future<void>.delayed(Duration.zero);
      expect(audio.disposals, 1);
    },
  );

  test('discard stops before purge and retries failed cleanup', () async {
    final audio = _Audio();
    final artifacts = _Artifacts()..failPurge = true;
    final controller = _controller(audio, artifacts);
    await controller.toggleRecording();
    expect(await controller.discard(), isFalse);
    artifacts.failPurge = false;
    expect(await controller.discard(), isTrue);
    expect(artifacts.order, ['register', 'purge', 'purge']);
    expect(audio.stopped, greaterThan(0));
    controller.dispose();
  });

  test('discard invalidates pending transcription', () async {
    final audio = _Audio();
    final engine = _Engine()..pending = Completer<AsrTranscript>();
    final controller = DictationController(
      audioFactory: () => audio,
      artifactsFactory: () => _Artifacts(),
      loadEngine: () async => engine,
      newId: () => 'id',
    );
    await controller.toggleRecording();
    final transcription = controller.toggleRecording();
    await Future<void>.delayed(Duration.zero);
    await controller.discard();
    engine.pending!.complete(_transcript());
    await transcription;
    expect(controller.session.transcript, isNull);
    controller.dispose();
  });
}

DictationController _controller(_Audio audio, _Artifacts artifacts) =>
    DictationController(
      audioFactory: () => audio,
      artifactsFactory: () => artifacts,
      loadEngine: () async => _Engine(),
      newId: () => 'id',
    );

AsrTranscript _transcript() => AsrTranscript(
  text: 'nota',
  metadata: const TranscriptionMetadata(engine: 'fake', pipelineVersion: '1'),
);

class _Audio implements DictationAudio {
  bool permission = true;
  bool started = false;
  int stopped = 0;
  int disposals = 0;
  @override
  Future<bool> requestPermission() async => permission;
  @override
  Future<String> prepareSandboxPath(String operationId) async =>
      '/tmp/$operationId';
  @override
  Future<void> startPcm16(String path) async {
    started = true;
  }

  @override
  Future<String?> stop() async {
    stopped++;
    return null;
  }

  @override
  Future<String> prepareWav(String path) async => path;
  @override
  Future<bool> togglePreview(String path) async => false;
  @override
  Future<void> stopPreview() async {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class _Artifacts implements DictationArtifacts {
  final order = <String>[];
  String? draft;
  bool failPurge = false;
  @override
  Future<void> registerCapture(
    String operationId,
    String recordingPath,
  ) async => order.add('register');
  @override
  Future<void> putDraft(
    String operationId, {
    required String transcription,
    required String recordingPath,
  }) async {
    draft = transcription;
  }

  @override
  Future<void> purge(String operationId, {String? recordingPath}) async {
    order.add('purge');
    if (failPurge) throw StateError('failure');
  }
}

class _Engine implements AsrEngine {
  Completer<AsrTranscript>? pending;
  bool empty = false;
  @override
  bool get isAvailable => true;
  @override
  String get engineId => 'fake';
  @override
  Future<AsrTranscript> transcribe(String wavPath) =>
      pending?.future ??
      Future.value(
        empty
            ? AsrTranscript(
                text: '',
                metadata: const TranscriptionMetadata(
                  engine: 'fake',
                  pipelineVersion: '1',
                ),
              )
            : _transcript(),
      );
}
