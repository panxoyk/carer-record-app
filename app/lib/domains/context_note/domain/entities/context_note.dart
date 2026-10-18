import 'dictation_stage.dart';
import '../../../on_device_ai/domain/asr_transcript.dart';
export '../../../on_device_ai/domain/asr_transcript.dart';

const int maxMilestoneTextLength = 20000;

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

/// In-memory state of one dictation. It owns no I/O: the presentation layer
/// drives [stage] and the data layer supplies the engine and the repository.
class DictationSession {
  static const _unchanged = Object();
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
    Object? recordingPath = _unchanged,
    Object? transcript = _unchanged,
    Object? draftText = _unchanged,
    Object? error = _unchanged,
    bool clearError = false,
  }) {
    return DictationSession(
      stage: stage ?? this.stage,
      recordingPath: identical(recordingPath, _unchanged)
          ? this.recordingPath
          : recordingPath as String?,
      transcript: identical(transcript, _unchanged)
          ? this.transcript
          : transcript as AsrTranscript?,
      draftText: identical(draftText, _unchanged)
          ? this.draftText
          : draftText as String?,
      error: clearError
          ? null
          : identical(error, _unchanged)
          ? this.error
          : error as String?,
    );
  }
}
