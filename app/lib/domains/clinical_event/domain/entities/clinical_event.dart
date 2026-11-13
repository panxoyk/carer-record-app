class ClinicalEvent {
  const ClinicalEvent({
    required this.organizationId,
    required this.hospitalizationId,
    required this.id,
    required this.patientId,
    required this.kind,
    required this.occurredAt,
    required this.createdAt,
    required this.summary,
    this.sourceKind = 'clinical_event',
    this.authorDisplayName,
    this.category,
    this.authorProfession,
    this.clientEventId,
    this.photoPath,
  });

  final String organizationId;
  final String hospitalizationId;
  final String id;
  final String patientId;
  final String kind;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String summary;

  /// Origin of the row in the timeline view: `clinical_event` or
  /// `context_note` (bitácora milestone).
  final String sourceKind;

  /// Nullable display name resolved for a confirmed context note by Postgres.
  final String? authorDisplayName;

  /// Category the author chose for a context note (ADR-024).
  final String? category;

  /// Profession of the note author captured by the server at publication.
  final String? authorProfession;

  /// Client event id of a context note; clinical photos link to it.
  final String? clientEventId;

  /// Private Storage path of the photo attached to a context note, if any.
  final String? photoPath;

  /// Milestone authored by dictation. The published row is the text its author
  /// confirmed after local transcription; the audio itself is never stored
  /// (ADR-016), so the timeline shows text for every milestone.
  bool get isDictatedMilestone =>
      sourceKind == 'context_note' && kind == 'milestone_audio';

  bool get isMilestone => sourceKind == 'context_note';
}
