import '../../domain/entities/patient.dart';

class PatientModel extends Patient {
  const PatientModel({
    required super.organizationId,
    required super.hospitalizationId,
    required super.patientId,
    required super.hospitalizationStatus,
    required super.admittedAt,
    required super.dischargedAt,
    required super.unitId,
    required super.bedLabel,
    required super.givenName,
    required super.familyName,
    required super.birthDate,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) {
    const required = [
      'organization_id',
      'hospitalization_id',
      'patient_id',
      'hospitalization_status',
      'admitted_at',
      'discharged_at',
      'unit_id',
      'bed_label',
      'given_name',
      'family_name',
      'birth_date',
    ];
    if (required.any((key) => !json.containsKey(key))) {
      throw const FormatException('Incomplete hospitalization census row');
    }
    return PatientModel(
      organizationId: json['organization_id'] as String,
      hospitalizationId: json['hospitalization_id'] as String,
      patientId: json['patient_id'] as String,
      hospitalizationStatus: json['hospitalization_status'] as String,
      admittedAt: DateTime.parse(json['admitted_at'] as String).toUtc(),
      dischargedAt:
          json['discharged_at'] == null
              ? null
              : DateTime.parse(json['discharged_at'] as String).toUtc(),
      unitId: json['unit_id'] as String?,
      bedLabel: json['bed_label'] as String?,
      givenName: json['given_name'] as String,
      familyName: json['family_name'] as String,
      birthDate:
          json['birth_date'] == null
              ? null
              : DateTime.parse(json['birth_date'] as String),
    );
  }
}
