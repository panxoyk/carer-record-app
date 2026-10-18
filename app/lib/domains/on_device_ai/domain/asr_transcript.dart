/// A part of dictated audio the engine flagged as uncertain.
class LowConfidenceSegment {
  const LowConfidenceSegment({
    required this.startMs,
    required this.endMs,
    required this.confidence,
  });
  final int startMs;
  final int endMs;
  final double confidence;
  factory LowConfidenceSegment.fromJson(Map<String, Object?> json) =>
      LowConfidenceSegment(
        startMs: (json['start_ms'] as num?)?.toInt() ?? 0,
        endMs: (json['end_ms'] as num?)?.toInt() ?? 0,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      );
  Map<String, Object?> toJson() => <String, Object?>{
    'start_ms': startMs,
    'end_ms': endMs,
    'confidence': confidence,
  };
}

/// Typed contract for the `transcription_metadata` jsonb column.
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
      lowConfidenceSegments: segments is List
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
      json['low_confidence_segments'] = lowConfidenceSegments
          .map((segment) => segment.toJson())
          .toList();
    }
    return json;
  }
}

/// A local ASR result, before author confirmation.
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
