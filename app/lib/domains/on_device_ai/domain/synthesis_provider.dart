/// Ports and contracts of the local text assistance (ADR-017).
///
/// The domain depends on [SynthesisProvider] only. It never imports the GGUF
/// runtime, so swapping the deterministic fake for the real adapter — or the
/// other way around — does not change a single use case or test.
library;

/// What the assistant is being asked for. Order matters: the first use is
/// polishing the text the author wrote by hand.
enum SynthesisPurpose {
  /// Improve the wording of a milestone without inventing facts.
  improveNoteText,

  /// Point out entities the author may want to rephrase. Local NER only: no
  /// substitution, no token map, nothing leaves the device.
  flagEntities,

  /// Period summary over an authorized interval (ADR-011). Last addition.
  periodSummary,
}

/// An entity the local model noticed in the text. It is shown to the author as a
/// hint and never substituted, stored or transmitted.
class DetectedEntity {
  const DetectedEntity({
    required this.value,
    required this.type,
    required this.start,
    required this.end,
    this.confidence,
  });

  final String value;
  final String type;
  final int start;
  final int end;
  final double? confidence;

  factory DetectedEntity.fromJson(Map<String, Object?> json) {
    return DetectedEntity(
      value: json['value'] as String? ?? '',
      type: json['type'] as String? ?? 'unknown',
      start: (json['start'] as num?)?.toInt() ?? 0,
      end: (json['end'] as num?)?.toInt() ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble(),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'value': value,
    'type': type,
    'start': start,
    'end': end,
    if (confidence != null) 'confidence': confidence,
  };
}

/// Stable error codes. They are part of the port contract: the UI maps them to
/// messages and the tests assert on them, never on runtime error strings.
class SynthesisErrorCode {
  const SynthesisErrorCode._();

  /// The model is not installed, or the runtime is unavailable on this device.
  static const String unavailable = 'synthesis_unavailable';

  /// The generation exceeded the budget configured by the use case.
  static const String timeout = 'synthesis_timeout';

  /// The caller cancelled the generation.
  static const String cancelled = 'synthesis_cancelled';

  /// The output exceeded the configured limit and was discarded.
  static const String tooLong = 'synthesis_too_long';

  /// The model returned something the use case could not validate.
  static const String malformed = 'synthesis_malformed';

  /// Anything else. The detail is never surfaced to the author.
  static const String internal = 'synthesis_internal';
}

class SynthesisException implements Exception {
  const SynthesisException(this.code, {this.detail});

  final String code;

  /// Technical context for logs. Never shown to the author and never persisted.
  final String? detail;

  @override
  String toString() =>
      'SynthesisException($code${detail == null ? '' : ': $detail'})';
}

class SynthesisRequest {
  const SynthesisRequest({
    required this.purpose,
    required this.text,
    required this.promptVersion,
    required this.timeout,
    required this.maxOutputChars,
    this.idempotencyKey,
  });

  final SynthesisPurpose purpose;

  /// Text authored on the device. It never leaves the device.
  final String text;

  /// Version of the prompt template, recorded so a result can be explained.
  final String promptVersion;

  final Duration timeout;
  final int maxOutputChars;

  /// Lets a retry reuse the same key instead of producing a second draft.
  final String? idempotencyKey;
}

class SynthesisResult {
  const SynthesisResult({
    required this.text,
    required this.modelVersion,
    required this.promptVersion,
    this.entities = const <DetectedEntity>[],
    this.structured = false,
    this.elapsed = Duration.zero,
  });

  /// Draft suggestion. The author always reviews it; it is never published
  /// directly.
  final String text;

  final String modelVersion;
  final String promptVersion;
  final List<DetectedEntity> entities;

  /// True when the model honoured the structured output contract.
  final bool structured;

  /// Technical measurement only; it is not persisted with the note.
  final Duration elapsed;

  bool get hasEntities => entities.isNotEmpty;
}

/// Local text assistance. Implementations never perform network calls.
abstract interface class SynthesisProvider {
  /// False when the model is missing or the runtime cannot run here. The caller
  /// then publishes the author's text untouched.
  bool get isAvailable;

  /// Version of the model this provider loaded, recorded in the pipeline
  /// provenance.
  String get modelVersion;

  /// Generates a draft. [isCancelled] is polled so the use case can abort
  /// without killing the model, and the provider reports a stable
  /// [SynthesisErrorCode.cancelled] instead of a partial result.
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  });

  Future<void> dispose();
}

/// Outcome of asking for help. Assistance is never blocking: when the model is
/// unavailable or fails, [fallback] is the author's own text and the milestone is
/// still published.
class SynthesisOutcome {
  const SynthesisOutcome({
    required this.fallback,
    this.suggestion,
    this.entities = const <DetectedEntity>[],
    this.errorCode,
    this.modelVersion,
    this.elapsed = Duration.zero,
  });

  /// The text that must be used when no suggestion is available.
  final String fallback;

  /// Editable draft produced by the model.
  final String? suggestion;

  final List<DetectedEntity> entities;

  /// Null on success.
  final String? errorCode;

  final String? modelVersion;
  final Duration elapsed;

  bool get hasSuggestion => suggestion != null && suggestion!.trim().isNotEmpty;
}
