import 'entities/context_note.dart';

/// Port of the local speech-recognition capability. The domain depends on this
/// interface only: it never knows the engine SDK, the native audio format or
/// where the model lives (ADR-007).
abstract interface class AsrEngine {
  /// Whether the engine can transcribe right now. A missing model makes the
  /// feature fail closed (ADR-016 decision 5): the caller offers the text
  /// milestone instead. There is no cloud fallback.
  bool get isAvailable;

  /// Short name recorded in the provenance metadata, e.g. `sherpa_onnx`.
  String get engineId;

  /// Transcribes a sandbox recording. Throws [AsrUnavailableException] when the
  /// engine is not usable and [AsrTranscriptionException] when decoding fails.
  Future<AsrTranscript> transcribe(String wavPath);
}

/// The local engine is missing, unusable or not installed.
class AsrUnavailableException implements Exception {
  const AsrUnavailableException(this.reason);

  /// Human readable, content free.
  final String reason;

  @override
  String toString() => 'AsrUnavailableException: $reason';
}

/// The engine failed on a given recording. Retrying locally is allowed;
/// sending the audio anywhere is not.
class AsrTranscriptionException implements Exception {
  const AsrTranscriptionException(this.reason);

  final String reason;

  @override
  String toString() => 'AsrTranscriptionException: $reason';
}
