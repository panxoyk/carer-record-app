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
    required this.payload,
  });

  final String id;
  final String? externalReference;
  final String? rut;
  final String givenName;
  final String familyName;
  final DateTime? birthDate;
  final String? careUnit;
  final String? bedLabel;
  final Map<String, dynamic> payload;

  String get fullName => '$givenName $familyName';

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
