class ClinicalEvent {
  const ClinicalEvent({
    required this.id,
    required this.patientId,
    required this.kind,
    required this.occurredAt,
    required this.details,
  });

  final String id;
  final String patientId;
  final String kind;
  final DateTime occurredAt;
  final ClinicalEventDetails details;

  String get summary => details.summary;
}

class ClinicalEventDetails {
  const ClinicalEventDetails({required this.summary});

  final String summary;
}
