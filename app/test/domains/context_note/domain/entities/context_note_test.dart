import 'package:carer_record_app/domains/context_note/domain/entities/context_note.dart';
import 'package:carer_record_app/domains/context_note/domain/entities/dictation_stage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptionMetadata', () {
    const full = TranscriptionMetadata(
      engine: 'sherpa_onnx',
      model: 'sherpa-onnx-whisper-base',
      modelVersion: 'base-int8',
      modelChecksum:
          '911b2083efd7c0dca2ac3b358b75222660dc09fb716d64fbfc417ba6c99ff3de',
      durationMs: 42000,
      meanConfidence: 0.91,
      parameters: <String, Object?>{'num_threads': 2},
      pipelineVersion: '1.0.0',
      lowConfidenceSegments: <LowConfidenceSegment>[
        LowConfidenceSegment(startMs: 12000, endMs: 13500, confidence: 0.42),
      ],
    );

    test('serializes only the keys ADR-016 allows', () {
      final json = full.toJson();
      expect(json.keys.toSet(), <String>{
        'asr_engine',
        'asr_model',
        'asr_model_version',
        'asr_model_checksum',
        'duration_ms',
        'mean_confidence',
        'asr_parameters',
        'low_confidence_segments',
        'pipeline_version',
      });
    });

    test('never emits content-bearing keys', () {
      final json = full.toJson();
      for (final key in json.keys) {
        expect(
          key.contains('text') ||
              key.contains('content') ||
              key.contains('transcript'),
          isFalse,
          reason: '$key looks like it could carry transcribed content',
        );
      }
    });

    test('omits absent measurements instead of sending nulls', () {
      const minimal = TranscriptionMetadata(
        engine: 'sherpa_onnx',
        pipelineVersion: '1.0.0',
      );
      expect(minimal.toJson(), <String, Object?>{
        'asr_engine': 'sherpa_onnx',
        'pipeline_version': '1.0.0',
      });
      expect(minimal.hasUncertainSegments, isFalse);
    });

    test('round-trips through its typed contract', () {
      final parsed = TranscriptionMetadata.fromJson(full.toJson());
      expect(parsed.engine, full.engine);
      expect(parsed.model, full.model);
      expect(parsed.durationMs, full.durationMs);
      expect(parsed.meanConfidence, full.meanConfidence);
      expect(parsed.parameters, full.parameters);
      expect(parsed.lowConfidenceSegments, hasLength(1));
      expect(parsed.hasUncertainSegments, isTrue);
      expect(parsed.lowConfidenceSegments.single.startMs, 12000);
    });

    test('identifier strings stay inside the database pattern', () {
      final pattern = RegExp(r'^[A-Za-z0-9._:+/-]{1,128}$');
      final json = full.toJson();
      for (final key in [
        'asr_engine',
        'asr_model',
        'asr_model_version',
        'asr_model_checksum',
        'pipeline_version',
      ]) {
        expect(pattern.hasMatch(json[key] as String), isTrue, reason: key);
      }
    });
  });

  group('ContextNoteMilestone', () {
    test('carries confirmed content for the text form', () {
      const milestone = ContextNoteMilestone(
        organizationId: 'org',
        hospitalizationId: 'episode',
        patientId: 'patient',
        inputMethod: MilestoneInputMethod.text,
        clientEventId: 'event',
        content: 'Hito escrito a mano.',
      );
      expect(milestone.transcription, isNull);
      expect(milestone.copyWith().content, 'Hito escrito a mano.');
    });

    test('carries provenance only for the audio form', () {
      const milestone = ContextNoteMilestone(
        organizationId: 'org',
        hospitalizationId: 'episode',
        patientId: 'patient',
        inputMethod: MilestoneInputMethod.audio,
        clientEventId: 'event',
        content: 'Texto revisado por la autora.',
        transcription: TranscriptionMetadata(
          engine: 'sherpa_onnx',
          pipelineVersion: '1.0.0',
        ),
      );
      expect(milestone.transcription, isNotNull);
      expect(milestone.inputMethod.wire, 'audio');
    });
  });

  group('DictationSession', () {
    test('only a reviewed draft can be confirmed', () {
      const empty = DictationSession(stage: DictationStage.readyToConfirm);
      expect(empty.canConfirm, isFalse);
      expect(
        const DictationSession(
          stage: DictationStage.readyToConfirm,
          draftText: '  ',
        ).canConfirm,
        isFalse,
      );
      expect(
        const DictationSession(
          stage: DictationStage.readyToConfirm,
          draftText: 'Revisado.',
        ).canConfirm,
        isTrue,
      );
    });

    test(
      'explicit null clears every optional artifact while omission retains it',
      () {
        const populated = DictationSession(
          recordingPath: '/tmp/capture.wav',
          draftText: 'draft',
          error: 'error',
        );
        expect(populated.copyWith().recordingPath, '/tmp/capture.wav');
        final cleared = populated.copyWith(
          recordingPath: null,
          draftText: null,
          error: null,
        );
        expect(cleared.recordingPath, isNull);
        expect(cleared.draftText, isNull);
        expect(cleared.error, isNull);
      },
    );

    test('stages that hold artifacts are explicit', () {
      expect(DictationStage.recording.holdsTemporaryArtifacts, isTrue);
      expect(DictationStage.transcribingLocal.holdsTemporaryArtifacts, isTrue);
      expect(DictationStage.readyToConfirm.holdsTemporaryArtifacts, isTrue);
      expect(DictationStage.failed.holdsTemporaryArtifacts, isTrue);
      expect(DictationStage.published.holdsTemporaryArtifacts, isFalse);
      expect(DictationStage.discarded.holdsTemporaryArtifacts, isFalse);
      expect(DictationStage.published.isTerminal, isTrue);
      expect(DictationStage.discarded.isTerminal, isTrue);
      expect(DictationStage.idle.isTerminal, isFalse);
    });
  });
}
