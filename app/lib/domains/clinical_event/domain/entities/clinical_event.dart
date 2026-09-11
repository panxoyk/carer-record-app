class ClinicalEvent {
  const ClinicalEvent({
    required this.id,
    required this.patientId,
    required this.kind,
    required this.occurredAt,
    required this.payload,
  });

  final String id;
  final String patientId;
  final String kind;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;
}
