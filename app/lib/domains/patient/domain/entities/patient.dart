/// A minimal census row for one hospitalization; not an authorization by patient.
class Patient {
  const Patient({
    required this.organizationId,
    required this.hospitalizationId,
    required this.patientId,
    required this.hospitalizationStatus,
    required this.admittedAt,
    required this.dischargedAt,
    required this.unitId,
    required this.bedLabel,
    required this.givenName,
    required this.familyName,
    required this.birthDate,
  });

  final String organizationId;
  final String hospitalizationId;
  final String patientId;
  final String hospitalizationStatus;
  final DateTime admittedAt;
  final DateTime? dischargedAt;
  final String? unitId;
  final String? bedLabel;
  final String givenName;
  final String familyName;
  final DateTime? birthDate;

  String get fullName => '$givenName $familyName';
  String get locationLabel =>
      bedLabel?.trim().isNotEmpty == true
          ? 'Cama $bedLabel'
          : 'Ubicación no registrada';

  bool matchesSearch(String query) {
    final normalized = normalizeSearchText(query);
    return normalized.isEmpty ||
        normalized.split(' ').every(normalizeSearchText(fullName).contains);
  }

  static String normalizeSearchText(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[áàäâ]'), 'a')
      .replaceAll(RegExp(r'[éèëê]'), 'e')
      .replaceAll(RegExp(r'[íìïî]'), 'i')
      .replaceAll(RegExp(r'[óòöô]'), 'o')
      .replaceAll(RegExp(r'[úùüû]'), 'u')
      .replaceAll('ñ', 'n')
      .replaceAll(RegExp(r'\s+'), ' ');
}
