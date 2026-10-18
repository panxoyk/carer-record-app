import 'dart:async';
import 'dart:io';

import 'package:carer_record_app/domains/context_note/data/asr_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/llm_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/domain/local_capability_repository.dart';
import 'package:carer_record_app/domains/context_note/presentation/context_note_providers.dart';
import 'package:carer_record_app/domains/context_note/presentation/model_setup_screen.dart';
import 'package:carer_record_app/domains/context_note/presentation/model_management_screen.dart';
import 'package:carer_record_app/domains/context_note/presentation/model_setup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// The repository ships manifests and no blobs. This screen is what turns a
/// fresh clone into a working device, and these tests pin the two properties
/// that matter: the clinician sees what is being fetched and why, and a failed
/// or declined download never blocks the clinical record.
void main() {
  const speechManifest = AsrModelManifest(
    id: 'sherpa-onnx-whisper-base',
    family: 'whisper',
    language: 'es',
    engine: 'sherpa_onnx',
    engineVersion: '1.13.8',
    version: 'base-int8',
    license: 'MIT',
    sourceUrl: 'https://example.test/asr-models',
    archiveSha256: 'aa',
    archiveBytes: 200,
    parts: {'encoder': 'e', 'decoder': 'd', 'tokens': 't'},
    files: [AsrModelFile(name: 'e', sha256: 'e', bytes: 100)],
    parameters: {},
  );

  const writingManifest = LlmModelManifest(
    id: 'qwen3',
    runtime: 'llamadart',
    runtimeVersion: '0.11.1',
    language: 'es',
    license: 'Apache-2.0',
    sourceUrl: 'https://example.test/llm',
    file: 'q.gguf',
    fileName: 'q.gguf',
    sha256: 'bb',
    bytes: 500,
    parameters: {},
  );

  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('setup-screen-');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  Widget mount(ProviderContainer container) => UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: ModelSetupScreen()),
  );

  Widget mountManagement(ProviderContainer container) =>
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ModelManagementScreen()),
      );

  /// Tall enough that the whole column is laid out, so assertions do not depend
  /// on what a ListView happens to have built.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  ProviderContainer containerWith(
    FakeCapabilityRepository repository, {
    DateTime Function()? clock,
  }) {
    final container = ProviderContainer(
      overrides: [
        localCapabilityRepositoryProvider.overrideWith(
          (ref) async => repository,
        ),
        asrModelManifestProvider.overrideWith((ref) async => speechManifest),
        llmModelManifestProvider.overrideWith((ref) async => writingManifest),
        asrModelDirectoryProvider.overrideWith(
          (ref) async => Directory('${root.path}/asr'),
        ),
        llmModelDirectoryProvider.overrideWith(
          (ref) async => Directory('${root.path}/llm'),
        ),
        // Installing invalidates the cached engines so they pick up the new
        // weights. Stubbed here: the real ones reach for path_provider, which
        // has no platform behind a widget test.
        asrEngineProvider.overrideWith((ref) async => null),
        synthesisProviderProvider.overrideWith((ref) async => null),
        if (clock != null) modelSetupClockProvider.overrideWithValue(clock),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('offers both models with their licence and size', (tester) async {
    await tester.pumpWidget(mount(containerWith(FakeCapabilityRepository())));
    await tester.pumpAndSettle();

    expect(find.text('Dictado de hitos'), findsOneWidget);
    expect(find.text('Mejora de redacción'), findsOneWidget);
    expect(find.textContaining('MIT'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.textContaining('Pendiente'), findsNWidgets(2));
  });

  testWidgets('startup inventory failure offers retry and skip', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository()
      ..queryError = StateError('disco no disponible');
    final container = containerWith(repository);
    await tester.pumpWidget(mount(container));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se pudo comprobar el estado de la descarga. Inténtalo de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('Ahora no'), findsOneWidget);
    expect(repository.installed, isEmpty);

    repository.queryError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Dictado de hitos'), findsOneWidget);
  });

  testWidgets('refresh query failure blocks install until retry succeeds', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository();
    final container = containerWith(repository);
    await tester.pumpWidget(mount(container));
    await tester.pumpAndSettle();
    expect(find.text('Dictado de hitos'), findsOneWidget);

    repository.queryError = StateError('inventario no disponible');
    await container.read(modelSetupControllerProvider.notifier).refresh();
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se pudo comprobar el estado de la descarga. Inténtalo de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);

    await container.read(modelSetupControllerProvider.notifier).installAll();
    expect(repository.installed, isEmpty);

    repository.queryError = null;
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'No se pudo comprobar el estado de la descarga. Inténtalo de nuevo.',
      ),
      findsNothing,
    );
    await tester.tap(find.text('Descargar 0 MB'));
    await tester.pumpAndSettle();
    expect(
      repository.installed,
      containsAll([
        LocalCapability.transcription,
        LocalCapability.textAssistance,
      ]),
    );
  });

  testWidgets('reports progress and finishes ready once installed', (
    tester,
  ) async {
    useTallSurface(tester);
    final gate = Completer<void>();
    var now = DateTime.utc(2026);
    final repository = FakeCapabilityRepository(
      onInstall: (capability) async* {
        yield LocalModelProgress(
          capability: capability,
          status: LocalCapabilityStatus.installing,
          stage: LocalModelProgressStage.downloading,
          fraction: 0.5,
          receivedBytes: 50,
          totalBytes: 100,
        );
        now = now.add(const Duration(seconds: 2));
        yield LocalModelProgress(
          capability: capability,
          status: LocalCapabilityStatus.installing,
          stage: LocalModelProgressStage.downloading,
          fraction: 0.75,
          receivedBytes: 75,
          totalBytes: 100,
        );
        // Held open so the mid-flight frame is observable instead of racing
        // straight to the finished state.
        await gate.future;
        yield LocalModelProgress(
          capability: capability,
          status: LocalCapabilityStatus.ready,
          stage: LocalModelProgressStage.installing,
          fraction: 1,
        );
      },
    );
    final container = containerWith(repository, clock: () => now);
    await tester.pumpWidget(mount(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Descargar 0 MB'));
    await tester.pump();
    expect(find.text('Descargando'), findsWidgets);
    expect(find.text('Calculando tiempo restante…'), findsNothing);
    expect(find.textContaining('Tiempo restante: 2 s'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Listo'), findsNWidgets(2));
    expect(find.text('Continuar'), findsOneWidget);
    expect(container.read(setupAwaitingContinueProvider), isTrue);
    expect(
      repository.installed,
      containsAll([
        LocalCapability.transcription,
        LocalCapability.textAssistance,
      ]),
    );
  });

  testWidgets('a failed download leaves the screen usable and retryable', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository(
      onInstall: (capability) async* {
        if (capability == LocalCapability.transcription) {
          throw const FormatException('sin red');
        }
        yield LocalModelProgress(
          capability: capability,
          status: LocalCapabilityStatus.ready,
          stage: LocalModelProgressStage.installing,
          fraction: 1,
        );
      },
    );
    await tester.pumpWidget(mount(containerWith(repository)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Descargar 0 MB'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'No se pudo descargar el modelo. Comprueba tu conexión e inténtalo de nuevo.',
      ),
      findsOneWidget,
    );
    expect(find.text('Error'), findsOneWidget);
    // The clinical record stays reachable no matter what the download did.
    expect(find.text('Ahora no'), findsOneWidget);
    // And the other model still installed rather than being abandoned.
    expect(repository.installed, contains(LocalCapability.textAssistance));
  });

  testWidgets(
    'download progress shows byte count percent and calculated ETA, then clears ETA outside download',
    (tester) async {
      useTallSurface(tester);
      final gate = Completer<void>();
      final repository = FakeCapabilityRepository(
        onInstall: (capability) async* {
          yield LocalModelProgress(
            capability: capability,
            status: LocalCapabilityStatus.installing,
            stage: LocalModelProgressStage.downloading,
            fraction: 0.5,
            receivedBytes: 50,
            totalBytes: 100,
          );
          await gate.future;
          yield LocalModelProgress(
            capability: capability,
            status: LocalCapabilityStatus.installing,
            stage: LocalModelProgressStage.installing,
            fraction: 1,
            receivedBytes: 100,
            totalBytes: 100,
          );
        },
      );
      await tester.pumpWidget(mount(containerWith(repository)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descargar 0 MB'));
      await tester.pump();
      expect(find.textContaining('0 KB / 0 KB · 50 %'), findsOneWidget);
      expect(
        find.textContaining('Calculando tiempo restante…'),
        findsOneWidget,
      );
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Preparando dictado…'), findsWidgets);
      expect(find.textContaining('Calculando tiempo restante…'), findsNothing);
      expect(find.textContaining('100 %'), findsNothing);
    },
  );

  testWidgets('never blocks the record: the skip action is always offered', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(mount(containerWith(FakeCapabilityRepository())));
    await tester.pumpAndSettle();

    expect(find.text('Ahora no'), findsOneWidget);
  });

  testWidgets('skip records the choice before leaving setup', (tester) async {
    useTallSurface(tester);
    final container = containerWith(FakeCapabilityRepository());
    await tester.pumpWidget(mount(container));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ahora no'));
    expect(tester.takeException(), isA<AssertionError>());
    expect(container.read(modelSetupSkippedProvider), isTrue);
    expect(container.read(setupAwaitingContinueProvider), isFalse);
  });

  testWidgets('states that nothing clinical is downloaded', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(mount(containerWith(FakeCapabilityRepository())));
    await tester.pumpAndSettle();

    expect(
      find.textContaining(
        'La descarga contiene solo modelos de IA, no información clínica.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('manager shows both models and can decline a clean', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository()
      ..ready.addAll(LocalCapability.values);
    await tester.pumpWidget(mountManagement(containerWith(repository)));
    await tester.pumpAndSettle();

    expect(find.text('Dictado y redacción'), findsOneWidget);
    expect(find.text('Comprobar descarga'), findsNWidgets(2));
    expect(find.text('Comprobar de nuevo'), findsNothing);

    await tester.tap(find.text('Limpiar').first);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('se requiere conexión a internet'),
      findsOneWidget,
    );
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Limpiar'),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.ready, {LocalCapability.textAssistance});
    expect(repository.cleaned, [LocalCapability.transcription]);
    expect(repository.installed, isEmpty);
  });

  testWidgets('manager cannot clean a model while milestone editor is active', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository()
      ..ready.addAll(LocalCapability.values);
    final container = containerWith(repository);
    await tester.pumpWidget(mountManagement(container));
    await tester.pumpAndSettle();
    container.read(milestoneEditorActiveProvider).active = true;

    await tester.tap(find.text('Limpiar').first);
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Limpiar'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.cleaned, isEmpty);
    expect(repository.ready, contains(LocalCapability.transcription));
    expect(find.text('Cierra editor para reparar el modelo'), findsOneWidget);
  });

  testWidgets('manager explicitly confirms clean and redownload', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository()
      ..ready.addAll(LocalCapability.values);
    await tester.pumpWidget(mountManagement(containerWith(repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpiar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpiar y volver a descargar'));
    await tester.pumpAndSettle();
    expect(repository.installed, [LocalCapability.transcription]);
    expect(repository.ready, containsAll(LocalCapability.values));
  });

  testWidgets('manager does not redownload when cleaning fails', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository()
      ..ready.addAll(LocalCapability.values)
      ..cleanError = StateError('no se pudo limpiar');
    await tester.pumpWidget(mountManagement(containerWith(repository)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpiar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpiar y volver a descargar'));
    await tester.pumpAndSettle();

    expect(repository.installed, isEmpty);
    expect(find.text('Error'), findsOneWidget);
  });

  testWidgets('manager stays available when every model is ready', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository()
      ..ready.addAll(LocalCapability.values);
    await tester.pumpWidget(mountManagement(containerWith(repository)));
    await tester.pumpAndSettle();
    expect(find.text('Dictado y redacción'), findsOneWidget);
    expect(find.text('Dictado de hitos'), findsOneWidget);
    expect(find.text('Mejora de redacción'), findsOneWidget);
  });

  testWidgets(
    'manager refresh failure offers retry without onboarding actions',
    (tester) async {
      useTallSurface(tester);
      final repository = FakeCapabilityRepository()
        ..queryError = StateError('disco no disponible');
      await tester.pumpWidget(mountManagement(containerWith(repository)));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'No se pudo comprobar el estado de la descarga. Inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Reintentar'), findsOneWidget);
      expect(find.text('Ahora no'), findsNothing);
      expect(find.text('Continuar'), findsNothing);
    },
  );

  testWidgets('skip returns to setup without recording a choice', (
    tester,
  ) async {
    useTallSurface(tester);
    final container = containerWith(FakeCapabilityRepository());
    await tester.pumpWidget(mountManagement(container));
    await tester.pumpAndSettle();

    expect(find.text('Dictado de hitos'), findsOneWidget);
    expect(find.text('Volver'), findsNothing);
    expect(container.read(modelSetupSkippedProvider), isFalse);
    expect(container.read(setupAwaitingContinueProvider), isFalse);
  });

  testWidgets('manager header back pops to the pushed screen', (tester) async {
    useTallSurface(tester);
    final container = containerWith(FakeCapabilityRepository());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: GoRouter(
            initialLocation: '/home',
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => Scaffold(
                  body: TextButton(
                    onPressed: () => context.push('/models'),
                    child: const Text('Abrir modelos'),
                  ),
                ),
              ),
              GoRoute(
                path: '/models',
                builder: (context, state) => const ModelManagementScreen(),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir modelos'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Volver a Ajustes'), findsOneWidget);
    await tester.tap(find.byTooltip('Volver a Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Abrir modelos'), findsOneWidget);
  });

  testWidgets('onboarding keeps skip and continue actions without app bar', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository();
    await tester.pumpWidget(mount(containerWith(repository)));
    await tester.pumpAndSettle();
    expect(find.text('Ahora no'), findsOneWidget);
    expect(find.text('Continuar'), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Comprobar descarga'), findsNothing);
    expect(find.text('Limpiar'), findsNothing);
  });

  testWidgets('onboarding downloads models only from the global action', (
    tester,
  ) async {
    useTallSurface(tester);
    final repository = FakeCapabilityRepository();
    await tester.pumpWidget(mount(containerWith(repository)));
    await tester.pumpAndSettle();

    expect(find.text('Descargar'), findsNothing);
    expect(find.text('Descargar 0 MB'), findsOneWidget);
    await tester.tap(find.text('Descargar 0 MB'));
    await tester.pumpAndSettle();

    expect(repository.installed, LocalCapability.values);
    expect(repository.ready, LocalCapability.values.toSet());
  });
}

/// Stands in for the real installer so the screen can be driven without network.
class FakeCapabilityRepository implements LocalCapabilityRepository {
  FakeCapabilityRepository({this.onInstall});

  final Stream<LocalModelProgress> Function(LocalCapability capability)?
  onInstall;
  final List<LocalCapability> installed = [];
  final List<LocalCapability> cleaned = [];
  final Set<LocalCapability> ready = {};
  Object? queryError;
  Object? cleanError;

  @override
  Future<List<LocalCapabilitySnapshot>> query() async {
    if (queryError case final error?) throw error;
    return [
      for (final capability in LocalCapability.values)
        LocalCapabilitySnapshot(
          capability: capability,
          status: ready.contains(capability)
              ? LocalCapabilityStatus.ready
              : LocalCapabilityStatus.missing,
        ),
    ];
  }

  @override
  Stream<LocalModelProgress> install(LocalCapability capability) {
    installed.add(capability);
    return _install(capability);
  }

  Stream<LocalModelProgress> _install(LocalCapability capability) async* {
    final updates =
        onInstall?.call(capability) ??
        Stream.value(
          LocalModelProgress(
            capability: capability,
            status: LocalCapabilityStatus.ready,
            stage: LocalModelProgressStage.installing,
            fraction: 1,
          ),
        );
    yield* updates;
    ready.add(capability);
  }

  @override
  Future<bool> verify(LocalCapability capability) async =>
      ready.contains(capability);

  @override
  Future<void> clean(LocalCapability capability) async {
    cleaned.add(capability);
    if (cleanError case final error?) throw error;
    ready.remove(capability);
  }
}
