import '../../domain/entities/patient.dart';

class PatientModel extends Patient {
  const PatientModel({
    required super.id,
    required super.givenName,
    required super.familyName,
    required super.payload,
  });

  factory PatientModel.fromJson(Map<String, dynamic> json) => PatientModel(
    id: json['id'] as String,
    givenName: json['given_name'] as String,
    familyName: json['family_name'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
  );
}
