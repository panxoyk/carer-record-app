import '../../domain/entities/clinical_event.dart';

class ClinicalEventModel extends ClinicalEvent {
  const ClinicalEventModel({
    required super.id,
    required super.patientId,
    required super.kind,
    required super.occurredAt,
    required super.details,
  });

  factory ClinicalEventModel.fromJson(Map<String, dynamic> json) =>
      ClinicalEventModel(
        id: json['id'] as String,
        patientId: json['patient_id'] as String,
        kind: json['kind'] as String,
        occurredAt: DateTime.parse(json['occurred_at'] as String).toUtc(),
        details: ClinicalEventDetails(
          summary: (json['payload'] as Map)['summary'] as String,
        ),
      );
}
