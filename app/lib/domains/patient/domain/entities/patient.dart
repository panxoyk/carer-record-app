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
      value.replaceAll(RegExp(r'[.\s]'), '').toUpperCase();
}
