/// Entidades internas de la ficha clínica obtenida desde HAPI FHIR.
/// La UI nunca ve recursos FHIR crudos: solo estas clases.
class PatientSummary {
  const PatientSummary({
    required this.id,
    required this.displayName,
    this.gender,
    this.birthDate,
    this.identifier,
    this.ward,
    this.bed,
    this.admissionDate,
  });

  final String id;
  final String displayName;
  final String? gender;
  final DateTime? birthDate;
  final String? identifier;

  /// Sala, cama y fecha de ingreso (extensiones urn:hospital-simulado:fhir:*).
  final String? ward;
  final String? bed;
  final DateTime? admissionDate;

  String? get genderLabel => switch (gender) {
    'female' => 'Femenino',
    'male' => 'Masculino',
    'other' => 'Otro',
    null => null,
    _ => 'No especificado',
  };

  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    var years = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) {
      years--;
    }
    return years;
  }
}

class RecordEntry {
  const RecordEntry({required this.title, this.detail, this.date});

  final String title;
  final String? detail;
  final DateTime? date;
}

class ClinicalRecord {
  const ClinicalRecord({
    required this.patient,
    required this.sections,
    required this.totalResources,
    required this.truncated,
  });

  final PatientSummary patient;

  /// Etiqueta de sección (ej. "Diagnósticos") -> entradas ordenadas por fecha desc.
  final Map<String, List<RecordEntry>> sections;

  /// Recursos recibidos desde el servidor (incluye los que no se muestran).
  final int totalResources;

  /// true si se alcanzó el tope de páginas y la ficha puede estar incompleta.
  final bool truncated;
}

class FhirException implements Exception {
  const FhirException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Una página del listado de pacientes. [nextPageToken] es opaco: se
/// devuelve tal cual a [FhirRecordRepository.listPatients] para la siguiente.
class PatientPage {
  const PatientPage({required this.patients, this.nextPageToken});

  final List<PatientSummary> patients;
  final String? nextPageToken;
}

abstract interface class FhirRecordRepository {
  /// Lista pacientes (todos si [query] está vacío) de a una página.
  Future<PatientPage> listPatients({String query = '', String? pageToken});
  Future<ClinicalRecord> loadRecord(String patientId);
}
