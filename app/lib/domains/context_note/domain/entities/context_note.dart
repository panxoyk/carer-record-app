import 'dictation_stage.dart';

/// How a bitácora milestone (context note) was authored.
enum MilestoneInputMethod {
  text('text'),
  audio('audio');

  const MilestoneInputMethod(this.wire);

  final String wire;
}

/// A bitácora milestone ready to be published. Saving it from the UI is the
/// author's confirmation, so the row is created as `confirmed`; RLS re-checks
/// active membership, `context.note.*` permissions and episode scope.
class ContextNoteMilestone {
  const ContextNoteMilestone({
    required this.organizationId,
    required this.hospitalizationId,
    required this.patientId,
    required this.inputMethod,
    required this.clientEventId,
    this.content,
    this.transcription,
  });

  final String organizationId;
  final String hospitalizationId;
  final String patientId;
  final MilestoneInputMethod inputMethod;

  /// The text the author confirmed, for both forms. Trimmed to 1-20000 chars by
  /// the repository. Required: an audio milestone persists the reviewed
  /// transcription, never the recording (ADR-016).
  final String? content;

  /// Auditable, non-sensitive ASR provenance. Present only for the audio form;
  /// the database rejects it otherwise.
  final TranscriptionMetadata? transcription;

  /// Client-generated UUID so a retried save never duplicates the milestone.
  final String clientEventId;

  ContextNoteMilestone copyWith({
    MilestoneInputMethod? inputMethod,
    String? content,
    TranscriptionMetadata? transcription,
  }) {
    return ContextNoteMilestone(
      organizationId: organizationId,
      hospitalizationId: hospitalizationId,
      patientId: patientId,
      inputMethod: inputMethod ?? this.inputMethod,
      clientEventId: clientEventId,
      content: content ?? this.content,
      transcription: transcription ?? this.transcription,
    );
  }
}

/// A part of the dictated audio the engine flagged as uncertain, so the author
/// can listen to it again before confirming (ADR-007).
class LowConfidenceSegment {
  const LowConfidenceSegment({
    required this.startMs,
    required this.endMs,
    required this.confidence,
  });

  final int startMs;
  final int endMs;
  final double confidence;

  factory LowConfidenceSegment.fromJson(Map<String, Object?> json) {
    return LowConfidenceSegment(
      startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
      endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'start_ms': startMs,
    'end_ms': endMs,
    'confidence': confidence,
  };
}

/// Typed contract for the `transcription_metadata` jsonb column. The database
/// enforces the same shape, including the ban on free text, so a value that
/// survives this class is still rejected server-side if it carries content.
class TranscriptionMetadata {
  const TranscriptionMetadata({
    required this.engine,
    required this.pipelineVersion,
    this.model,
    this.modelVersion,
    this.modelChecksum,
    this.durationMs,
    this.meanConfidence,
    this.parameters = const <String, Object?>{},
    this.lowConfidenceSegments = const <LowConfidenceSegment>[],
  });

  final String engine;
  final String pipelineVersion;
  final String? model;
  final String? modelVersion;
  final String? modelChecksum;
  final int? durationMs;
  final double? meanConfidence;
  final Map<String, Object?> parameters;
  final List<LowConfidenceSegment> lowConfidenceSegments;

  bool get hasUncertainSegments => lowConfidenceSegments.isNotEmpty;

  factory TranscriptionMetadata.fromJson(Map<String, Object?> json) {
    final segments = json['low_confidence_segments'];
    return TranscriptionMetadata(
      engine: json['asr_engine'] as String? ?? '',
      model: json['asr_model'] as String?,
      modelVersion: json['asr_model_version'] as String?,
      modelChecksum: json['asr_model_checksum'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toInt(),
      meanConfidence: (json['mean_confidence'] as num?)?.toDouble(),
      parameters: Map<String, Object?>.from(
        (json['asr_parameters'] as Map<Object?, Object?>?) ??
            const <String, Object?>{},
      ),
      pipelineVersion: json['pipeline_version'] as String? ?? '',
      lowConfidenceSegments:
          segments is List
              ? segments
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (item) => LowConfidenceSegment.fromJson(
                      Map<String, Object?>.from(item),
                    ),
                  )
                  .toList(growable: false)
              : const <LowConfidenceSegment>[],
    );
  }

  Map<String, Object?> toJson() {
    final json = <String, Object?>{
      'asr_engine': engine,
      'pipeline_version': pipelineVersion,
    };
    void put(String key, Object? value) {
      if (value != null) json[key] = value;
    }

    put('asr_model', model);
    put('asr_model_version', modelVersion);
    put('asr_model_checksum', modelChecksum);
    put('duration_ms', durationMs);
    put('mean_confidence', meanConfidence);
    if (parameters.isNotEmpty) json['asr_parameters'] = parameters;
    if (lowConfidenceSegments.isNotEmpty) {
      json['low_confidence_segments'] =
          lowConfidenceSegments.map((segment) => segment.toJson()).toList();
    }
    return json;
  }
}

/// A local ASR result. It is a draft: the author edits and confirms it before
/// anything is persisted, and the audio it came from is deleted afterwards.
class AsrTranscript {
  const AsrTranscript({
    required this.text,
    required this.metadata,
    this.lowConfidenceSegments = const <LowConfidenceSegment>[],
  });

  final String text;
  final TranscriptionMetadata metadata;
  final List<LowConfidenceSegment> lowConfidenceSegments;

  bool get isEmpty => text.trim().isEmpty;
  bool get hasUncertainSegments => lowConfidenceSegments.isNotEmpty;
}

/// In-memory state of one dictation. It owns no I/O: the presentation layer
/// drives [stage] and the data layer supplies the engine and the repository.
class DictationSession {
  const DictationSession({
    this.stage = DictationStage.idle,
    this.recordingPath,
    this.transcript,
    this.draftText,
    this.error,
  });

  final DictationStage stage;

  /// Absolute path of the sandbox recording, while it still exists.
  final String? recordingPath;

  /// The local transcription, once the engine returned it.
  final AsrTranscript? transcript;

  /// What the author currently sees in the editable field. Only this is
  /// persisted on confirmation.
  final String? draftText;

  final String? error;

  bool get canListen => recordingPath != null;
  bool get canConfirm =>
      stage == DictationStage.readyToConfirm &&
      (draftText ?? '').trim().isNotEmpty;

  DictationSession copyWith({
    DictationStage? stage,
    String? recordingPath,
    AsrTranscript? transcript,
    String? draftText,
    String? error,
    bool clearError = false,
  }) {
    return DictationSession(
      stage: stage ?? this.stage,
      recordingPath: recordingPath ?? this.recordingPath,
      transcript: transcript ?? this.transcript,
      draftText: draftText ?? this.draftText,
      error: clearError ? null : (error ?? this.error),
    );
  }
}
