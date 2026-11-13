import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/core/navigation/current_hospitalization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _app({String? hospitalizationId, VoidCallback? onRecord}) {
  final router = GoRouter(
    initialLocation: '/patients',
    routes: [
      GoRoute(
        path: '/patients',
        builder: (_, __) => Scaffold(
          extendBody: true,
          body: Center(
            child: TextButton(onPressed: () {}, child: const Text('Contenido')),
          ),
          bottomNavigationBar: ClinicalBottomNavigation(
            current: ClinicalTab.cases,
            onRecord: onRecord,
          ),
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (_, __) => const Text('Pantalla de ajustes'),
      ),
      GoRoute(
        path: '/hospitalizations/:id',
        builder: (_, state) => Text('Bitácora ${state.pathParameters['id']}'),
      ),
      GoRoute(
        path: '/hospitalizations/:id/handoff',
        builder: (_, state) => Text('Entrega ${state.pathParameters['id']}'),
      ),
    ],
  );
  return ProviderScope(
    overrides: [
      currentHospitalizationProvider.overrideWith((ref) => hospitalizationId),
    ],
    child: MaterialApp.router(
      theme: ClinicalTheme.build(),
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('bar keeps its own height and does not block the screen', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(ClinicalBottomNavigation));
    expect(bar.height, lessThan(140));
    // Content in the middle of the screen still receives taps.
    final center = tester.getCenter(find.text('Contenido'));
    expect(
      tester
          .hitTestOnBinding(center)
          .path
          .any(
            (entry) =>
                entry.target == tester.renderObject(find.byType(TextButton)),
          ),
      isTrue,
    );
  });

  testWidgets('patient tabs stay disabled until an episode was opened', (
    tester,
  ) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    for (final label in ['Casos', 'Bitácora', 'Entrega', 'Ajustes']) {
      expect(find.text(label), findsOneWidget);
    }
    await tester.tap(find.text('Bitácora'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Bitácora '), findsNothing);
    expect(find.byTooltip('Registrar evento'), findsNothing);

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Pantalla de ajustes'), findsOneWidget);
  });

  testWidgets('patient tabs open the last episode and record is optional', (
    tester,
  ) async {
    var recorded = 0;
    await tester.pumpWidget(
      _app(hospitalizationId: 'episode-1', onRecord: () => recorded++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Registrar evento'));
    expect(recorded, 1);
    await tester.tap(find.text('Entrega'));
    await tester.pumpAndSettle();
    expect(find.text('Entrega episode-1'), findsOneWidget);
  });
}
