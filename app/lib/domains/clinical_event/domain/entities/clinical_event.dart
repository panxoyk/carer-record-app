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
    this.audioStoragePath,
    this.audioDurationMs,
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
  final String? audioStoragePath;
  final int? audioDurationMs;

  bool get isStoredAudioMilestone =>
      sourceKind == 'context_note' &&
      audioStoragePath != null &&
      audioStoragePath!.isNotEmpty;
}
