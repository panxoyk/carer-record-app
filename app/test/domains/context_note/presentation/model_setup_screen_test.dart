import 'dart:async';
import 'dart:io';

import 'package:carer_record_app/domains/context_note/data/asr_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/llm_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/model_provisioning.dart';
import 'package:carer_record_app/domains/context_note/presentation/context_note_providers.dart';
import 'package:carer_record_app/domains/context_note/presentation/model_setup_providers.dart';
import 'package:carer_record_app/domains/context_note/presentation/model_setup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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

  ProviderContainer containerWith(FakeProvisioner provisioner) {
    final container = ProviderContainer(
      overrides: [
        modelProvisionerProvider.overrideWithValue(provisioner),
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
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  testWidgets('offers both models with their licence and size', (tester) async {
    await tester.pumpWidget(mount(containerWith(FakeProvisioner())));
    await tester.pumpAndSettle();

    expect(find.text('Dictado de hitos'), findsOneWidget);
    expect(find.text('Mejora de redacción'), findsOneWidget);
    expect(find.textContaining('MIT'), findsOneWidget);
    expect(find.textContaining('Apache-2.0'), findsOneWidget);
    expect(find.textContaining('Pendiente'), findsNWidgets(2));
  });

  testWidgets('reports progress and finishes ready once installed', (
    tester,
  ) async {
    useTallSurface(tester);
    final gate = Completer<void>();
    final provisioner = FakeProvisioner(
      onInstall: (model, onProgress) async {
        onProgress(0.5, 'descargando');
        // Held open so the mid-flight frame is observable instead of racing
        // straight to the finished state.
        await gate.future;
      },
    );
    await tester.pumpWidget(mount(containerWith(provisioner)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(find.text('Descargando · 50 %'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Listo'), findsNWidgets(2));
    expect(
      provisioner.installed,
      containsAll([LocalModel.speech, LocalModel.writing]),
    );
  });

  testWidgets('a failed download leaves the screen usable and retryable', (
    tester,
  ) async {
    useTallSurface(tester);
    final provisioner = FakeProvisioner(
      onInstall: (model, onProgress) async {
        if (model == LocalModel.speech) throw const FormatException('sin red');
      },
    );
    await tester.pumpWidget(mount(containerWith(provisioner)));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    expect(find.textContaining('sin red'), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);
    // The clinical record stays reachable no matter what the download did.
    expect(find.text('Continuar sin los modelos'), findsOneWidget);
    // And the other model still installed rather than being abandoned.
    expect(provisioner.installed, contains(LocalModel.writing));
  });

  testWidgets('never blocks the record: the skip action is always offered', (
    tester,
  ) async {
    useTallSurface(tester);
    await tester.pumpWidget(mount(containerWith(FakeProvisioner())));
    await tester.pumpAndSettle();

    expect(find.text('Continuar sin los modelos'), findsOneWidget);
  });

  testWidgets('states that nothing clinical is downloaded', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(mount(containerWith(FakeProvisioner())));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Ninguna descarga contiene información clínica'),
      findsOneWidget,
    );
  });
}

/// Stands in for the real installer so the screen can be driven without network.
class FakeProvisioner implements ModelProvisioner {
  FakeProvisioner({this.onInstall});

  final Future<void> Function(
    LocalModel model,
    void Function(double?, String) onProgress,
  )?
  onInstall;
  final List<LocalModel> installed = [];

  @override
  int totalBytes(List<ModelTask> tasks) =>
      tasks.fold(0, (sum, task) => sum + task.bytes);

  @override
  List<ModelTask> describe({
    required AsrModelManifest speech,
    required LlmModelManifest writing,
    required Directory speechTarget,
    required Directory writingTarget,
  }) => [
    _ready(
      speech.version,
      speech.license,
      speech.archiveBytes,
      LocalModel.speech,
    ),
    _ready(writing.file, writing.license, writing.bytes, LocalModel.writing),
  ];

  @override
  Future<void> install(
    ModelTask task, {
    required Directory speechTarget,
    required Directory writingTarget,
    required AsrModelManifest speech,
    required LlmModelManifest writing,
    required void Function(double? fraction, String stage) onProgress,
  }) async {
    installed.add(task.model);
    if (onInstall != null) await onInstall!(task.model, onProgress);
  }

  ModelTask _ready(
    String version,
    String license,
    int bytes,
    LocalModel model,
  ) => ModelTask(
    model: model,
    title: model == LocalModel.speech
        ? 'Dictado de hitos'
        : 'Mejora de redacción',
    purpose: 'x',
    version: version,
    license: license,
    bytes: bytes,
    status: ModelStatus.missing,
  );
}
