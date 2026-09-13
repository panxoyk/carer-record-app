import '../../domain/entities/patient.dart';

class PatientModel extends Patient {
  const PatientModel({
    required super.id,
    required super.externalReference,
    required super.rut,
    required super.givenName,
    required super.familyName,
    required super.birthDate,
    required super.careUnit,
    required super.bedLabel,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) => PatientModel(
    id: json['id'] as String,
    externalReference: json['external_reference'] as String?,
    rut: json['rut'] as String?,
    givenName: json['given_name'] as String,
    familyName: json['family_name'] as String,
    birthDate:
        json['birth_date'] == null
            ? null
            : DateTime.parse(json['birth_date'] as String),
    careUnit: json['care_unit'] as String?,
    bedLabel: json['bed_label'] as String?,
  );
}
