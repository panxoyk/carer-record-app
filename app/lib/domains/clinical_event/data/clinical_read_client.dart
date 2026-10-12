import 'package:supabase_flutter/supabase_flutter.dart';

enum ClinicalReadView { census, demographics, timeline }

enum ClinicalReadOrder { familyName, givenName, occurredAtDescending }

bool isClinicalReadUuid(String value) => RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
).hasMatch(value);

/// Closed query contract: callers cannot provide arbitrary table/view names or columns.
class ClinicalReadQuery {
  const ClinicalReadQuery._({
    required this.view,
    required this.organizationId,
    this.hospitalizationId,
    this.single = false,
    this.order = const [],
  });

  final ClinicalReadView view;
  final String organizationId;
  final String? hospitalizationId;
  final bool single;
  final List<ClinicalReadOrder> order;

  String get viewName => switch (view) {
    ClinicalReadView.census => 'clinical_census_by_hospitalization',
    ClinicalReadView.demographics =>
      'clinical_patient_demographics_by_hospitalization',
    ClinicalReadView.timeline => 'clinical_timeline_by_hospitalization',
  };
  String get columns => switch (view) {
    ClinicalReadView.census =>
      'organization_id,hospitalization_id,patient_id,hospitalization_status,admitted_at,discharged_at,unit_id,bed_label,given_name,family_name,birth_date',
    ClinicalReadView.demographics =>
      'organization_id,hospitalization_id,patient_id,given_name,family_name,birth_date',
    ClinicalReadView.timeline =>
      'organization_id,hospitalization_id,event_id,kind,occurred_at,summary,patient_id,created_at',
  };
  List<String> get filterColumns => [
    'organization_id',
    if (hospitalizationId != null) 'hospitalization_id',
  ];

  static ClinicalReadQuery census(String organizationId) => ClinicalReadQuery._(
    view: ClinicalReadView.census,
    organizationId: organizationId,
    order: const [ClinicalReadOrder.familyName, ClinicalReadOrder.givenName],
  );

  static ClinicalReadQuery censusEpisode(
    String organizationId,
    String hospitalizationId,
  ) => ClinicalReadQuery._(
    view: ClinicalReadView.census,
    organizationId: organizationId,
    hospitalizationId: hospitalizationId,
    single: true,
  );

  static ClinicalReadQuery demographics(
    String organizationId,
    String hospitalizationId,
  ) => ClinicalReadQuery._(
    view: ClinicalReadView.demographics,
    organizationId: organizationId,
    hospitalizationId: hospitalizationId,
    single: true,
  );

  static ClinicalReadQuery timeline(
    String organizationId,
    String hospitalizationId,
  ) => ClinicalReadQuery._(
    view: ClinicalReadView.timeline,
    organizationId: organizationId,
    hospitalizationId: hospitalizationId,
    order: const [ClinicalReadOrder.occurredAtDescending],
  );
}

abstract interface class ClinicalReadClient {
  Future<List<Map<String, dynamic>>> execute(ClinicalReadQuery query);
}

class SupabaseClinicalReadClient implements ClinicalReadClient {
  SupabaseClinicalReadClient(this._client);
  final SupabaseClient _client;

  @override
  Future<List<Map<String, dynamic>>> execute(ClinicalReadQuery query) async {
    if (query.single) {
      final id = query.hospitalizationId;
      if (id == null) {
        throw const FormatException('Single episode query needs ID');
      }
      final row =
          await _client
              .from(query.viewName)
              .select(query.columns)
              .eq('organization_id', query.organizationId)
              .eq('hospitalization_id', id)
              .maybeSingle();
      return row == null ? const [] : [Map<String, dynamic>.from(row)];
    }
    if (query.view == ClinicalReadView.timeline) {
      final id = query.hospitalizationId;
      if (id == null) throw const FormatException('Timeline query needs ID');
      final rows = await _client
          .from(query.viewName)
          .select(query.columns)
          .eq('organization_id', query.organizationId)
          .eq('hospitalization_id', id)
          .order('occurred_at', ascending: false);
      return rows.map((row) => Map<String, dynamic>.from(row)).toList();
    }
    final rows = await _client
        .from(query.viewName)
        .select(query.columns)
        .eq('organization_id', query.organizationId)
        .order('family_name')
        .order('given_name');
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }
}
