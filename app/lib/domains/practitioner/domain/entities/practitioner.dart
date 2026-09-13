enum PractitionerRole { administrator, physician, nurse, technician }

enum PractitionerStatus { active, suspended }

class Practitioner {
  const Practitioner({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
  });

  final String id;
  final String displayName;
  final PractitionerRole role;
  final PractitionerStatus status;

  bool get isAdministrator => role == PractitionerRole.administrator;
  bool get isActive => status == PractitionerStatus.active;
}
