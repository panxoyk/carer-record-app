import 'dart:async';

import 'package:carer_record_app/domains/clinical_event/domain/entities/clinical_event.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:carer_record_app/domains/patient/domain/entities/patient.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_screens.dart';
import 'package:carer_record_app/domains/fhir_record/domain/authorized_clinical_record.dart';
import 'package:carer_record_app/domains/fhir_record/presentation/fhir_record_providers.dart';
import 'package:carer_record_app/core/session/authorization_refresh.dart';
import 'package:carer_record_app/app/presentation/settings_screen.dart';
import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:carer_record_app/domains/institutional/domain/iam_entities.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/core/design_system/clinical_design_system.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/local_capability_repository.dart';
import 'package:carer_record_app/domains/on_device_ai/presentation/local_ai_providers.dart';
import 'package:carer_record_app/domains/context_note/presentation/context_note_providers.dart';
import 'package:carer_record_app/domains/context_note/presentation/milestone_editor_sheet.dart';
import 'package:carer_record_app/domains/context_note/data/context_note_repository.dart';
import 'package:carer_record_app/domains/context_note/data/draft_vault.dart';
import 'package:carer_record_app/domains/context_note/domain/entities/context_note.dart';
import 'package:carer_record_app/domains/context_note/domain/dictation_audio.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/asr_engine.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const orgId = '00000000-0000-4000-8000-000000000001';
const hospitalizationId = '00000000-0000-4000-8000-000000000002';
const patientId = '00000000-0000-4000-8000-000000000003';
final episode = Patient(
  organizationId: orgId,
  hospitalizationId: hospitalizationId,
  patientId: patientId,
  hospitalizationStatus: 'admitted',
  admittedAt: DateTime.utc(2026),
  dischargedAt: null,
  unitId: 'secret-unit-uuid',
  bedLabel: '12',
  givenName: 'Ana',
  familyName: 'Prueba',
  birthDate: null,
);

const _record = AuthorizedClinicalRecord(
  status: 'complete',
  truncated: false,
  freshness: ClinicalRecordFreshness(retrievedAt: '2026-01-01T00:00:00Z'),
  patient: ClinicalRecordPatient(id: 'fhir-3', name: 'Ana Prueba'),
  hospitalization: ClinicalHospitalization(
    id: hospitalizationId,
    status: 'admitted',
    admittedAt: '2026-01-01T00:00:00Z',
    bed: '12',
  ),
  sections: [],
  timeline: [],
);

Widget screen(Widget child, List<Override> overrides) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    authorizationRefreshProvider.overrideWithValue(() {}),
    authorizedClinicalTimelineProvider(hospitalizationId)
        .overrideWith((ref) async => _record),
    ...overrides,
  ],
  child: MaterialApp(theme: ClinicalTheme.build(), home: child),
);

void main() {
  testWidgets('context note sheet is usable on narrow and enlarged screens', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
    });
    for (final size in [const Size(320, 640), const Size(360, 640)]) {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      final repository = _FakeMilestoneRepository();
      final audio = _FakeDictationAudio();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(null),
            contextNoteRepositoryProvider.overrideWithValue(repository),
            draftVaultProvider.overrideWith((ref) => _FakeDraftVault()),
            dictationAudioFactoryProvider.overrideWithValue(() => audio),
            asrEngineProvider.overrideWith((ref) async => null),
            synthesisProviderProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: ClinicalTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showMilestoneEditorSheet(
                    context,
                    patient: episode,
                    onSaved: (_) {},
                  ),
                  child: const Text('Open context note'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open context note'));
      await tester.pumpAndSettle();
      expect(find.text('Nueva nota de contexto'), findsOneWidget);
      // Selection is audio by default, but opening the sheet never records.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Iniciar dictado'), findsOneWidget);
      expect(audio.startCalls, 0);
      final selector = tester.widget<SegmentedButton<MilestoneInputMethod>>(
        find.byType(SegmentedButton<MilestoneInputMethod>),
      );
      expect(selector.segments.map((segment) => segment.value), [
        MilestoneInputMethod.audio,
        MilestoneInputMethod.text,
      ]);
      expect(find.text('Escribir o dictar'), findsNothing);
      expect(find.text('Contenido de la nota'), findsNothing);
      expect(
        find.textContaining('Al guardar, la nota confirmada se incorpora'),
        findsNothing,
      );
      expect(
        find.text('El dictado no está disponible. Puedes escribir la nota.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      expect(
        MediaQuery.textScalerOf(tester.element(find.byType(TextField)))
            .scale(10),
        20,
      );
      expect(find.textContaining('marcas de tiempo'), findsNothing);
      expect(tester.takeException(), isNull);

      await tester.enterText(find.byType(TextField), 'Borrador accesible');
      tester.view.viewInsets = const FakeViewPadding(bottom: 280);
      await tester.pumpAndSettle();
      final fieldContext = tester.element(find.byType(TextField));
      expect(MediaQuery.viewInsetsOf(fieldContext).bottom, 280);
      await tester.ensureVisible(find.text('Guardar nota'));
      expect(
        tester.getRect(find.text('Guardar nota')).bottom,
        lessThanOrEqualTo(size.height - 280),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Guardar nota'));
      await tester.pumpAndSettle();
      expect(repository.saved, hasLength(1));
      expect(repository.saved.single.content, 'Borrador accesible');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('milestone text enables save and successful save closes once', (
    tester,
  ) async {
    final repository = _FakeMilestoneRepository();
    final vault = _FakeDraftVault();
    var savedCalls = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(null),
          contextNoteRepositoryProvider.overrideWithValue(repository),
          draftVaultProvider.overrideWithValue(vault),
          asrEngineProvider.overrideWith((ref) async => null),
          synthesisProviderProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: ClinicalTheme.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: (_) => savedCalls++,
                ),
                child: const Text('Open milestone'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open milestone'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Texto'));
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(
            find.ancestor(
              of: find.text('Guardar nota'),
              matching: find.byType(FilledButton),
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.enterText(find.byType(TextField), '  Hito sintético  ');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.ensureVisible(find.text('Guardar nota'));
    await tester.tap(find.text('Guardar nota'));
    await tester.pumpAndSettle();
    expect(repository.saved.single.content, 'Hito sintético');
    expect(savedCalls, 1);
    expect(find.text('Nueva nota de contexto'), findsNothing);
  });

  testWidgets('switching text and dictation modes preserves the text draft', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(null),
          contextNoteRepositoryProvider.overrideWithValue(
            _FakeMilestoneRepository(),
          ),
          draftVaultProvider.overrideWith((ref) => _FakeDraftVault()),
          asrEngineProvider.overrideWith((ref) async => null),
          synthesisProviderProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: ClinicalTheme.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: (_) {},
                ),
                child: const Text('Open context note'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open context note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Borrador que permanece');
    await tester.ensureVisible(find.text('Dictado'));
    await tester.tap(find.text('Dictado'));
    await tester.pumpAndSettle();
    expect(
      find.text('El dictado no está disponible. Puedes escribir la nota.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Borrador que permanece',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('local model check errors do not block text notes', (
    tester,
  ) async {
    final repository = _FakeMilestoneRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(null),
          contextNoteRepositoryProvider.overrideWithValue(repository),
          draftVaultProvider.overrideWith((ref) => _FakeDraftVault()),
          asrEngineProvider.overrideWith(
            (ref) async => throw StateError('asr'),
          ),
          synthesisProviderProvider.overrideWith(
            (ref) async => throw StateError('assistance'),
          ),
        ],
        child: MaterialApp(
          theme: ClinicalTheme.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: (_) {},
                ),
                child: const Text('Open context note'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open context note'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dictado'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No se pudo comprobar el dictado'),
      findsNothing,
    );
    expect(
      find.text('El dictado no está disponible. Puedes escribir la nota.'),
      findsOneWidget,
    );
    expect(find.text('Ayuda de redacción no disponible.'), findsOneWidget);
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Nota sin modelos locales');
    await tester.pump();
    await tester.ensureVisible(find.text('Guardar nota'));
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Guardar nota'));
    await tester.pumpAndSettle();
    expect(repository.saved.single.content, 'Nota sin modelos locales');
    expect(tester.takeException(), isNull);
  });

  testWidgets('local model loading keeps the textual editor available', (
    tester,
  ) async {
    final asr = Completer<AsrEngine?>();
    final assistance = Completer<SynthesisProvider?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(null),
          contextNoteRepositoryProvider.overrideWithValue(
            _FakeMilestoneRepository(),
          ),
          draftVaultProvider.overrideWith((ref) => _FakeDraftVault()),
          asrEngineProvider.overrideWith((ref) => asr.future),
          synthesisProviderProvider.overrideWith((ref) => assistance.future),
        ],
        child: MaterialApp(
          theme: ClinicalTheme.build(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: (_) {},
                ),
                child: const Text('Open context note'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open context note'));
    await tester.pump();
    expect(find.text('Comprobando el dictado…'), findsNothing);
    expect(find.text('Comprobando la ayuda de redacción…'), findsNothing);
    asr.complete(null);
    assistance.complete(null);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Texto'));
    await tester.tap(find.text('Texto'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.ensureVisible(find.text('Dictado'));
    await tester.tap(find.text('Dictado'));
    await tester.pumpAndSettle();
    expect(
      find.text('El dictado no está disponible. Puedes escribir la nota.'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('narrow enlarged dictation reviews transcript provenance', (
    tester,
  ) async {
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    final transcription = Completer<AsrTranscript>();
    final audio = _FakeDictationAudio();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(null),
          contextNoteRepositoryProvider.overrideWithValue(
            _FakeMilestoneRepository(),
          ),
          draftVaultProvider.overrideWith((ref) => _FakeDraftVault()),
          dictationAudioFactoryProvider.overrideWithValue(() => audio),
          asrEngineProvider.overrideWith(
            (ref) async => _PendingAsrEngine(transcription.future),
          ),
          synthesisProviderProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: ClinicalTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: (_) {},
                ),
                child: const Text('Open context note'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open context note'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Dictado'));
    await tester.tap(find.text('Dictado'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Iniciar dictado'));
    expect(audio.startCalls, 0);
    await tester.tap(find.text('Iniciar dictado'));
    await tester.pumpAndSettle();
    expect(audio.startCalls, 1);
    expect(find.text('Grabando…'), findsOneWidget);
    await tester.ensureVisible(find.text('Detener dictado'));
    await tester.tap(find.text('Detener dictado'));
    await tester.pump();
    expect(find.text('Transcribiendo…'), findsOneWidget);
    transcription.complete(
      const AsrTranscript(
        text: 'Transcripción de prueba',
        metadata: TranscriptionMetadata(
          engine: 'engine-local-extenso',
          model: 'modelo local de prueba con nombre extenso',
          pipelineVersion: '1',
          lowConfidenceSegments: [
            LowConfidenceSegment(startMs: 0, endMs: 100, confidence: 0.2),
          ],
        ),
        lowConfidenceSegments: [
          LowConfidenceSegment(startMs: 0, endMs: 100, confidence: 0.2),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Transcripción de prueba'), findsOneWidget);
    expect(find.textContaining('engine-local-extenso'), findsNothing);
    expect(find.textContaining('modelo local de prueba'), findsNothing);
    expect(find.text('Escribir o dictar'), findsNothing);
    expect(find.text('Contenido de la nota'), findsNothing);
    expect(
      find.textContaining('se procesan en este dispositivo'),
      findsNothing,
    );
    expect(find.textContaining('no se envían'), findsNothing);
    expect(find.text('Revisa el texto antes de guardar.'), findsNothing);
    expect(
      find.text('Algunas palabras pueden ser incorrectas. Revisa el texto.'),
      findsOneWidget,
    );
    expect(find.textContaining('0:00'), findsNothing);
    expect(find.text('Revisa el texto antes de guardar.'), findsNothing);
    expect(find.text('Escuchar'), findsOneWidget);
    await tester.ensureVisible(find.text('Escuchar'));
    await tester.tap(find.text('Escuchar'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow enlarged text assistance applies a reviewable suggestion',
    (tester) async {
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(null),
            contextNoteRepositoryProvider.overrideWithValue(
              _FakeMilestoneRepository(),
            ),
            draftVaultProvider.overrideWith((ref) => _FakeDraftVault()),
            asrEngineProvider.overrideWith((ref) async => null),
            synthesisProviderProvider.overrideWith(
              (ref) async => _FakeSynthesisProvider(),
            ),
          ],
          child: MaterialApp(
            theme: ClinicalTheme.build(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showMilestoneEditorSheet(
                    context,
                    patient: episode,
                    onSaved: (_) {},
                  ),
                  child: const Text('Open context note'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open context note'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Texto inicial de prueba');
      await tester.pump();
      await tester.ensureVisible(find.text('Mejorar redacción'));
      await tester.tap(find.text('Mejorar redacción'));
      await tester.pumpAndSettle();
      expect(find.text('Texto sugerido revisable'), findsOneWidget);
      expect(
        find.text('Revisa la sugerencia antes de guardarla.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'uncertain save failure retains draft and does not report success',
    (tester) async {
      final repository = _FakeMilestoneRepository()
        ..failure = StateError('remote');
      var savedCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(null),
            contextNoteRepositoryProvider.overrideWithValue(repository),
            draftVaultProvider.overrideWithValue(_FakeDraftVault()),
            asrEngineProvider.overrideWith((ref) async => null),
            synthesisProviderProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: ClinicalTheme.build(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showMilestoneEditorSheet(
                    context,
                    patient: episode,
                    onSaved: (_) => savedCalls++,
                  ),
                  child: const Text('Open milestone'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open milestone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Borrador conservado');
      await tester.pump();
      await tester.ensureVisible(find.text('Guardar nota'));
      await tester.tap(find.text('Guardar nota'));
      await tester.pumpAndSettle();
      expect(find.text('Nueva nota de contexto'), findsOneWidget);
      expect(repository.attempted, hasLength(1));
      expect(
        find.byKey(const Key('milestone-operation-error')),
        findsOneWidget,
      );
      expect(
        find.text(
          'No pudimos confirmar el guardado. Puedes reintentar la misma nota.',
        ),
        findsOneWidget,
      );
      expect(find.text('No se pudo confirmar el guardado.'), findsOneWidget);
      expect(find.text('Reintentar guardado'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).readOnly, isTrue);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Borrador conservado',
      );
      expect(repository.saved, isEmpty);
      expect(savedCalls, 0);

      await tester.pump(const Duration(seconds: 5));
      expect(find.text('No se pudo confirmar el guardado.'), findsNothing);
      expect(
        find.text(
          'No pudimos confirmar el guardado. Puedes reintentar la misma nota.',
        ),
        findsOneWidget,
      );
      repository.failure = null;
      await tester.ensureVisible(find.text('Reintentar guardado'));
      await tester.tap(find.text('Reintentar guardado'));
      await tester.pumpAndSettle();
      expect(repository.attempted, hasLength(2));
      expect(
        repository.attempted[1].clientEventId,
        repository.attempted[0].clientEventId,
      );
      expect(repository.saved.single.content, 'Borrador conservado');
      expect(savedCalls, 1);
    },
  );

  testWidgets(
    'text-only persistence succeeds without temporary audio cleanup',
    (tester) async {
      final repository = _FakeMilestoneRepository();
      final vault = _FakeDraftVault()..failure = StateError('purge');
      var savedResult = <bool>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWithValue(null),
            contextNoteRepositoryProvider.overrideWithValue(repository),
            draftVaultProvider.overrideWithValue(vault),
            asrEngineProvider.overrideWith((ref) async => null),
            synthesisProviderProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: ClinicalTheme.build(),
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => showMilestoneEditorSheet(
                    context,
                    patient: episode,
                    onSaved: (pending) => savedResult.add(pending),
                  ),
                  child: const Text('Open milestone'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open milestone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Texto'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Guardado confirmado');
      await tester.pump();
      await tester.ensureVisible(find.text('Guardar nota'));
      await tester.tap(find.text('Guardar nota'));
      await tester.pumpAndSettle();
      expect(repository.saved, hasLength(1));
      expect(savedResult, [false]);
      expect(find.text('Nueva nota de contexto'), findsNothing);
      expect(vault.purgeCalls, 0);
    },
  );

  testWidgets('audio cleanup failure reports persisted save exactly once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1;
    final repository = _FakeMilestoneRepository();
    final vault = _FakeDraftVault()..failure = StateError('purge');
    final audio = _FakeDictationAudio();
    final engine = _FakeAsrEngine();
    var savedResults = <bool>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionProvider.overrideWithValue(null),
          contextNoteRepositoryProvider.overrideWithValue(repository),
          draftVaultProvider.overrideWithValue(vault),
          dictationAudioFactoryProvider.overrideWithValue(() => audio),
          asrEngineProvider.overrideWith((ref) async => engine),
          synthesisProviderProvider.overrideWith((ref) async => null),
        ],
        child: MaterialApp(
          theme: ClinicalTheme.build(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(0.75)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: savedResults.add,
                ),
                child: const Text('Open milestone'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open milestone'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dictado'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mic_none));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.stop));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Audio transcrito',
    );
    expect(find.textContaining('fake'), findsNothing);
    expect(find.textContaining('Modelo local sintético'), findsNothing);
    expect(find.text('Escuchar'), findsOneWidget);
    await tester.ensureVisible(find.text('Guardar nota'));
    await tester.tap(find.text('Guardar nota'));
    await tester.pumpAndSettle();
    expect(repository.saved, hasLength(1));
    expect(repository.saved.single.inputMethod, MilestoneInputMethod.audio);
    expect(repository.saved.single.transcription?.engine, 'fake');
    expect(
      repository.saved.single.transcription?.model,
      'Modelo local sintético extenso',
    );
    expect(savedResults, [true]);
    expect(vault.purgeCalls, 1);
    expect(find.text('Nueva nota de contexto'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(savedResults, [true]);
    await tester.pumpWidget(const SizedBox.shrink());
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('closing milestone editor releases its active guard safely', (
    tester,
  ) async {
    final container = ProviderContainer();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ClinicalTheme.build(),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showMilestoneEditorSheet(
                  context,
                  patient: episode,
                  onSaved: (_) {},
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
    expect(
      container
          .read(localCapabilityUsageProvider)
          .isInUse(LocalCapability.transcription),
      isTrue,
    );
    expect(
      container
          .read(localCapabilityUsageProvider)
          .isInUse(LocalCapability.textAssistance),
      isTrue,
    );
    await tester.tap(find.text('Descartar'));
    await tester.pumpAndSettle();
    expect(
      container
          .read(localCapabilityUsageProvider)
          .isInUse(LocalCapability.transcription),
      isFalse,
    );
    expect(
      container
          .read(localCapabilityUsageProvider)
          .isInUse(LocalCapability.textAssistance),
      isFalse,
    );
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
    expect(find.textContaining('Cama 12'), findsOneWidget);
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
    expect(find.text('Reintentar carga de hospitalización'), findsOneWidget);
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
    expect(
      find.text('No fue posible cargar las notas de contexto.'),
      findsOneWidget,
    );
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
    expect(find.text('No hay eventos disponibles.'), findsOneWidget);
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
    expect(find.text('No hay eventos disponibles.'), findsOneWidget);
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
    expect(find.text('Nueva nota de contexto'), findsOneWidget);
    expect(find.text('Texto'), findsOneWidget);
    expect(find.text('Dictado'), findsOneWidget);
    expect(find.text('Guardar nota'), findsOneWidget);
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
    expect(find.textContaining('Nota de contexto'), findsOneWidget);
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

class _FakeMilestoneRepository extends ContextNoteRepository {
  _FakeMilestoneRepository() : super(_NoopSupabaseClient());

  final saved = <ContextNoteMilestone>[];
  final attempted = <ContextNoteMilestone>[];
  Object? failure;

  @override
  Future<void> saveMilestone(ContextNoteMilestone milestone) async {
    attempted.add(milestone);
    if (failure != null) throw failure!;
    saved.add(milestone);
  }
}

class _NoopSupabaseClient implements SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeDraftVault extends DraftVault {
  Object? failure;
  int purgeCalls = 0;

  @override
  Future<void> registerCapture(
    String operationId,
    String recordingPath,
  ) async {}

  @override
  Future<void> putDraft(
    String operationId, {
    required String transcription,
    required String recordingPath,
  }) async {}

  @override
  Future<void> purge(String operationId, {String? recordingPath}) async {
    purgeCalls++;
    if (failure != null) throw failure!;
  }
}

class _FakeDictationAudio implements DictationAudio {
  int startCalls = 0;
  @override
  Future<bool> requestPermission() async => true;
  @override
  Future<String> prepareSandboxPath(String operationId) async =>
      '/fake/$operationId.wav';
  @override
  Future<void> startPcm16(String path) async => startCalls++;
  @override
  Future<String?> stop() async => null;
  @override
  Future<String> prepareWav(String path) async => path;
  @override
  Future<bool> togglePreview(String path) async => true;
  @override
  Future<void> stopPreview() async {}
  @override
  Future<void> dispose() async {}
}

class _FakeAsrEngine implements AsrEngine {
  @override
  bool get isAvailable => true;
  @override
  String get engineId => 'fake';
  @override
  Future<AsrTranscript> transcribe(String wavPath) async => AsrTranscript(
    text: 'Audio transcrito',
    metadata: const TranscriptionMetadata(
      engine: 'fake',
      model: 'Modelo local sintético extenso',
      pipelineVersion: '1',
    ),
  );
}

class _PendingAsrEngine implements AsrEngine {
  _PendingAsrEngine(this.result);

  final Future<AsrTranscript> result;

  @override
  bool get isAvailable => true;

  @override
  String get engineId => 'pending-local-engine';

  @override
  Future<AsrTranscript> transcribe(String wavPath) => result;
}

class _FakeSynthesisProvider implements SynthesisProvider {
  @override
  bool get isAvailable => true;

  @override
  String get modelVersion => 'synthetic-model-1';

  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async => const SynthesisResult(
    text: 'Texto sugerido revisable',
    modelVersion: 'synthetic-model-1',
    promptVersion: 'test-prompt-1',
  );

  @override
  Future<void> dispose() async {}
}
