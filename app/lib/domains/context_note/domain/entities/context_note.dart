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
    this.audioStoragePath,
    this.audioDurationMs,
  });

  final String organizationId;
  final String hospitalizationId;
  final String patientId;
  final MilestoneInputMethod inputMethod;

  /// Milestone text for `text` form; trimmed to 1-20000 chars by the
  /// repository. Must stay null for `audio`.
  final String? content;

  /// Private bucket object path for `audio` form
  /// (`<hospitalization_id>/<client_event_id>.m4a`). Must stay null for
  /// `text`.
  final String? audioStoragePath;
  final int? audioDurationMs;

  /// Client-generated UUID so a retried save never duplicates the milestone.
  final String clientEventId;
}
