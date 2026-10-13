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

  /// Milestone authored by dictation. The published row is the text its author
  /// confirmed after local transcription; the audio itself is never stored
  /// (ADR-016), so the timeline shows text for every milestone.
  bool get isDictatedMilestone =>
      sourceKind == 'context_note' && kind == 'milestone_audio';

  bool get isMilestone => sourceKind == 'context_note';
}
