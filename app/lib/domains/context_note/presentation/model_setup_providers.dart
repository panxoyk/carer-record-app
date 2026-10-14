import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/model_provisioning.dart';
import 'context_note_providers.dart';

/// Keeps the provisioner injectable so the controller can be tested without
/// reaching for the network.
final modelProvisionerProvider = Provider<ModelProvisioner>(
  (ref) => const ModelProvisioner(),
);

/// Drives the first-run download of the on-device weights.
///
/// A fresh clone ships manifests, not blobs, so this is what turns `flutter run`
/// on a clean device into a working app. Nothing here blocks sign-in: a failed
/// or skipped download only leaves the dictated milestone and the text
/// assistance unavailable, exactly as ADR-016 and ADR-017 require.
class ModelSetupController extends Notifier<List<ModelTask>> {
  @override
  List<ModelTask> build() => const [];

  bool get isBusy => state.any((task) => task.status == ModelStatus.installing);

  bool get allReady =>
      state.isNotEmpty &&
      state.every((task) => task.status == ModelStatus.ready);

  List<ModelTask> get pending =>
      state.where((task) => task.status != ModelStatus.ready).toList();

  int get pendingBytes => pending.fold(0, (sum, task) => sum + task.bytes);

  /// Reads both manifests and reports what is already on the device.
  Future<void> refresh() async {
    final speech = await ref.read(asrModelManifestProvider.future);
    final writing = await ref.read(llmModelManifestProvider.future);
    final speechTarget = await ref.read(asrModelDirectoryProvider.future);
    final writingTarget = await ref.read(llmModelDirectoryProvider.future);
    state = ref
        .read(modelProvisionerProvider)
        .describe(
          speech: speech,
          writing: writing,
          speechTarget: speechTarget,
          writingTarget: writingTarget,
        );
  }

  /// Installs every model that is not on the device yet, one after the other.
  ///
  /// Sequential on purpose: two concurrent downloads buy little on a phone and
  /// make the progress line unreadable.
  Future<void> installAll() async {
    final provisioner = ref.read(modelProvisionerProvider);
    final speech = await ref.read(asrModelManifestProvider.future);
    final writing = await ref.read(llmModelManifestProvider.future);
    final speechTarget = await ref.read(asrModelDirectoryProvider.future);
    final writingTarget = await ref.read(llmModelDirectoryProvider.future);

    for (final task in pending) {
      _patch(
        task.model,
        (t) => t.copyWith(
          status: ModelStatus.installing,
          fraction: 0,
          stage: 'descargando',
          clearError: true,
        ),
      );
      try {
        await provisioner.install(
          task,
          speechTarget: speechTarget,
          writingTarget: writingTarget,
          speech: speech,
          writing: writing,
          onProgress: (fraction, stage) => _patch(
            task.model,
            (t) => t.copyWith(fraction: fraction, stage: stage),
          ),
        );
        _patch(
          task.model,
          (t) => t.copyWith(status: ModelStatus.ready, fraction: 1),
        );
      } catch (error) {
        // Kept as a retryable task instead of rethrown: the clinician can still
        // write milestones by hand, so the screen stays usable either way.
        _patch(
          task.model,
          (t) => t.copyWith(status: ModelStatus.failed, error: '$error'),
        );
      }
    }
    _invalidateEngines();
  }

  void _patch(LocalModel model, ModelTask Function(ModelTask) change) {
    state = [
      for (final task in state)
        if (task.model == model) change(task) else task,
    ];
  }

  /// Drops the cached engines so the next reader picks up the new weights.
  void _invalidateEngines() {
    ref.invalidate(asrEngineProvider);
    ref.invalidate(synthesisProviderProvider);
  }
}

final modelSetupControllerProvider =
    NotifierProvider<ModelSetupController, List<ModelTask>>(
      ModelSetupController.new,
    );
