enum ClinicalRecordPurpose { record, timeline }

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
  });
  final String id, status, admittedAt;
  final String? dischargedAt, unit, bed;
}

class ClinicalRecordEntry {
  const ClinicalRecordEntry({
    required this.id,
    required this.title,
    required this.sourceKind,
    required this.isDateOnly,
    this.detail,
    this.date,
  });
  final String id, title, sourceKind;
  final String? detail, date;
  final bool isDateOnly;
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
  });
}
