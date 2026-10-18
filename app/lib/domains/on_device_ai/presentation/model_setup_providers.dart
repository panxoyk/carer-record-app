import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models/model_task.dart';
import '../data/asr_model_manifest.dart';
import '../data/llm_model_manifest.dart';
import '../domain/local_capability_repository.dart';
import '../presentation/local_ai_providers.dart';

final modelSetupClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// A skip is valid only for this process. It is deliberately not persisted.
final modelSetupSkippedProvider = StateProvider<bool>((ref) => false);

/// True only while first-run setup is waiting for the user to continue after
/// starting an installation in this process.
final setupAwaitingContinueProvider = StateProvider<bool>((ref) => false);
final modelSetupRefreshErrorProvider = StateProvider<bool>((ref) => false);
final modelCleanBlockedProvider = StateProvider<bool>((ref) => false);

/// One device-local readiness snapshot per ProviderContainer/process. It only
/// reads installed capability metadata; it never provisions model files.
final modelReadinessProvider = FutureProvider<bool>((ref) async {
  final repository = await ref.watch(localCapabilityRepositoryProvider);
  final snapshots = await repository.query();
  return LocalCapability.values.every(
    (capability) => snapshots.any(
      (snapshot) =>
          snapshot.capability == capability &&
          snapshot.status == LocalCapabilityStatus.ready,
    ),
  );
});

/// Drives the first-run download of the on-device weights.
///
/// A fresh clone ships manifests, not blobs, so this is what turns `flutter run`
/// on a clean device into a working app. Nothing here blocks sign-in: a failed
/// or skipped download only leaves the dictated milestone and the text
/// assistance unavailable, exactly as ADR-016 and ADR-017 require.
class ModelSetupController extends Notifier<List<ModelTask>> {
  @override
  List<ModelTask> build() => const [];

  bool _operationInProgress = false;
  bool get isBusy =>
      _operationInProgress ||
      state.any(
        (task) =>
            task.status == ModelStatus.installing ||
            task.status == ModelStatus.checking,
      );
  final Map<LocalModel, _DownloadEstimate> _estimates = {};

  bool get allReady =>
      state.isNotEmpty &&
      state.every((task) => task.status == ModelStatus.ready);

  List<ModelTask> get pending =>
      state.where((task) => task.status != ModelStatus.ready).toList();

  int get pendingBytes => pending.fold(0, (sum, task) => sum + task.bytes);

  /// Reads both manifests and reports what is already on the device.
  Future<void> refresh() async {
    try {
      final speech = await ref.read(asrModelManifestProvider.future);
      final writing = await ref.read(llmModelManifestProvider.future);
      final repo = await ref.read(localCapabilityRepositoryProvider);
      final snapshots = await repo.query();
      state = _tasks(snapshots, speech, writing);
    } catch (_) {
      // A failed query/manifest load is not evidence that models are absent.
      ref.read(modelSetupRefreshErrorProvider.notifier).state = true;
      return;
    }
    if (state.isNotEmpty) {
      ref.read(modelSetupRefreshErrorProvider.notifier).state = false;
    }
  }

  /// Installs every model that is not on the device yet, one after the other.
  ///
  /// Sequential on purpose: two concurrent downloads buy little on a phone and
  /// make the progress line unreadable.
  Future<void> installAll() async {
    if (ref.read(modelSetupRefreshErrorProvider) ||
        _operationInProgress ||
        state.isEmpty ||
        isBusy) {
      return;
    }
    _operationInProgress = true;
    try {
      final repo = await ref.read(localCapabilityRepositoryProvider);
      for (final task in pending) {
        _patch(
          task.model,
          (t) => t.copyWith(
            status: ModelStatus.installing,
            fraction: 0,
            stage: 'descargando',
            clearError: true,
            clearProgress: true,
          ),
        );
        _estimates.remove(task.model);
        try {
          await for (final progress in repo.install(_capability(task.model))) {
            final eta = _estimate(task.model, progress);
            _patch(
              task.model,
              (t) => t.copyWith(
                status: _status(progress.status),
                fraction: progress.fraction,
                stage: _stage(progress.stage),
                receivedBytes:
                    progress.stage == LocalModelProgressStage.downloading
                    ? progress.receivedBytes
                    : null,
                totalBytes:
                    progress.stage == LocalModelProgressStage.downloading
                    ? progress.totalBytes
                    : null,
                eta: eta,
                clearProgress:
                    progress.stage != LocalModelProgressStage.downloading,
              ),
            );
          }
        } catch (error) {
          // Kept as a retryable task instead of rethrown: the clinician can still
          // write milestones by hand, so the screen stays usable either way.
          _patch(
            task.model,
            (t) => t.copyWith(
              status: ModelStatus.failed,
              error: 'No se pudo descargar el modelo. Comprueba tu conexión e inténtalo de nuevo.',
            ),
          );
        }
      }
      _invalidateEngines();
      ref.invalidate(modelReadinessProvider);
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> install(LocalModel model) async {
    if (ref.read(modelSetupRefreshErrorProvider) ||
        _operationInProgress ||
        isBusy) {
      return;
    }
    final task = state.where((task) => task.model == model).firstOrNull;
    if (task == null) return;
    _operationInProgress = true;
    _patch(
      model,
      (t) => t.copyWith(
        status: ModelStatus.installing,
        fraction: 0,
        stage: 'descargando',
        clearError: true,
        clearProgress: true,
      ),
    );
    _estimates.remove(model);
    try {
      final repo = await ref.read(localCapabilityRepositoryProvider);
      await for (final progress in repo.install(_capability(model))) {
        final eta = _estimate(model, progress);
        _patch(
          model,
          (t) => t.copyWith(
            status: _status(progress.status),
            fraction: progress.fraction,
            stage: _stage(progress.stage),
            receivedBytes: progress.stage == LocalModelProgressStage.downloading
                ? progress.receivedBytes
                : null,
            totalBytes: progress.stage == LocalModelProgressStage.downloading
                ? progress.totalBytes
                : null,
            eta: eta,
            clearProgress:
                progress.stage != LocalModelProgressStage.downloading,
          ),
        );
      }
      _invalidateEngines();
      ref.invalidate(modelReadinessProvider);
    } catch (error) {
      _patch(
        model,
        (t) => t.copyWith(
          status: ModelStatus.failed,
          error: 'No se pudo descargar el modelo. Comprueba tu conexión e inténtalo de nuevo.',
        ),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> verify(LocalModel model) async {
    if (ref.read(modelSetupRefreshErrorProvider) ||
        _operationInProgress ||
        isBusy) {
      return;
    }
    _operationInProgress = true;
    _patch(model, (t) => t.copyWith(status: ModelStatus.checking));
    try {
      final ready = await (await ref.read(localCapabilityRepositoryProvider))
          .verify(_capability(model));
      ref.invalidate(modelReadinessProvider);
      _patch(
        model,
        (t) =>
            t.copyWith(status: ready ? ModelStatus.ready : ModelStatus.missing),
      );
    } catch (error) {
      _patch(
        model,
        (t) => t.copyWith(
          status: ModelStatus.failed,
          error: 'No se pudo comprobar la descarga. Inténtalo de nuevo.',
        ),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  Future<void> clean(LocalModel model) async {
    if (ref.read(localCapabilityUsageProvider).isInUse(_capability(model))) {
      ref.read(modelCleanBlockedProvider.notifier).state = true;
      return;
    }
    if (ref.read(modelSetupRefreshErrorProvider) ||
        _operationInProgress ||
        isBusy) {
      return;
    }
    _operationInProgress = true;
    _patch(
      model,
      (t) => t.copyWith(status: ModelStatus.installing, stage: 'limpiando'),
    );
    try {
      _invalidateEngines();
      await (await ref.read(localCapabilityRepositoryProvider))
          .clean(_capability(model));
      ref.invalidate(modelReadinessProvider);
      _patch(
        model,
        (t) => t.copyWith(
          status: ModelStatus.missing,
          fraction: null,
          stage: null,
        ),
      );
    } catch (error) {
      _patch(
        model,
        (t) => t.copyWith(
          status: ModelStatus.failed,
          error: 'No se pudo limpiar el modelo. Inténtalo de nuevo.',
        ),
      );
    } finally {
      _operationInProgress = false;
    }
  }

  List<ModelTask> _tasks(
    List<LocalCapabilitySnapshot> snapshots,
    AsrModelManifest speech,
    LlmModelManifest writing,
  ) {
    final result = <ModelTask>[];
    for (final model in LocalModel.values) {
      final capability = _capability(model);
      final snapshot = snapshots
          .where((s) => s.capability == capability)
          .firstOrNull;
      result.add(
        ModelTask(
          model: model,
          title: model == LocalModel.speech
              ? 'Dictado de hitos'
              : 'Mejora de redacción',
          purpose: model == LocalModel.speech
              ? 'Transcribe la voz en el dispositivo. El audio nunca sale del teléfono.'
              : 'Sugiere una redacción más clara del hito. Es opcional y nunca bloquea la escritura clínica.',
          version: model == LocalModel.speech ? speech.version : writing.file,
          license: model == LocalModel.speech
              ? speech.license
              : writing.license,
          bytes: model == LocalModel.speech
              ? speech.archiveBytes
              : writing.bytes,
          status: snapshot == null
              ? ModelStatus.missing
              : _status(snapshot.status),
        ),
      );
    }
    return result;
  }

  LocalCapability _capability(LocalModel model) => model == LocalModel.speech
      ? LocalCapability.transcription
      : LocalCapability.textAssistance;
  ModelStatus _status(LocalCapabilityStatus status) => switch (status) {
    LocalCapabilityStatus.ready => ModelStatus.ready,
    LocalCapabilityStatus.installing ||
    LocalCapabilityStatus.checking => ModelStatus.installing,
    LocalCapabilityStatus.failed => ModelStatus.failed,
    _ => ModelStatus.missing,
  };
  String _stage(LocalModelProgressStage stage) => switch (stage) {
    LocalModelProgressStage.downloading => 'descargando',
    LocalModelProgressStage.verifying => 'verificando',
    LocalModelProgressStage.extracting => 'descomprimiendo',
    LocalModelProgressStage.cleaning => 'limpiando',
    _ => 'preparando',
  };

  void _patch(LocalModel model, ModelTask Function(ModelTask) change) {
    state = [
      for (final task in state)
        if (task.model == model) change(task) else task,
    ];
  }

  Duration? _estimate(LocalModel model, LocalModelProgress progress) {
    if (progress.stage != LocalModelProgressStage.downloading ||
        progress.receivedBytes == null ||
        progress.totalBytes == null) {
      _estimates.remove(model);
      return null;
    }
    final now = ref.read(modelSetupClockProvider)();
    final previous = _estimates[model];
    if (previous != null) {
      final seconds = now.difference(previous.at).inMicroseconds / 1000000;
      final bytes = progress.receivedBytes! - previous.bytes;
      if (seconds > 0 && bytes > 0) {
        final rate = bytes / seconds;
        previous.rate = previous.rate == null
            ? rate
            : previous.rate! * .5 + rate * .5;
        previous.samples++;
      }
    }
    _estimates[model] = _DownloadEstimate(
      at: now,
      bytes: progress.receivedBytes!,
      rate: previous?.rate,
      samples: previous?.samples ?? 1,
    );
    if (previous == null || previous.samples < 2 || previous.rate == null) {
      return null;
    }
    final remaining = progress.totalBytes! - progress.receivedBytes!;
    if (remaining < 0) return null;
    return Duration(seconds: (remaining / previous.rate!).ceil());
  }

  /// Drops the cached engines so the next reader picks up the new weights.
  void _invalidateEngines() {
    ref.invalidate(asrEngineProvider);
    ref.invalidate(synthesisProviderProvider);
  }
}

class _DownloadEstimate {
  _DownloadEstimate({
    required this.at,
    required this.bytes,
    this.rate,
    this.samples = 1,
  });
  final DateTime at;
  final int bytes;
  double? rate;
  int samples;
}

final modelSetupControllerProvider =
    NotifierProvider<ModelSetupController, List<ModelTask>>(
      ModelSetupController.new,
    );
