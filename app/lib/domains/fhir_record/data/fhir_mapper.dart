import '../domain/fhir_record_entities.dart';

/// Frontera anticorrupción: FHIR R4 (JSON crudo) -> modelo interno.
class FhirMapper {
  const FhirMapper();

  static const sectionLabels = <String, String>{
    'Condition': 'Diagnósticos',
    'AllergyIntolerance': 'Alergias',
    'MedicationRequest': 'Medicación',
    'Observation': 'Observaciones y signos',
    'Procedure': 'Procedimientos',
    'Immunization': 'Inmunizaciones',
    'DiagnosticReport': 'Informes',
    'Encounter': 'Encuentros',
  };

  PatientSummary patient(Map<String, dynamic> r) {
    final names = (r['name'] as List?) ?? const [];
    final n = names.isNotEmpty ? names.first as Map : const <String, dynamic>{};
    final given = ((n['given'] as List?) ?? const []).join(' ');
    final family = (n['family'] as String?) ?? '';
    final display = '$given $family'.trim();

    return PatientSummary(
      id: r['id'] as String,
      displayName: display.isEmpty ? 'Sin nombre' : display,
      gender: r['gender'] as String?,
      birthDate: _date(r['birthDate']),
      identifier: _medicalRecordNumber(r),
      ward: _extension(r, 'urn:hospital-simulado:fhir:ward', 'valueString'),
      bed: _extension(
        r,
        'urn:hospital-simulado:fhir:bed-number',
        'valueString',
      ),
      admissionDate: _date(
        _extension(
          r,
          'urn:hospital-simulado:fhir:admission-date',
          'valueDateTime',
        ),
      ),
    );
  }

  /// Prefiere el identificador tipo MR; si no existe usa el primero.
  String? _medicalRecordNumber(Map<String, dynamic> r) {
    final ids = ((r['identifier'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final id in ids) {
      final codings = ((id['type'] as Map?)?['coding'] as List?) ?? const [];
      if (codings.any((c) => c is Map && c['code'] == 'MR')) {
        return id['value'] as String?;
      }
    }
    return ids.isEmpty ? null : ids.first['value'] as String?;
  }

  String? _extension(Map<String, dynamic> r, String url, String valueKey) {
    for (final e in (r['extension'] as List?) ?? const []) {
      if (e is Map && e['url'] == url) return e[valueKey] as String?;
    }
    return null;
  }

  ClinicalRecord record({
    required PatientSummary patient,
    required List<Map<String, dynamic>> resources,
    required bool truncated,
  }) {
    final sections = <String, List<RecordEntry>>{};
    for (final r in resources) {
      final type = r['resourceType'] as String?;
      final label = sectionLabels[type];
      if (label == null) continue; // Claim, Organization, etc.: no se muestran
      sections.putIfAbsent(label, () => []).add(_entry(type!, r));
    }
    for (final list in sections.values) {
      list.sort((a, b) {
        final da = a.date, db = b.date;
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    }
    // Orden estable de secciones según sectionLabels.
    final ordered = <String, List<RecordEntry>>{
      for (final l in sectionLabels.values)
        if (sections.containsKey(l)) l: sections[l]!,
    };
    return ClinicalRecord(
      patient: patient,
      sections: ordered,
      totalResources: resources.length,
      truncated: truncated,
    );
  }

  RecordEntry _entry(String type, Map<String, dynamic> r) {
    switch (type) {
      case 'Condition':
        return RecordEntry(
          title: _concept(r['code']),
          detail: _concept(r['clinicalStatus'], empty: ''),
          date: _date(r['onsetDateTime'] ?? r['recordedDate']),
        );
      case 'AllergyIntolerance':
        return RecordEntry(
          title: _concept(r['code']),
          detail: _concept(r['clinicalStatus'], empty: ''),
          date: _date(r['recordedDate'] ?? r['onsetDateTime']),
        );
      case 'MedicationRequest':
        return RecordEntry(
          title: _concept(r['medicationCodeableConcept']),
          detail: _dosageText(r) ?? r['status'] as String?,
          date: _date(r['authoredOn']),
        );
      case 'Observation':
        return RecordEntry(
          title: _concept(r['code']),
          detail: _observationValue(r),
          date: _date(r['effectiveDateTime'] ?? r['issued']),
        );
      case 'Procedure':
        return RecordEntry(
          title: _concept(r['code']),
          detail: r['status'] as String?,
          date: _date(
            r['performedDateTime'] ?? (r['performedPeriod'] as Map?)?['start'],
          ),
        );
      case 'Immunization':
        return RecordEntry(
          title: _concept(r['vaccineCode']),
          detail: r['status'] as String?,
          date: _date(r['occurrenceDateTime']),
        );
      case 'DiagnosticReport':
        return RecordEntry(
          title: _concept(r['code']),
          detail: r['status'] as String?,
          date: _date(r['effectiveDateTime'] ?? r['issued']),
        );
      case 'Encounter':
        final types = (r['type'] as List?) ?? const [];
        final period = r['period'] as Map?;
        return RecordEntry(
          title: types.isNotEmpty
              ? _concept(types.first)
              : ((r['class'] as Map?)?['code'] as String? ?? 'Encuentro'),
          detail: r['status'] as String?,
          date: _date(period?['start']),
        );
      default:
        return RecordEntry(title: type);
    }
  }

  /// Primera posología con texto (ej. "1 g por vía intravenosa cada 24 horas").
  String? _dosageText(Map<String, dynamic> r) {
    final dosages = ((r['dosageInstruction'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>();
    for (final dosage in dosages) {
      final text = dosage['text'];
      if (text is String && text.isNotEmpty) return text;
    }
    return null;
  }

  String? _observationValue(Map<String, dynamic> r) {
    final q = r['valueQuantity'] as Map?;
    if (q != null) {
      final v = q['value'];
      final shown = v is num ? v.toStringAsFixed(v % 1 == 0 ? 0 : 1) : '$v';
      return '$shown ${q['unit'] ?? ''}'.trim();
    }
    if (r['valueString'] != null) return r['valueString'] as String;
    if (r['valueCodeableConcept'] != null) {
      return _concept(r['valueCodeableConcept'], empty: '');
    }
    final comps = (r['component'] as List?) ?? const [];
    if (comps.isNotEmpty) {
      // Ej. presión arterial: sistólica/diastólica.
      return comps
          .whereType<Map<String, dynamic>>()
          .map((c) {
            final cq = c['valueQuantity'] as Map?;
            if (cq == null) return null;
            final v = cq['value'];
            return v is num ? v.toStringAsFixed(v % 1 == 0 ? 0 : 1) : '$v';
          })
          .whereType<String>()
          .join(' / ');
    }
    return null;
  }

  String _concept(Object? cc, {String empty = 'Sin descripción'}) {
    if (cc is! Map) return empty;
    final text = cc['text'] as String?;
    if (text != null && text.isNotEmpty) return text;
    final codings = (cc['coding'] as List?) ?? const [];
    for (final c in codings) {
      if (c is Map && (c['display'] as String?)?.isNotEmpty == true) {
        return c['display'] as String;
      }
    }
    return empty;
  }

  DateTime? _date(Object? v) => v is String ? DateTime.tryParse(v) : null;
}
