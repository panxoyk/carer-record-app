import '../../domain/entities/practitioner.dart';

class PractitionerModel extends Practitioner {
  const PractitionerModel({
    required super.id,
    required super.displayName,
    required super.role,
    required super.status,
  });

  factory PractitionerModel.fromJson(Map<String, dynamic> json) =>
      PractitionerModel(
        id: json['id'] as String,
        displayName: json['display_name'] as String,
        role: json['role'] as String,
        status: json['status'] as String? ?? 'active',
      );
}
