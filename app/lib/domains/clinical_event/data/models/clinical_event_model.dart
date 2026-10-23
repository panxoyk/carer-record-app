import '../../domain/entities/clinical_event.dart';

class ClinicalEventModel extends ClinicalEvent {
  const ClinicalEventModel({
    required super.organizationId,
    required super.hospitalizationId,
    required super.id,
    required super.patientId,
    required super.kind,
    required super.occurredAt,
    required super.createdAt,
    required super.summary,
    super.sourceKind,
    super.authorDisplayName,
  });

  factory ClinicalEventModel.fromJson(Map<String, dynamic> json) {
    const required = [
      'organization_id',
      'hospitalization_id',
      'event_id',
      'kind',
      'occurred_at',
      'summary',
      'patient_id',
      'created_at',
      'author_display_name',
    ];
    if (required.any((key) => !json.containsKey(key))) {
      throw const FormatException('Incomplete clinical timeline row');
    }
    return ClinicalEventModel(
      organizationId: json['organization_id'] as String,
      hospitalizationId: json['hospitalization_id'] as String,
      id: json['event_id'] as String,
      kind: json['kind'] as String,
      occurredAt: DateTime.parse(json['occurred_at'] as String).toUtc(),
      summary: json['summary'] as String,
      patientId: json['patient_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String).toUtc(),
      sourceKind: (json['source_kind'] as String?) ?? 'clinical_event',
      authorDisplayName: json['author_display_name'] as String?,
    );
  }
}
