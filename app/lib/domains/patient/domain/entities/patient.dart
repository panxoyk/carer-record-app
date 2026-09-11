class Patient {
  const Patient({
    required this.id,
    required this.givenName,
    required this.familyName,
    required this.payload,
  });

  final String id;
  final String givenName;
  final String familyName;
  final Map<String, dynamic> payload;
}
