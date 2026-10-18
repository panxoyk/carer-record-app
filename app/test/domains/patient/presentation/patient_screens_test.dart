import 'dart:async';

import 'package:carer_record_app/domains/clinical_event/domain/entities/clinical_event.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_screens.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/domains/context_note/presentation/context_note_providers.dart';
import 'package:carer_record_app/domains/context_note/presentation/milestone_editor_sheet.dart';

const orgId = '00000000-0000-4000-8000-000000000001';
const hospitalizationId = '00000000-0000-4000-8000-000000000002';
const patientId = '00000000-0000-4000-8000-000000000003';
final episode = Patient(
  organizationId: orgId,
  hospitalizationId: hospitalizationId,
  patientId: patientId,
  hospitalizationStatus: 'active',
  admittedAt: DateTime.utc(2026),
  dischargedAt: null,
  unitId: 'secret-unit-uuid',
  bedLabel: '12',
  givenName: 'Ana',
  familyName: 'Prueba',
  birthDate: null,
);

Widget screen(Widget child, List<Override> overrides) => ProviderScope(
  key: UniqueKey(),
  overrides: overrides,
  child: MaterialApp(home: child),
);

void main() {
  testWidgets('closing milestone editor releases its active guard safely', (
    tester,
  ) async {
    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: () {},
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(container.read(milestoneEditorActiveProvider).active, isTrue);
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(container.read(milestoneEditorActiveProvider).active, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });

  testWidgets('internal root app bars use clinical title and colors', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(const PatientsScreen(), [
        patientsProvider.overrideWith((ref) async => const []),
      ]),
    );
    await tester.pumpAndSettle();
    final censusBar = tester.widget<AppBar>(find.byType(AppBar));
    final censusTitle = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Hospitalizaciones'),
    );
    expect(censusTitle, findsOneWidget);
    expect(censusBar.backgroundColor, ClinicalColors.canvas);
    expect(tester.widget<Text>(censusTitle).style?.color, ClinicalColors.ink);

    await tester.pumpWidget(
      screen(const SettingsScreen(), [
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
        sessionProvider.overrideWith((ref) => null),
      ]),
    );
    await tester.pumpAndSettle();
    final settingsBar = tester.widget<AppBar>(find.byType(AppBar));
    final settingsTitle = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Ajustes'),
    );
    expect(settingsTitle, findsOneWidget);
    expect(settingsBar.backgroundColor, ClinicalColors.canvas);
    expect(tester.widget<Text>(settingsTitle).style?.color, ClinicalColors.ink);
  });

  testWidgets('census ready searches name only and displays safe location', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(const PatientsScreen(), [
        patientsProvider.overrideWith((ref) async => [episode]),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ana Prueba'), findsOneWidget);
    expect(find.text('Cama 12'), findsOneWidget);
    expect(find.textContaining('secret-unit-uuid'), findsNothing);
    expect(find.textContaining(patientId), findsNothing);
    expect(find.textContaining(episode.hospitalizationId), findsNothing);
    expect(find.textContaining(episode.unitId!), findsNothing);
    await tester.enterText(find.byType(TextField), '12345678-9');
    await tester.pumpAndSettle();
    expect(find.text('Ana Prueba'), findsNothing);
  });

  testWidgets('census loading state is visible', (tester) async {
    final pending = Completer<List<Patient>>();
    await tester.pumpWidget(
      screen(const PatientsScreen(), [
        patientsProvider.overrideWith((ref) => pending.future),
      ]),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete([episode]);
    await tester.pumpAndSettle();
  });

  testWidgets('census navigation carries hospitalization id, not patient id', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/patients',
      routes: [
        GoRoute(path: '/patients', builder: (_, __) => const PatientsScreen()),
        GoRoute(
          path: '/hospitalizations/:hospitalizationId',
          builder: (_, state) =>
              Text('episode:${state.pathParameters['hospitalizationId']}'),
        ),
        GoRoute(
          path: '/hospitalizations/:hospitalizationId/details',
          builder: (_, state) =>
              Text('details:${state.pathParameters['hospitalizationId']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          patientsProvider.overrideWith((ref) async => [episode]),
          iamContextProvider.overrideWith(
            (ref) async => _iam({'clinical.timeline.read'}),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Prueba'));
    await tester.pumpAndSettle();
    expect(find.text('episode:$hospitalizationId'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets('census without timeline permission links to demographics only', (
    tester,
  ) async {
    final router = GoRouter(
      initialLocation: '/patients',
      routes: [
        GoRoute(path: '/patients', builder: (_, __) => const PatientsScreen()),
        GoRoute(
          path: '/hospitalizations/:hospitalizationId/details',
          builder: (_, state) =>
              Text('details:${state.pathParameters['hospitalizationId']}'),
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          patientsProvider.overrideWith((ref) async => [episode]),
          iamContextProvider.overrideWith(
            (ref) async =>
                _iam(const {'clinical.census.read', 'clinical.patient.read'}),
          ),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Prueba'));
    await tester.pumpAndSettle();
    expect(find.text('details:$hospitalizationId'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  testWidgets('census empty and error states are neutral', (tester) async {
    await tester.pumpWidget(
      screen(const PatientsScreen(), [
        patientsProvider.overrideWith((ref) async => const []),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No hay pacientes disponibles para tu acceso.'),
      findsOneWidget,
    );
    await tester.pumpWidget(
      screen(const PatientsScreen(), [
        patientsProvider.overrideWith(
          (ref) async => throw StateError('synthetic'),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('No fue posible cargar las hospitalizaciones.'),
      findsOneWidget,
    );
  });

  testWidgets('detail uses hospitalization key and shows summary timeline', (
    tester,
  ) async {
    final event = ClinicalEvent(
      organizationId: orgId,
      hospitalizationId: hospitalizationId,
      id: '00000000-0000-4000-8000-000000000004',
      patientId: patientId,
      kind: 'observation',
      occurredAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      summary: 'Texto resumido',
    );
    final olderEvent = ClinicalEvent(
      organizationId: orgId,
      hospitalizationId: hospitalizationId,
      id: '00000000-0000-4000-8000-000000000005',
      patientId: patientId,
      kind: 'observation',
      occurredAt: DateTime.utc(2025),
      createdAt: DateTime.utc(2025),
      summary: 'Resumen anterior',
    );
    await tester.pumpWidget(
      screen(const PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) async => [event, olderEvent]),
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
      ]),
    );
    await tester.pumpAndSettle();
    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    final title = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Bitácora'),
    );
    expect(title, findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.arrow_back_ios_new_rounded),
      ),
      findsOneWidget,
    );
    expect(
      tester.getCenter(find.text('Bitácora')).dy,
      closeTo(tester.getCenter(find.byType(IconButton).first).dy, 1),
    );
    expect(appBar.backgroundColor, ClinicalColors.canvas);
    expect(find.text('Texto resumido'), findsOneWidget);
    expect(find.textContaining(patientId), findsNothing);
    expect(find.textContaining(hospitalizationId), findsNothing);
    expect(find.textContaining(episode.unitId!), findsNothing);
    expect(
      find.textContaining('00000000-0000-4000-8000-000000000004'),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.text('Texto resumido')).dy,
      lessThan(tester.getTopLeft(find.text('Resumen anterior')).dy),
    );
    expect(find.text('Paciente no encontrado.'), findsNothing);
  });

  testWidgets('hidden hospitalization is not found', (tester) async {
    await tester.pumpWidget(
      screen(
        const PatientInformationScreen(
          hospitalizationId: '00000000-0000-4000-8000-000000000088',
        ),
        [
          patientProvider('00000000-0000-4000-8000-000000000088')
              .overrideWith((ref) async => null),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Paciente no encontrado.'), findsOneWidget);
  });

  testWidgets('detail loading and error states retire prior presentation', (
    tester,
  ) async {
    final pending = Completer<Patient?>();
    await tester.pumpWidget(
      screen(PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId)
            .overrideWith((ref) => pending.future),
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
      ]),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('synthetic'));
    await tester.pumpAndSettle();
    expect(
      find.text('No fue posible cargar la hospitalización.'),
      findsOneWidget,
    );
    expect(find.text('Ana Prueba'), findsNothing);
  });

  testWidgets('timeline loading and error states show no previous summary', (
    tester,
  ) async {
    final pending = Completer<List<ClinicalEvent>>();
    await tester.pumpWidget(
      screen(PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) => pending.future),
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
      ]),
    );
    await tester.pump();
    expect(find.text('Ana Prueba'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.completeError(StateError('synthetic'));
    await tester.pumpAndSettle();
    expect(find.text('No fue posible cargar los eventos.'), findsOneWidget);
    expect(find.text('summary-anterior'), findsNothing);
  });

  testWidgets('timeline empty state is neutral', (tester) async {
    await tester.pumpWidget(
      screen(PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) async => const []),
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('No hay eventos clínicos disponibles.'), findsOneWidget);
    expect(find.text('Ana Prueba'), findsOneWidget);
  });

  testWidgets('pull-to-refresh re-queries and replaces census rows', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<List<Patient>>();
    await tester.pumpWidget(
      screen(const PatientsScreen(), [
        patientsProvider.overrideWith((ref) {
          calls++;
          return calls == 1 ? Future.value([episode]) : pending.future;
        }),
      ]),
    );
    await tester.pumpAndSettle();
    expect(calls, 1);
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    expect(find.text('Ana Prueba'), findsNothing);
    pending.complete(const []);
    await tester.pumpAndSettle();
    expect(
      find.text('No hay pacientes disponibles para tu acceso.'),
      findsOneWidget,
    );
  });

  testWidgets('timeline refresh removes previous summary during requery', (
    tester,
  ) async {
    var calls = 0;
    final pending = Completer<List<ClinicalEvent>>();
    final event = ClinicalEvent(
      organizationId: orgId,
      hospitalizationId: hospitalizationId,
      id: '00000000-0000-4000-8000-000000000004',
      patientId: patientId,
      kind: 'observation',
      occurredAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      summary: 'Contenido revocado',
    );
    await tester.pumpWidget(
      screen(PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) {
              calls++;
              return calls == 1 ? Future.value([event]) : pending.future;
            }),
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Contenido revocado'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 350));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 2);
    expect(find.text('Contenido revocado'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    pending.complete(const []);
    await tester.pumpAndSettle();
    expect(find.text('No hay eventos clínicos disponibles.'), findsOneWidget);
  });

  testWidgets('milestone action appears only with create and confirm', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(const PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) async => const []),
        iamContextProvider.overrideWith(
          (ref) async =>
              _iam(const {'context.note.create', 'context.note.confirm'}),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_task_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());

    await tester.pumpWidget(
      screen(const PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) async => const []),
        iamContextProvider.overrideWith(
          (ref) async => _iam(const {'context.note.create'}),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_task_outlined), findsNothing);
  });

  testWidgets('milestone sheet offers text and dictation forms', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(const PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) async => const []),
        iamContextProvider.overrideWith(
          (ref) async =>
              _iam(const {'context.note.create', 'context.note.confirm'}),
        ),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_task_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Agregar hito a la bitácora'), findsOneWidget);
    expect(find.text('Texto'), findsOneWidget);
    expect(find.text('Dictado'), findsOneWidget);
    expect(find.text('Confirmar hito'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dictated milestone row shows the confirmed text and no player', (
    tester,
  ) async {
    final event = ClinicalEvent(
      organizationId: orgId,
      hospitalizationId: hospitalizationId,
      id: '00000000-0000-4000-8000-000000000006',
      patientId: patientId,
      kind: 'milestone_audio',
      occurredAt: DateTime.utc(2026),
      createdAt: DateTime.utc(2026),
      summary: 'Texto que la autora confirmó tras el dictado local.',
      sourceKind: 'context_note',
    );
    await tester.pumpWidget(
      screen(const PatientDetailScreen(hospitalizationId: hospitalizationId), [
        patientProvider(hospitalizationId).overrideWith((ref) async => episode),
        hospitalizationClinicalEventsProvider(hospitalizationId)
            .overrideWith((ref) async => [event]),
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
      ]),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Texto que la autora confirmó tras el dictado local.'),
      findsOneWidget,
    );
    expect(find.textContaining('Dictado local'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
    expect(find.byIcon(Icons.flag_outlined), findsOneWidget);
  });

  testWidgets('settings renders IAM context without practitioner role', (
    tester,
  ) async {
    await tester.pumpWidget(
      screen(const SettingsScreen(), [
        iamContextProvider.overrideWith((ref) async => _iam(const {})),
        sessionProvider.overrideWith((ref) => null),
      ]),
    );
    await tester.pumpAndSettle();
    expect(find.text('Synthetic user'), findsWidgets);
    expect(find.text('Synthetic hospital'), findsWidgets);
    expect(find.text('Rol'), findsNothing);
  });

  testWidgets(
    'settings lists institutional destinations allowed by effective permissions',
    (tester) async {
      await tester.pumpWidget(
        screen(const SettingsScreen(), [
          iamContextProvider.overrideWith(
            (ref) async =>
                _iam({'iam.membership.read', 'clinical.assignment.manage'}),
          ),
          sessionProvider.overrideWith((ref) => null),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('ADMINISTRACIÓN INSTITUCIONAL'), findsOneWidget);
      expect(find.text('Gestionar usuarios'), findsOneWidget);
      expect(find.text('Profesionales por hospitalización'), findsOneWidget);
      expect(find.text('Roles y permisos'), findsNothing);
    },
  );

  testWidgets(
    'settings hides the institutional section for clinical-only permissions',
    (tester) async {
      await tester.pumpWidget(
        screen(const SettingsScreen(), [
          iamContextProvider.overrideWith(
            (ref) async =>
                _iam({'clinical.census.read', 'clinical.patient.read'}),
          ),
          sessionProvider.overrideWith((ref) => null),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('ADMINISTRACIÓN INSTITUCIONAL'), findsNothing);
      expect(find.text('Gestionar usuarios'), findsNothing);
      expect(find.text('Roles y permisos'), findsNothing);
      expect(find.text('Profesionales por hospitalización'), findsNothing);
    },
  );
}

IamContext _iam(Set<String> permissions) => IamContext(
  organizationId: '00000000-0000-4000-8000-000000000010',
  organizationName: 'Synthetic hospital',
  profileId: '00000000-0000-4000-8000-000000000011',
  displayName: 'Synthetic user',
  profileStatus: 'active',
  membershipId: '00000000-0000-4000-8000-000000000012',
  membershipStatus: 'active',
  permissions: permissions,
);
