import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/time/clinical_time.dart';
import '../../fhir_record/domain/authorized_clinical_record.dart';
import '../domain/period_summary.dart';

/// Supabase adapter for the period-summary domain. Authorization remains at the
/// RPC/RLS and clinical-record gateway boundaries.
class SupabasePeriodSummaryRepository implements PeriodSummaryRepository {
  SupabasePeriodSummaryRepository({
    required SupabaseClient client,
    required AuthorizedClinicalRecordRepository clinicalRecords,
    String? Function()? authenticatedUserId,
    // ignore: prefer_initializing_formals
  }) : _client = client,
       // ignore: prefer_initializing_formals
       _clinicalRecords = clinicalRecords,
       // ignore: prefer_initializing_formals
       _authenticatedUserId = authenticatedUserId;

  final SupabaseClient _client;
  final AuthorizedClinicalRecordRepository _clinicalRecords;
  final String? Function()? _authenticatedUserId;
  static const _pageSize = 200;
  static const _maxSourceRows = 1000;
  static final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  @override
  Future<PeriodSummaryContext> loadContext({
    required String organizationId,
    required String hospitalizationId,
  }) async {
    _requireUuid(organizationId);
    _requireUuid(hospitalizationId);
    final actor = _currentUser();
    try {
      final rows = await _client.rpc<List<dynamic>>(
        'period_summary_context',
        params: {
          'p_organization_id': organizationId,
          'p_hospitalization_id': hospitalizationId,
        },
      );
      if (rows.length != 1 || rows.single is! Map) {
        _fail('authorization_lost');
      }
      _assertSameActor(actor);
      final row = Map<String, dynamic>.from(rows.single as Map);
      final patient = _string(row['patient_id']);
      if (!_uuid.hasMatch(patient)) _fail('authorization_lost');
      final organizationTimezone = _string(row['timezone']);
      if (organizationTimezone != demoInstitutionTimeZone) {
        _fail('timezone_mismatch');
      }
      return PeriodSummaryContext(
        patientId: patient,
        timezone: demoInstitutionTimeZone,
      );
    } catch (error) {
      _translate(error);
    }
  }

  @override
  Future<SummarySourceBatch> loadSources({
    required String organizationId,
    required String hospitalizationId,
    required SummaryWindow window,
    required Set<SummarySourceKind> selectedKinds,
  }) async {
    final actor = _currentUser();
    final context = await loadContext(
      organizationId: organizationId,
      hospitalizationId: hospitalizationId,
    );
    _assertSameActor(actor);
    final sources = <SummarySource>[];
    var complete = true;
    if (selectedKinds.contains(SummarySourceKind.contextNote)) {
      try {
        final first = await _client
            .from('context_notes')
            .select(
              'id,organization_id,hospitalization_id,patient_id,status,content,occurred_at',
            )
            .eq('organization_id', organizationId)
            .eq('hospitalization_id', hospitalizationId)
            .eq('status', 'confirmed')
            .gte('occurred_at', window.fromUtc.toUtc().toIso8601String())
            .lt('occurred_at', window.toUtc.toUtc().toIso8601String())
            .order('occurred_at')
            .order('id')
            .range(0, _pageSize - 1)
            .count(CountOption.exact);
        final total = first.count;
        _assertSameActor(actor);
        if (total > _maxSourceRows) {
          _fail('input_over_budget');
        }
        if (first.data.length != (total < _pageSize ? total : _pageSize)) {
          _fail('sources_incomplete');
        }
        final rows = <dynamic>[...first.data];
        for (var offset = _pageSize; offset < total; offset += _pageSize) {
          final page = await _client
              .from('context_notes')
              .select(
                'id,organization_id,hospitalization_id,patient_id,status,content,occurred_at',
              )
              .eq('organization_id', organizationId)
              .eq('hospitalization_id', hospitalizationId)
              .eq('status', 'confirmed')
              .gte('occurred_at', window.fromUtc.toUtc().toIso8601String())
              .lt('occurred_at', window.toUtc.toUtc().toIso8601String())
              .order('occurred_at')
              .order('id')
              .range(offset, offset + _pageSize - 1)
              .count(CountOption.exact);
          _assertSameActor(actor);
          if (page.count != total ||
              page.data.length !=
                  (total - offset < _pageSize ? total - offset : _pageSize)) {
            _fail('sources_incomplete');
          }
          rows.addAll(page.data);
        }
        if (rows.length != total) _fail('sources_incomplete');
        final seen = <String>{};
        for (final raw in rows) {
          if (raw is! Map) _fail('sources_incomplete');
          final row = Map<String, dynamic>.from(raw);
          final id = _string(row['id']);
          _assertSameActor(actor);
          if (!_uuid.hasMatch(id) ||
              !seen.add(id) ||
              row['organization_id'] != organizationId ||
              row['hospitalization_id'] != hospitalizationId ||
              row['patient_id'] != context.patientId ||
              row['status'] != 'confirmed' ||
              row['occurred_at'] is! String ||
              row['content'] is! String) {
            _fail('sources_incomplete');
          }
          sources.add(
            SummarySource(
              id: id,
              kind: SummarySourceKind.contextNote,
              title: 'Nota de contexto',
              content: row['content'] as String,
              occurredAt: _instant(row['occurred_at'] as String),
              precision: 'instant',
            ),
          );
        }
      } catch (error) {
        _translate(error);
      }
    }
    final fhirKinds = selectedKinds
        .where((kind) => kind != SummarySourceKind.contextNote)
        .toSet();
    if (fhirKinds.isNotEmpty) {
      try {
        final record = await _clinicalRecords.load(
          organizationId: organizationId,
          hospitalizationId: hospitalizationId,
          purpose: ClinicalRecordPurpose.timeline,
          expectedPatientId: context.patientId,
          range: ClinicalRecordRange(
            fromUtc: window.fromUtc.toUtc(),
            toUtc: window.toUtc.toUtc(),
          ),
        );
        _assertSameActor(actor);
        if (record.hospitalization.id != hospitalizationId ||
            record.patient.id != context.patientId ||
            record.status != 'complete' ||
            record.truncated) {
          _fail('sources_incomplete');
        }
        for (final item in record.timeline) {
          final kind = _kind(item.resourceType);
          if (!fhirKinds.contains(kind)) continue;
          final precision = item.precision;
          final date = item.occurredAt;
          if (precision == null && date == null) {
            sources.add(
              SummarySource(
                id: item.id,
                kind: kind,
                title: item.title,
                content: item.summaryDetail ?? item.detail ?? '',
                precision: 'undated',
              ),
            );
          } else if (precision == 'date' && date != null) {
            // Partial FHIR dates cannot be represented as a calendar day safely.
            if (RegExp(r'^\d{4}$').hasMatch(date) ||
                (RegExp(r'^\d{4}-\d{2}$').hasMatch(date) &&
                    int.parse(date.substring(5)) >= 1 &&
                    int.parse(date.substring(5)) <= 12)) {
              sources.add(
                SummarySource(
                  id: item.id,
                  kind: kind,
                  title: item.title,
                  content: item.summaryDetail ?? item.detail ?? '',
                  precision: 'undated',
                ),
              );
            } else if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date)) {
              final parsed = _dateOnly(date);
              sources.add(
                SummarySource(
                  id: item.id,
                  kind: kind,
                  title: item.title,
                  content: item.summaryDetail ?? item.detail ?? '',
                  occurredAt: parsed,
                  precision: 'date',
                ),
              );
            } else {
              _fail('sources_incomplete');
            }
          } else if (precision == 'instant' && date != null) {
            sources.add(
              SummarySource(
                id: item.id,
                kind: kind,
                title: item.title,
                content: item.summaryDetail ?? item.detail ?? '',
                occurredAt: _instant(date),
                precision: 'instant',
              ),
            );
          } else {
            _fail('sources_incomplete');
          }
        }
      } on ClinicalAuthorizationLost {
        _fail('authorization_lost');
      } catch (error) {
        _translate(error);
      }
    }
    // Recheck authorization after remote source retrieval, before returning any data.
    final after = await loadContext(
      organizationId: organizationId,
      hospitalizationId: hospitalizationId,
    );
    _assertSameActor(actor);
    if (after.patientId != context.patientId ||
        after.timezone != context.timezone) {
      _fail('authorization_lost');
    }
    return SummarySourceBatch(
      sources: List.unmodifiable(sources),
      complete: complete,
    );
  }

  @override
  Future<List<PeriodSummary>> listHistory({
    required String organizationId,
    required String hospitalizationId,
    required int limit,
    required int offset,
  }) async {
    _requireUuid(organizationId);
    _requireUuid(hospitalizationId);
    if (limit < 1 || limit > 20 || offset < 0 || offset > 10000) {
      _fail('invalid_pagination');
    }
    final actor = _currentUser();
    try {
      final result = await _client
          .from('period_summaries')
          .select()
          .eq('organization_id', organizationId)
          .eq('hospitalization_id', hospitalizationId)
          .eq('author_id', actor)
          .order('created_at', ascending: false)
          .order('id', ascending: false)
          .range(offset, offset + limit - 1);
      _assertSameActor(actor);
      final summaries = result
          .map(
            (raw) => _mapSummary(
              raw,
              expectedOrg: organizationId,
              expectedEpisode: hospitalizationId,
              expectedAuthor: actor,
            ),
          )
          .toList(growable: false);
      final context = await loadContext(
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
      );
      _assertSameActor(actor);
      if (summaries.any((item) => item.patientId != context.patientId)) {
        _fail('authorization_lost');
      }
      return summaries;
    } catch (error) {
      _translate(error);
    }
  }

  @override
  Future<PeriodSummary> getOwnDetail({
    required String organizationId,
    required String hospitalizationId,
    required String summaryId,
  }) async {
    _requireUuid(organizationId);
    _requireUuid(hospitalizationId);
    _requireUuid(summaryId);
    final actor = _currentUser();
    try {
      final raw = await _client
          .from('period_summaries')
          .select()
          .eq('id', summaryId)
          .eq('organization_id', organizationId)
          .eq('hospitalization_id', hospitalizationId)
          .eq('author_id', actor)
          .maybeSingle();
      if (raw is! Map) _fail('authorization_lost');
      final summary = _mapSummary(
        raw,
        expectedOrg: organizationId,
        expectedEpisode: hospitalizationId,
        expectedAuthor: actor,
      );
      if (summary.id != summaryId) _fail('invalid_response');
      final context = await loadContext(
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
      );
      _assertSameActor(actor);
      if (summary.patientId != context.patientId) _fail('authorization_lost');
      return summary;
    } catch (error) {
      _translate(error);
    }
  }

  @override
  Future<PeriodSummary> save(SummarySaveAttempt attempt) async {
    _requireUuid(attempt.organizationId);
    _requireUuid(attempt.hospitalizationId);
    _requireUuid(attempt.patientId);
    _requireUuid(attempt.draft.id);
    final actor = _currentUser();
    try {
      final context = await loadContext(
        organizationId: attempt.organizationId,
        hospitalizationId: attempt.hospitalizationId,
      );
      if (context.patientId != attempt.patientId ||
          context.timezone != attempt.window.timezone) {
        _fail('authorization_lost');
      }
      _assertSameActor(actor);
      final result = await _client.rpc<Map<String, dynamic>>(
        'save_period_summary',
        params: {
          'p_id': attempt.draft.id,
          'p_organization_id': attempt.organizationId,
          'p_hospitalization_id': attempt.hospitalizationId,
          'p_patient_id': attempt.patientId,
          'p_from_utc': attempt.window.fromUtc.toUtc().toIso8601String(),
          'p_to_utc': attempt.window.toUtc.toUtc().toIso8601String(),
          'p_timezone': attempt.window.timezone,
          'p_generated_at': attempt.draft.generatedAt.toUtc().toIso8601String(),
          'p_content': attempt.draft.prepared.content,
          'p_model_version': attempt.draft.modelVersion,
          'p_prompt_version': attempt.draft.promptVersion,
          'p_selected_kinds':
              attempt.selectedKinds.map(summaryKindValue).toList()..sort(),
          'p_excluded_undated_count':
              attempt.draft.prepared.excludedUndatedCount,
          'p_sources': attempt.draft.prepared.sources
              .map((source) => source.toJson())
              .toList(),
        },
      );
      _assertSameActor(actor);
      final summary = _mapSummary(
        result,
        expectedOrg: attempt.organizationId,
        expectedEpisode: attempt.hospitalizationId,
        expectedAuthor: actor,
      );
      if (summary.id != attempt.draft.id ||
          summary.patientId != attempt.patientId ||
          !summary.window.fromUtc.isAtSameMomentAs(attempt.window.fromUtc) ||
          !summary.window.toUtc.isAtSameMomentAs(attempt.window.toUtc) ||
          summary.window.timezone != attempt.window.timezone ||
          summary.content != attempt.draft.prepared.content ||
          summary.modelVersion != attempt.draft.modelVersion ||
          summary.promptVersion != attempt.draft.promptVersion) {
        _fail('invalid_response');
      }
      return summary;
    } catch (error) {
      _translate(error);
    }
  }

  String _currentUser() {
    final userId = _authenticatedUserId?.call() ?? _client.auth.currentUser?.id;
    if (userId == null || !_uuid.hasMatch(userId)) _fail('authorization_lost');
    return userId;
  }

  void _assertSameActor(String expected) {
    if (_currentUser() != expected) _fail('authorization_lost');
  }
}

PeriodSummary _mapSummary(
  Object? raw, {
  required String expectedOrg,
  required String expectedEpisode,
  required String expectedAuthor,
}) {
  if (raw is! Map) _fail('invalid_response');
  final m = Map<String, dynamic>.from(raw);
  final id = _string(m['id']),
      org = _string(m['organization_id']),
      episode = _string(m['hospitalization_id']),
      patient = _string(m['patient_id']),
      author = _string(m['author_id']);
  if (![
        id,
        org,
        episode,
        patient,
        author,
      ].every((v) => SupabasePeriodSummaryRepository._uuid.hasMatch(v)) ||
      org != expectedOrg ||
      episode != expectedEpisode ||
      author != expectedAuthor) {
    _fail('authorization_lost');
  }
  final timezone = _string(m['timezone']);
  final start = _instant(_string(m['from_utc']));
  final end = _instant(_string(m['to_utc']));
  if (!end.isAfter(start) || timezone.isEmpty) _fail('invalid_response');
  final kinds = m['selected_kinds'];
  final sourceRows = m['sources'];
  if (kinds is! List ||
      sourceRows is! List ||
      kinds.isEmpty ||
      kinds.length > 6 ||
      sourceRows.isEmpty ||
      sourceRows.length > 1000) {
    _fail('invalid_response');
  }
  final selected = <SummarySourceKind>{};
  for (final item in kinds) {
    if (item is! String) _fail('invalid_response');
    final kind = _kind(item);
    if (!selected.add(kind)) _fail('invalid_response');
  }
  final refs = sourceRows.map(_mapReference).toList(growable: false);
  if (refs.any((r) => !selected.contains(_kind(r.kind)))) {
    _fail('invalid_response');
  }
  final undated = m['excluded_undated_count'];
  if (undated is! int || undated < 0) _fail('invalid_response');
  return PeriodSummary(
    id: id,
    organizationId: org,
    hospitalizationId: episode,
    patientId: patient,
    authorId: author,
    window: SummaryWindow(fromUtc: start, toUtc: end, timezone: timezone),
    generatedAt: _instant(_string(m['generated_at'])),
    createdAt: _instant(_string(m['created_at'])),
    content: _string(m['content']),
    modelVersion: _string(m['model_version']),
    promptVersion: _string(m['prompt_version']),
    selectedKinds: Set.unmodifiable(selected),
    excludedUndatedCount: undated,
    sources: List.unmodifiable(refs),
  );
}

SummarySourceReference _mapReference(Object? value) {
  if (value is! Map) _fail('invalid_response');
  final m = Map<String, dynamic>.from(value);
  if (m.length != 4 ||
      !m.keys.toSet().containsAll({'id', 'kind', 'occurred_at', 'precision'})) {
    _fail('invalid_response');
  }
  final id = _string(m['id']),
      kind = _string(m['kind']),
      precision = _string(m['precision']);
  if (id.isEmpty || id.length > 128) _fail('invalid_response');
  _kind(kind);
  final rawDate = _string(m['occurred_at']);
  if (precision == 'instant') {
    return SummarySourceReference(
      id: id,
      kind: kind,
      precision: precision,
      occurredAt: _instant(rawDate),
    );
  }
  if (precision == 'date') {
    return SummarySourceReference(
      id: id,
      kind: kind,
      precision: precision,
      occurredAt: _dateOnly(rawDate),
    );
  }
  _fail('invalid_response');
}

SummarySourceKind _kind(String value) => switch (value) {
  'context_note' => SummarySourceKind.contextNote,
  'Condition' => SummarySourceKind.condition,
  'Observation' => SummarySourceKind.observation,
  'MedicationRequest' => SummarySourceKind.medicationRequest,
  'Procedure' => SummarySourceKind.procedure,
  'DiagnosticReport' => SummarySourceKind.diagnosticReport,
  _ => throw const PeriodSummaryException('invalid_response'),
};

DateTime _instant(String value) {
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (match == null) _fail('invalid_response');
  final parts = [for (var i = 1; i <= 6; i++) int.parse(match.group(i) ?? '0')];
  final wall = DateTime.utc(
    parts[0],
    parts[1],
    parts[2],
    parts[3],
    parts[4],
    parts[5],
  );
  if (wall.year != parts[0] ||
      wall.month != parts[1] ||
      wall.day != parts[2] ||
      wall.hour != parts[3] ||
      wall.minute != parts[4] ||
      wall.second != parts[5]) {
    _fail('invalid_response');
  }
  final offset = match.group(8)!;
  if (offset != 'Z') {
    final hours = int.parse(offset.substring(1, 3));
    final minutes = int.parse(offset.substring(4, 6));
    if (hours > 14 || minutes > 59 || (hours == 14 && minutes != 0)) {
      _fail('invalid_response');
    }
  }
  final date = DateTime.tryParse(value);
  if (date == null) _fail('invalid_response');
  return date.toUtc();
}

DateTime _dateOnly(String value) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    _fail('invalid_response');
  }
  final parts = value.split('-').map(int.parse).toList();
  final date = DateTime.utc(parts[0], parts[1], parts[2]);
  if (date.year != parts[0] || date.month != parts[1] || date.day != parts[2]) {
    _fail('invalid_response');
  }
  return date;
}

String _string(Object? value) {
  if (value is! String || value.trim().isEmpty) _fail('invalid_response');
  return value;
}

Never _fail(String code) => throw PeriodSummaryException(code);
void _requireUuid(String value) {
  if (!SupabasePeriodSummaryRepository._uuid.hasMatch(value)) {
    _fail('invalid_identifier');
  }
}

Never _translate(Object error) {
  if (error is PeriodSummaryException) throw error;
  if (error is PostgrestException &&
      (error.code == '42501' || error.code == 'PGRST116')) {
    _fail('authorization_lost');
  }
  if (error is FunctionException && {401, 403, 404}.contains(error.status)) {
    _fail('authorization_lost');
  }
  _fail('repository_unavailable');
}
