class Practitioner {
  const Practitioner({
    required this.id,
    required this.displayName,
    required this.role,
    required this.status,
  });

  final String id;
  final String displayName;
  final String role;
  final String status;

  bool get isAdministrator => role == 'administrator';
  bool get isActive => status == 'active';
}
