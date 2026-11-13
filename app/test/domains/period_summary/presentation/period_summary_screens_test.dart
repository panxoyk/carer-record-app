import 'package:carer_record_app/domains/on_device_ai/data/fake_synthesis_provider.dart';
import 'package:carer_record_app/domains/on_device_ai/presentation/local_ai_providers.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';
import 'package:carer_record_app/domains/period_summary/presentation/controllers/period_summary_controller.dart';
import 'package:carer_record_app/domains/period_summary/presentation/period_summary_providers.dart';
import 'package:carer_record_app/domains/period_summary/presentation/screens/period_summary_screens.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

const _episode = 'episode';
final _fixedNow = DateTime.utc(2026, 11, 12, 15);
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

PeriodSummary _summary({
  String content = 'Resumen clínico sintético.',
  SummaryWindow? window,
}) => PeriodSummary(
  id: 'summary',
  organizationId: 'org',
  hospitalizationId: _episode,
  patientId: 'patient',
  authorId: 'author',
  window:
      window ??
      SummaryWindow(
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
  Set<SummarySourceKind>? requestedKinds;
  SummaryWindow? requestedWindow;
  final attempts = <SummarySaveAttempt>[];
  bool failFirstSave = false;
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
  }) async {
    requestedKinds = selectedKinds;
    requestedWindow = window;
    return SummarySourceBatch(
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
  }

  @override
  Future<PeriodSummary> save(SummarySaveAttempt attempt) async {
    attempts.add(attempt);
    if (failFirstSave && attempts.length == 1) {
      throw const PeriodSummaryException('repository_unavailable');
    }
    return PeriodSummary(
      id: attempt.draft.id,
      organizationId: attempt.organizationId,
      hospitalizationId: attempt.hospitalizationId,
      patientId: attempt.patientId,
      authorId: 'author',
      window: attempt.window,
      generatedAt: attempt.draft.generatedAt,
      createdAt: attempt.draft.generatedAt,
      content: attempt.draft.prepared.content,
      modelVersion: attempt.draft.modelVersion,
      promptVersion: attempt.draft.promptVersion,
      selectedKinds: attempt.selectedKinds,
      excludedUndatedCount: attempt.draft.prepared.excludedUndatedCount,
      sources: attempt.draft.prepared.sources,
    );
  }

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
  _Repository? repository,
  DateTime Function()? clock,
  void Function()? onHistoryLoad,
}) async {
  final repo = repository ?? _Repository();
  final c =
      controller ??
      PeriodSummaryController(
        repository: repo,
        generator: PeriodSummaryGenerator(
          repository: repo,
          provider: FakeSynthesisProvider(),
          newId: () => 'id',
          clock: clock ?? DateTime.now,
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
        periodSummaryHistoryProvider.overrideWith((ref, key) async {
          onHistoryLoad?.call();
          return rows;
        }),
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
      child: onHistoryLoad == null
          ? MaterialApp.router(routerConfig: router)
          : Consumer(
              builder: (context, ref, _) {
                ref.watch(
                  periodSummaryHistoryProvider((
                    episodeId: _episode,
                    offset: 0,
                  )),
                );
                return MaterialApp.router(routerConfig: router);
              },
            ),
    ),
  );
  await tester.pumpAndSettle();
  return router;
}

class _SynthesisSpy implements SynthesisProvider {
  int calls = 0;
  final requests = <SynthesisRequest>[];
  @override
  bool get isAvailable => true;
  @override
  String get modelVersion => 'test-runtime';
  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    calls++;
    requests.add(request);
    return const SynthesisResult(
      text: 'Síntesis de prueba visible.',
      modelVersion: 'test-runtime',
      promptVersion: 'test-prompt',
    );
  }

  @override
  Future<void> dispose() async {}
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
    await tester.tap(find.textContaining('01/01/2026'));
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
  testWidgets(
    'detail presents the historical synthesis without source listings',
    (tester) async {
      await _mount(
        tester,
        const PeriodSummaryDetailScreen(
          hospitalizationId: _episode,
          summaryId: 'summary',
        ),
      );
      expect(find.textContaining('No es una nota clínica'), findsNothing);
      expect(find.textContaining('Generado:'), findsNothing);
      expect(find.textContaining('Zona horaria:'), findsNothing);
      expect(find.textContaining('Síntesis asistida:'), findsNothing);
      expect(find.text('Fuentes incluidas'), findsNothing);
      expect(find.text('Síntesis del periodo'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Publicar como nota'), findsNothing);
    },
  );
  testWidgets('hour range ending at local midnight retains its real hours', (
    tester,
  ) async {
    await _mount(
      tester,
      const PeriodSummaryDetailScreen(
        hospitalizationId: _episode,
        summaryId: 'summary',
      ),
      detail: _summary(
        window: SummaryWindow(
          fromUtc: DateTime.utc(2026, 1, 1, 21),
          toUtc: DateTime.utc(2026, 1, 2, 3),
          timezone: 'America/Santiago',
        ),
      ),
    );
    expect(
      find.textContaining('01/01/2026 18:00 – 02/01/2026 00:00'),
      findsOneWidget,
    );
  });
  testWidgets(
    'date range spanning DST formats inclusive end by calendar date',
    (tester) async {
      await _mount(
        tester,
        const PeriodSummaryDetailScreen(
          hospitalizationId: _episode,
          summaryId: 'summary',
        ),
        detail: _summary(
          window: SummaryWindow(
            fromUtc: DateTime.utc(2026, 4, 5, 4),
            toUtc: DateTime.utc(2026, 4, 6, 4),
            timezone: 'America/Santiago',
          ),
        ),
      );
      expect(find.textContaining('05/04/2026 – 05/04/2026'), findsOneWidget);
    },
  );
  testWidgets('generation screen contains date selection and synthesis board', (
    tester,
  ) async {
    await _mount(
      tester,
      GeneratePeriodSummaryScreen(
        hospitalizationId: _episode,
        clock: () => _fixedNow,
      ),
    );
    expect(find.byType(ChoiceChip), findsNWidgets(4));
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Últimas 24 h'), findsOneWidget);
    expect(find.text('Elegir fechas'), findsOneWidget);
    expect(find.textContaining('Seleccionar fechas'), findsNothing);
    expect(find.text('Consultar fuentes'), findsNothing);
    expect(find.textContaining('America/Santiago'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending save locks date selection and prevents regenerating', (
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
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Generar resumen'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .every((chip) => chip.onSelected == null),
      isTrue,
    );
    await tester.ensureVisible(find.text('Reintentar guardado'));
    await tester.pumpAndSettle();
    expect(find.text('Reintentar guardado'), findsOneWidget);
    expect(find.text('Guardado pendiente'), findsWidgets);
  });

  testWidgets(
    'date picker accepts a single date and does not open time picker',
    (tester) async {
      await _mount(
        tester,
        GeneratePeriodSummaryScreen(
          hospitalizationId: _episode,
          clock: () => _fixedNow,
        ),
        clock: () => _fixedNow,
      );
      await tester.tap(find.text('Elegir fechas'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_month));
      await tester.pumpAndSettle();
      final picker = tester.widget<DateRangePickerDialog>(
        find.byType(DateRangePickerDialog),
      );
      expect(picker.initialDateRange!.start, picker.initialDateRange!.end);
      expect(picker.currentDate, DateTime(2026, 11, 12));
      expect(find.byType(TimePickerDialog), findsNothing);
    },
  );

  testWidgets(
    'one tap generates all source kinds and shows saved output in place',
    (tester) async {
      final repo = _Repository();
      final synthesis = _SynthesisSpy();
      final controller = PeriodSummaryController(
        repository: repo,
        generator: PeriodSummaryGenerator(
          repository: repo,
          provider: synthesis,
          newId: () => 'stable-id',
          clock: () => _fixedNow,
        ),
        organizationId: 'org',
        hospitalizationId: _episode,
        canContinue: () => true,
      );
      final router = await _mount(
        tester,
        GeneratePeriodSummaryScreen(
          hospitalizationId: _episode,
          clock: () => _fixedNow,
        ),
        controller: controller,
        repository: repo,
        clock: () => _fixedNow,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Generar resumen'));
      await tester.pumpAndSettle();
      expect(synthesis.calls, 1);
      expect(repo.requestedKinds, SummarySourceKind.values.toSet());
      expect(repo.requestedWindow!.toUtc, _fixedNow);
      expect(
        repo.requestedWindow!.fromUtc,
        _fixedNow.subtract(const Duration(hours: 24)),
      );
      expect(controller.phase, PeriodSummaryPhase.saved);
      expect(find.text('Síntesis de prueba visible.'), findsOneWidget);
      expect(find.text('Guardado'), findsNothing);
      expect(find.textContaining('Zona horaria:'), findsNothing);
      expect(find.text(synthesis.requests.single.text), findsNothing);
      expect(router.routeInformationProvider.value.uri.path, '/test');
      expect(find.text('Consultar fuentes'), findsNothing);
    },
  );

  testWidgets('hour presets anchor exact UTC windows when generating', (
    tester,
  ) async {
    final repo = _Repository();
    final synthesis = _SynthesisSpy();
    final controller = PeriodSummaryController(
      repository: repo,
      generator: PeriodSummaryGenerator(
        repository: repo,
        provider: synthesis,
        newId: () => 'preset-id',
        clock: () => _fixedNow,
      ),
      organizationId: 'org',
      hospitalizationId: _episode,
      canContinue: () => true,
    );
    await _mount(
      tester,
      GeneratePeriodSummaryScreen(
        hospitalizationId: _episode,
        clock: () => _fixedNow,
      ),
      controller: controller,
      repository: repo,
      clock: () => _fixedNow,
    );
    for (final preset in [
      ('Últimas 6 h', 6),
      ('Últimas 12 h', 12),
      ('Últimas 24 h', 24),
    ]) {
      await tester.tap(find.text(preset.$1));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Generar resumen'));
      await tester.pumpAndSettle();
      expect(
        repo.requestedWindow!.fromUtc,
        _fixedNow.subtract(Duration(hours: preset.$2)),
      );
      expect(repo.requestedWindow!.toUtc, _fixedNow);
    }
    expect(find.textContaining('Zona horaria'), findsNothing);
    expect(find.textContaining('Generado:'), findsNothing);
    expect(find.textContaining('No es una nota clínica'), findsNothing);
  });

  testWidgets('result header keeps the generated window when clock advances', (
    tester,
  ) async {
    var now = _fixedNow;
    final repo = _Repository();
    final controller = PeriodSummaryController(
      repository: repo,
      generator: PeriodSummaryGenerator(
        repository: repo,
        provider: _SynthesisSpy(),
        newId: () => 'clock-id',
        clock: () => _fixedNow,
      ),
      organizationId: 'org',
      hospitalizationId: _episode,
      canContinue: () => true,
    );
    await _mount(
      tester,
      GeneratePeriodSummaryScreen(
        hospitalizationId: _episode,
        clock: () => now,
      ),
      controller: controller,
      repository: repo,
      clock: () => _fixedNow,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Generar resumen'));
    await tester.pumpAndSettle();
    final originalHeader = tester
        .widget<Text>(find.textContaining('Últimas 24 h ·'))
        .data;
    now = now.add(const Duration(days: 2));
    await tester.pump();
    expect(
      tester.widget<Text>(find.textContaining('Últimas 24 h ·')).data,
      originalHeader,
    );
  });

  testWidgets('save retry keeps generated result and does not infer again', (
    tester,
  ) async {
    final repo = _Repository()..failFirstSave = true;
    final synthesis = _SynthesisSpy();
    final controller = PeriodSummaryController(
      repository: repo,
      generator: PeriodSummaryGenerator(
        repository: repo,
        provider: synthesis,
        newId: () => 'stable-id',
        clock: () => _fixedNow,
      ),
      organizationId: 'org',
      hospitalizationId: _episode,
      canContinue: () => true,
    );
    await _mount(
      tester,
      GeneratePeriodSummaryScreen(
        hospitalizationId: _episode,
        clock: () => _fixedNow,
      ),
      controller: controller,
      repository: repo,
      clock: () => _fixedNow,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Generar resumen'));
    await tester.pumpAndSettle();
    final id = repo.attempts.single.draft.id;
    await tester.tap(find.text('Reintentar guardado'));
    await tester.pumpAndSettle();
    expect(synthesis.calls, 1);
    expect(repo.attempts.last.draft.id, id);
    expect(controller.phase, PeriodSummaryPhase.saved);
    expect(find.text('Síntesis de prueba visible.'), findsOneWidget);
  });

  testWidgets('successful save invalidates watched history', (tester) async {
    var historyLoads = 0;
    final repo = _Repository();
    final synthesis = _SynthesisSpy();
    final controller = PeriodSummaryController(
      repository: repo,
      generator: PeriodSummaryGenerator(
        repository: repo,
        provider: synthesis,
        newId: () => 'history-id',
        clock: () => _fixedNow,
      ),
      organizationId: 'org',
      hospitalizationId: _episode,
      canContinue: () => true,
    );
    await _mount(
      tester,
      GeneratePeriodSummaryScreen(
        hospitalizationId: _episode,
        clock: () => _fixedNow,
      ),
      controller: controller,
      repository: repo,
      clock: () => _fixedNow,
      onHistoryLoad: () => historyLoads++,
    );
    expect(historyLoads, 1);
    await tester.tap(find.widgetWithText(FilledButton, 'Generar resumen'));
    await tester.pumpAndSettle();
    expect(historyLoads, 2);
  });

  testWidgets('changing the selected dates clears the prior saved synthesis', (
    tester,
  ) async {
    final repo = _Repository();
    final controller = PeriodSummaryController(
      repository: repo,
      generator: PeriodSummaryGenerator(
        repository: repo,
        provider: _SynthesisSpy(),
        newId: () => 'dated-id',
        clock: () => _fixedNow,
      ),
      organizationId: 'org',
      hospitalizationId: _episode,
      canContinue: () => true,
    );
    await _mount(
      tester,
      GeneratePeriodSummaryScreen(
        hospitalizationId: _episode,
        clock: () => _fixedNow,
      ),
      controller: controller,
      repository: repo,
      clock: () => _fixedNow,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Generar resumen'));
    await tester.pumpAndSettle();
    expect(controller.saved, isNotNull);
    await tester.tap(find.text('Elegir fechas'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month));
    await tester.pumpAndSettle();
    await tester.tap(find.text('11').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('11').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(controller.saved, isNull);
    expect(
      find.text('La síntesis aparecerá aquí al generar el resumen.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'generation page remains usable at narrow width and enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(640, 1200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _mount(
        tester,
        const GeneratePeriodSummaryScreen(hospitalizationId: _episode),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
