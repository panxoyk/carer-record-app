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
  });

  final String organizationId;
  final String hospitalizationId;
  final String id;
  final String patientId;
  final String kind;
  final DateTime occurredAt;
  final DateTime createdAt;
  final String summary;
}
