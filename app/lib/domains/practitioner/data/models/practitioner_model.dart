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
        role: PractitionerRole.values.byName(json['role'] as String),
        status: PractitionerStatus.values.byName(
          json['status'] as String? ?? 'active',
        ),
      );
}
