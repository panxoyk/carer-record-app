enum ClinicalRecordPurpose { record, timeline }

class ClinicalRecordRange {
  const ClinicalRecordRange({required this.fromUtc, required this.toUtc});

  final DateTime fromUtc;
  final DateTime toUtc;
}

class ClinicalRecordPatient {
  const ClinicalRecordPatient({
    required this.id,
    required this.name,
    this.identifier,
    this.birthDate,
    this.gender,
  });
  final String id;
  final String name;
  final String? identifier, birthDate, gender;
}

class ClinicalHospitalization {
  const ClinicalHospitalization({
    required this.id,
    required this.status,
    required this.admittedAt,
    this.dischargedAt,
    this.unit,
    this.bed,
    this.attendingPhysician,
    this.reason,
  });
  final String id, status, admittedAt;
  final String? dischargedAt, unit, bed;

  /// Attending physician display name from `Encounter.participant`.
  final String? attendingPhysician;

  /// Admission reason (`Encounter.reasonCode` or principal diagnosis).
  final String? reason;
}

class ClinicalRecordEntry {
  const ClinicalRecordEntry({
    required this.id,
    required this.title,
    required this.sourceKind,
    required this.isDateOnly,
    this.detail,
    this.date,
    this.value,
    this.flag,
    this.code,
    this.category,
    this.administeredAt,
    this.noteRef,
  });
  final String id, title, sourceKind;
  final String? detail, date;
  final bool isDateOnly;

  /// Compact measured value, e.g. `120/80 mmHg` (ADR-024).
  final String? value;

  /// Out of range value from the source interpretation or reference range.
  final ClinicalValueFlag? flag;

  /// First code of the resource (LOINC for observations).
  final String? code;

  /// First category code (`vital-signs`, `laboratory`, `fluid-intake`…).
  final String? category;

  /// Administration instant matched to a scheduled dose, if recorded.
  final String? administeredAt;

  /// Note client event id or timeline entry id a clinical photo belongs to.
  final String? noteRef;

  bool get isAbnormal => flag != null;

  /// FHIR id of the resource (`demo-hapi/<type>/<id>`).
  String get resourceId => id.split('@').first.split('/').last;
}

enum ClinicalValueFlag {
  high('Alto'),
  low('Bajo'),
  abnormal('Alterado');

  const ClinicalValueFlag(this.label);
  final String label;
}

/// Section types returned by the gateway.
abstract final class ClinicalSectionType {
  static const conditions = 'conditions';
  static const observations = 'observations';
  static const medications = 'medications';
  static const procedures = 'procedures';
  static const reports = 'reports';
  static const allergies = 'allergies';
  static const administrations = 'administrations';
  static const photos = 'photos';
  static const all = {
    conditions,
    observations,
    medications,
    procedures,
    reports,
    allergies,
    administrations,
    photos,
  };
}

class ClinicalRecordSection {
  const ClinicalRecordSection({required this.type, required this.entries});
  final String type;
  final List<ClinicalRecordEntry> entries;
}

class ClinicalTimelineItem {
  const ClinicalTimelineItem({
    required this.id,
    required this.resourceType,
    required this.title,
    this.occurredAt,
    this.precision,
    this.detail,
  });
  final String id, resourceType, title;
  final String? occurredAt, detail;
  final String? precision;
}

class ClinicalRecordFreshness {
  const ClinicalRecordFreshness({
    required this.retrievedAt,
    this.sourceUpdatedAt,
  });
  final String retrievedAt;
  final String? sourceUpdatedAt;
}

class AuthorizedClinicalRecord {
  const AuthorizedClinicalRecord({
    required this.status,
    required this.truncated,
    required this.freshness,
    required this.patient,
    required this.hospitalization,
    required this.sections,
    required this.timeline,
  });
  final String status;
  final bool truncated;
  final ClinicalRecordFreshness freshness;
  final ClinicalRecordPatient patient;
  final ClinicalHospitalization hospitalization;
  final List<ClinicalRecordSection> sections;
  final List<ClinicalTimelineItem> timeline;

  List<ClinicalRecordEntry> entriesOf(String type) => [
    for (final section in sections)
      if (section.type == type) ...section.entries,
  ];
}

/// One clinical photo downloaded through the gateway (ADR-024).
class ClinicalPhoto {
  const ClinicalPhoto({required this.contentType, required this.bytes});
  final String contentType;
  final List<int> bytes;
}

class ClinicalAuthorizationLost implements Exception {
  const ClinicalAuthorizationLost(this.status);
  final int status;
}

abstract interface class AuthorizedClinicalRecordRepository {
  Future<AuthorizedClinicalRecord> load({
    required String organizationId,
    required String hospitalizationId,
    required ClinicalRecordPurpose purpose,
    String? expectedPatientId,
    ClinicalRecordRange? range,
  });
}
