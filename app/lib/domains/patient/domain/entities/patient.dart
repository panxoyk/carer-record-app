class Patient {
  const Patient({
    required this.id,
    required this.externalReference,
    required this.rut,
    required this.givenName,
    required this.familyName,
    required this.birthDate,
    required this.careUnit,
    required this.bedLabel,
  });

  final String id;
  final String? externalReference;
  final String? rut;
  final String givenName;
  final String familyName;
  final DateTime? birthDate;
  final String? careUnit;
  final String? bedLabel;

  String get fullName => '$givenName $familyName';

  bool matchesSearch(String query) {
    final normalizedNameQuery = normalizeSearchText(query);
    if (normalizedNameQuery.isEmpty) return true;

    final normalizedName = normalizeSearchText(fullName);
    final nameMatches = normalizedNameQuery
        .split(' ')
        .every(normalizedName.contains);
    final value = rut;
    if (value == null) return nameMatches;

    final normalizedRutQuery = normalizeRut(query);
    return nameMatches ||
        (normalizedRutQuery.isNotEmpty &&
            normalizeRut(value).contains(normalizedRutQuery));
  }

  String? get maskedRut {
    final value = rut;
    if (value == null) return null;
    final match = RegExp(r'^([0-9]{7,8})-([0-9K])$').firstMatch(value);
    if (match == null) return '****';
    final digits = match.group(1)!;
    final hidden = List.filled(digits.length - 3, '*').join();
    return '$hidden${digits.substring(digits.length - 3)}-${match.group(2)}';
  }

  String get locationLabel {
    final location = <String>[
      if (careUnit != null) careUnit!,
      if (bedLabel != null) bedLabel!,
    ];
    return location.isEmpty ? 'Ubicación no registrada' : location.join(' · ');
  }

  static String normalizeRut(String value) =>
      value.replaceAll(RegExp(r'[.\s-]'), '').toUpperCase();

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
