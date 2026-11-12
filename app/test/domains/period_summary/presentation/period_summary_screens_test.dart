import 'package:carer_record_app/domains/on_device_ai/data/fake_synthesis_provider.dart';
import 'package:carer_record_app/domains/on_device_ai/presentation/local_ai_providers.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';
import 'package:carer_record_app/domains/period_summary/presentation/controllers/period_summary_controller.dart';
import 'package:carer_record_app/domains/period_summary/presentation/period_summary_providers.dart';
import 'package:carer_record_app/domains/period_summary/presentation/screens/period_summary_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _episode = 'episode';
final _patient = Patient(
  organizationId: 'org',
  hospitalizationId: _episode,
  patientId: 'patient',
  hospitalizationStatus: 'admitted',
  admittedAt: DateTime.utc(2026),
  dischargedAt: null,
  unitId: null,
  bedLabel: '1',
  givenName: 'Paciente',
  familyName: 'Sintético',
  birthDate: null,
);

PeriodSummary _summary({String content = 'Resumen clínico sintético.'}) =>
    PeriodSummary(
      id: 'summary',
      organizationId: 'org',
      hospitalizationId: _episode,
      patientId: 'patient',
      authorId: 'author',
      window: SummaryWindow(
        fromUtc: DateTime.utc(2026, 1, 1),
        toUtc: DateTime.utc(2026, 1, 2),
        timezone: 'America/Santiago',
      ),
      generatedAt: DateTime.utc(2026, 1, 2, 4),
      createdAt: DateTime.utc(2026, 1, 2, 4),
      content: content,
      modelVersion: 'm',
      promptVersion: 'p',
      selectedKinds: {SummarySourceKind.observation},
      excludedUndatedCount: 1,
      sources: [
        SummarySourceReference(
          id: 'Observation/source',
          kind: 'Observation',
          occurredAt: DateTime.utc(2026, 1, 1),
          precision: 'date',
        ),
      ],
    );

class _Repository implements PeriodSummaryRepository {
  @override
  Future<PeriodSummaryContext> loadContext({
    required String organizationId,
    required String hospitalizationId,
  }) async => const PeriodSummaryContext(
    patientId: 'patient',
    timezone: 'America/Santiago',
  );
  @override
  Future<SummarySourceBatch> loadSources({
    required String organizationId,
    required String hospitalizationId,
    required SummaryWindow window,
    required Set<SummarySourceKind> selectedKinds,
  }) async => SummarySourceBatch(
    complete: true,
    sources: [
      SummarySource(
        id: 'note',
        kind: SummarySourceKind.contextNote,
        title: 'Nota',
        content: 'Sin cambios.',
        occurredAt: window.fromUtc.add(const Duration(hours: 1)),
        precision: 'instant',
      ),
    ],
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<GoRouter> _mount(
  WidgetTester tester,
  Widget screen, {
  bool allowed = true,
  List<PeriodSummary> rows = const [],
  PeriodSummary? detail,
  PeriodSummaryController? controller,
}) async {
  final repo = _Repository();
  final c =
      controller ??
      PeriodSummaryController(
        repository: repo,
        generator: PeriodSummaryGenerator(
          repository: repo,
          provider: FakeSynthesisProvider(),
          newId: () => 'id',
        ),
        organizationId: 'org',
        hospitalizationId: _episode,
        canContinue: () => allowed,
      );
  final router = GoRouter(
    initialLocation: '/test',
    routes: [
      GoRoute(path: '/test', builder: (_, __) => screen),
      GoRoute(
        path: '/hospitalizations/episode/summaries/new',
        builder: (_, __) => const Scaffold(body: Text('Nueva pantalla')),
      ),
      GoRoute(
        path: '/hospitalizations/episode/summaries/summary',
        builder: (_, __) => const Scaffold(body: Text('Detalle seleccionado')),
      ),
    ],
  );
  addTearDown(router.dispose);
  addTearDown(c.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        periodSummaryAllowedProvider.overrideWith((ref) => allowed),
        patientProvider.overrideWith((ref, id) async => _patient),
        periodSummaryHistoryProvider.overrideWith((ref, key) async => rows),
        periodSummaryDetailProvider.overrideWith(
          (ref, key) async => detail ?? _summary(),
        ),
        periodSummaryContextProvider.overrideWith(
          (ref, id) async => const PeriodSummaryContext(
            patientId: 'patient',
            timezone: 'America/Santiago',
          ),
        ),
        periodSummaryControllerProvider.overrideWith((ref, id) => c),
        synthesisProviderProvider.overrideWith(
          (ref) async => FakeSynthesisProvider(),
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets(
    'history is an episode screen with empty state and generation entry',
    (tester) async {
      await _mount(
        tester,
        const PeriodSummaryHistoryScreen(hospitalizationId: _episode),
      );
      expect(find.text('Mis resúmenes'), findsOneWidget);
      expect(find.text('Paciente Sintético'), findsOneWidget);
      expect(find.textContaining('Aún no has generado'), findsOneWidget);
      await tester.tap(find.text('Generar resumen'));
      await tester.pumpAndSettle();
      expect(find.text('Nueva pantalla'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
    },
  );
  testWidgets('history entry opens its own detail route', (tester) async {
    await _mount(
      tester,
      const PeriodSummaryHistoryScreen(hospitalizationId: _episode),
      rows: [_summary()],
    );
    await tester.tap(find.textContaining('2025-12-31'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle seleccionado'), findsOneWidget);
  });
  testWidgets('no permission hides patient and summary content', (
    tester,
  ) async {
    await _mount(
      tester,
      const PeriodSummaryDetailScreen(
        hospitalizationId: _episode,
        summaryId: 'summary',
      ),
      allowed: false,
      detail: _summary(content: 'Texto privado'),
    );
    expect(find.text('No tienes acceso a esta función.'), findsOneWidget);
    expect(find.text('Texto privado'), findsNothing);
    expect(find.text('Paciente Sintético'), findsNothing);
  });
  testWidgets('detail preserves date-only precision and historical warning', (
    tester,
  ) async {
    await _mount(
      tester,
      const PeriodSummaryDetailScreen(
        hospitalizationId: _episode,
        summaryId: 'summary',
      ),
    );
    expect(find.textContaining('No es una nota clínica'), findsOneWidget);
    expect(find.textContaining('Generado: 2026-01-02 01:00'), findsOneWidget);
    await tester.ensureVisible(find.text('Fuentes incluidas'));
    await tester.tap(find.text('Fuentes incluidas'));
    await tester.pumpAndSettle();
    expect(find.text('2026-01-01 · sin hora registrada'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Publicar como nota'), findsNothing);
  });
  testWidgets('configuration defaults to 24 hours and previews sources', (
    tester,
  ) async {
    await _mount(
      tester,
      const GeneratePeriodSummaryScreen(hospitalizationId: _episode),
    );
    final selected = tester
        .widgetList<ChoiceChip>(find.byType(ChoiceChip))
        .where((chip) => chip.selected)
        .single;
    expect((selected.label as Text).data, '24 horas');
    expect(find.byType(FilterChip), findsNWidgets(6));
    expect(find.textContaining('America/Santiago'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Consultar fuentes'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Consultar fuentes'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Fuentes incluidas: 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending save locks filters and prevents regenerating', (
    tester,
  ) async {
    final repo = _Repository();
    final c = PeriodSummaryController(
      repository: repo,
      generator: PeriodSummaryGenerator(
        repository: repo,
        provider: FakeSynthesisProvider(),
        newId: () => 'id',
      ),
      organizationId: 'org',
      hospitalizationId: _episode,
      canContinue: () => true,
    )..phase = PeriodSummaryPhase.saveFailed;
    await _mount(
      tester,
      const GeneratePeriodSummaryScreen(hospitalizationId: _episode),
      controller: c,
    );
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.onSelected == null),
      isTrue,
    );
    expect(
      tester
          .widgetList<FilterChip>(find.byType(FilterChip))
          .every((chip) => chip.onSelected == null),
      isTrue,
    );
    await tester.scrollUntilVisible(find.text('Reintentar guardado'), 250);
    await tester.pumpAndSettle();
    expect(find.text('Reintentar guardado'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Consultar fuentes'),
          )
          .onPressed,
      isNull,
    );
  });
}
