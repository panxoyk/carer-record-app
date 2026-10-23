import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/authorized_clinical_record.dart';

const _sectionTypes = {
  'conditions',
  'observations',
  'medications',
  'procedures',
  'reports',
  'allergies',
};
const _dateOnly = r'^\d{4}(?:-\d{2}(?:-\d{2})?)?$';
const _instant =
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|([+-])(\d{2}):(\d{2}))$';

class AuthorizedClinicalRecordRepositoryImpl
    implements AuthorizedClinicalRecordRepository {
  AuthorizedClinicalRecordRepositoryImpl(this._client);
  final SupabaseClient _client;

  @override
  Future<AuthorizedClinicalRecord> load({
    required String organizationId,
    required String hospitalizationId,
    required ClinicalRecordPurpose purpose,
    String? expectedPatientId,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'clinical-record',
        body: {
          'organizationId': organizationId,
          'hospitalizationId': hospitalizationId,
          'purpose': purpose.name,
        },
      );
    } on FunctionException catch (e) {
      final status = e.status;
      if (status == 401 || status == 403 || status == 404) {
        throw ClinicalAuthorizationLost(status);
      }
      rethrow;
    }
    final body = response.data;
    if (body is! Map) {
      throw const FormatException('Invalid clinical record response');
    }
    final map = Map<String, dynamic>.from(body);
    final patient = _map(map['patient'], 'patient');
    final episode = _map(map['hospitalization'], 'hospitalization');
    final freshness = _map(map['freshness'], 'freshness');
    if (_requiredString(episode, 'id') != hospitalizationId ||
        (expectedPatientId != null &&
            _requiredString(patient, 'id') != expectedPatientId)) {
      throw const FormatException('Clinical record context mismatch');
    }
    final status = _requiredString(map, 'status');
    if (!{'complete', 'partial'}.contains(status)) {
      throw const FormatException('Invalid status');
    }
    final truncated = map['truncated'];
    if (truncated is! bool) {
      throw const FormatException('Invalid truncated flag');
    }
    final sectionsRaw = map['sections'];
    final timelineRaw = map['timeline'];
    if (sectionsRaw is! List || timelineRaw is! List) {
      throw const FormatException('Invalid clinical collections');
    }
    if (purpose == ClinicalRecordPurpose.record && timelineRaw.isNotEmpty) {
      throw const FormatException('Record response must not include timeline');
    }
    final hospitalizationStatus = _requiredString(episode, 'status');
    if (!{'admitted', 'discharged'}.contains(hospitalizationStatus)) {
      throw const FormatException('Invalid hospitalization status');
    }
    final sections = sectionsRaw
        .map((raw) {
          if (raw is! Map) throw const FormatException('Invalid section');
          final section = Map<String, dynamic>.from(raw);
          final type = _requiredString(section, 'type');
          final entries = section['entries'];
          if (!_sectionTypes.contains(type) || entries is! List) {
            throw const FormatException('Invalid section contract');
          }
          return ClinicalRecordSection(
            type: type,
            entries: entries.map(_entry).toList(growable: false),
          );
        })
        .toList(growable: false);
    return AuthorizedClinicalRecord(
      status: status,
      truncated: truncated,
      freshness: ClinicalRecordFreshness(
        retrievedAt: _requiredInstant(freshness, 'retrievedAt'),
        sourceUpdatedAt: _optionalDate(
          freshness,
          'sourceUpdatedAt',
          instantOnly: true,
        ),
      ),
      patient: ClinicalRecordPatient(
        id: _requiredString(patient, 'id'),
        name: _requiredString(patient, 'name'),
        identifier: _optionalString(patient, 'identifier'),
        birthDate: _optionalDate(patient, 'birthDate'),
        gender: _optionalString(patient, 'gender'),
      ),
      hospitalization: ClinicalHospitalization(
        id: hospitalizationId,
        status: hospitalizationStatus,
        admittedAt: _requiredInstant(episode, 'admittedAt'),
        dischargedAt: _optionalDate(episode, 'dischargedAt', instantOnly: true),
        unit: _optionalString(episode, 'unit'),
        bed: _optionalString(episode, 'bed'),
      ),
      sections: sections,
      timeline: timelineRaw.map(_timeline).toList(growable: false),
    );
  }
}

Map<String, dynamic> _map(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('Invalid $name');
  }
  return Map<String, dynamic>.from(value);
}

String _requiredString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Invalid $key');
  }
  return value;
}

String? _optionalString(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value == null) return null;
  if (value is! String) throw FormatException('Invalid $key');
  return value;
}

String _requiredInstant(Map<String, dynamic> map, String key) =>
    _validateDate(_requiredString(map, key), instantOnly: true);
String? _optionalDate(
  Map<String, dynamic> map,
  String key, {
  bool instantOnly = false,
}) {
  final value = _optionalString(map, key);
  return value == null ? null : _validateDate(value, instantOnly: instantOnly);
}

String _validateDate(String value, {bool instantOnly = false}) {
  if (!instantOnly && RegExp(_dateOnly).hasMatch(value)) {
    final parts = value.split('-').map(int.parse).toList();
    final year = parts[0];
    if (year < 1) throw const FormatException('Invalid clinical date');
    if (parts.length > 1 && (parts[1] < 1 || parts[1] > 12)) {
      throw const FormatException('Invalid clinical date');
    }
    if (parts.length > 2) {
      final leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
      final days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
      if (parts[2] < 1 || parts[2] > days[parts[1] - 1]) {
        throw const FormatException('Invalid clinical date');
      }
    }
    return value;
  }
  final match = RegExp(_instant).firstMatch(value);
  if (match != null) {
    final year = int.parse(match[1]!);
    final month = int.parse(match[2]!);
    final day = int.parse(match[3]!);
    final hour = int.parse(match[4]!);
    final minute = int.parse(match[5]!);
    final second = int.parse(match[6] ?? '0');
    final date = DateTime.utc(year, month, day, hour, minute, second);
    final offsetHour = int.parse(match[10] ?? '0');
    final offsetMinute = int.parse(match[11] ?? '0');
    if (year > 0 &&
        date.year == year &&
        date.month == month &&
        date.day == day &&
        hour <= 23 &&
        minute <= 59 &&
        second <= 59 &&
        offsetHour <= 14 &&
        offsetMinute <= 59 &&
        (offsetHour < 14 || offsetMinute == 0)) {
      return value;
    }
  }
  throw const FormatException('Invalid clinical date');
}

ClinicalRecordEntry _entry(Object? raw) {
  final m = _map(raw, 'entry');
  final date = _optionalDate(m, 'date');
  final dateOnly = m['isDateOnly'];
  if (dateOnly is! bool ||
      dateOnly != (date != null && RegExp(_dateOnly).hasMatch(date))) {
    throw const FormatException('Invalid entry date precision');
  }
  return ClinicalRecordEntry(
    id: _requiredString(m, 'id'),
    title: _requiredString(m, 'title'),
    sourceKind: _requiredString(m, 'sourceKind'),
    detail: _optionalString(m, 'detail'),
    date: date,
    isDateOnly: dateOnly,
  );
}

ClinicalTimelineItem _timeline(Object? raw) {
  final m = _map(raw, 'timeline item');
  final date = _optionalDate(m, 'occurredAt');
  final precision = m['precision'];
  final expected = date == null
      ? null
      : RegExp(_dateOnly).hasMatch(date)
      ? 'date'
      : 'instant';
  if (precision != expected) {
    throw const FormatException('Invalid timeline precision');
  }
  return ClinicalTimelineItem(
    id: _requiredString(m, 'id'),
    resourceType: _requiredString(m, 'resourceType'),
    title: _requiredString(m, 'title'),
    detail: _optionalString(m, 'detail'),
    occurredAt: date,
    precision: precision as String?,
  );
}
