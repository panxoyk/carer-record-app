import 'dart:io';

import 'asr_model_installer.dart';
import 'asr_model_manifest.dart';
import 'llm_model_installer.dart';
import 'llm_model_manifest.dart';

/// Which of the two on-device models a task refers to.
enum LocalModel { speech, writing }

/// Where a model task stands right now.
enum ModelStatus { checking, ready, missing, installing, failed }

/// One weight set the app provisions on first run.
///
/// The weights themselves are never in the repository: the app ships a manifest
/// that pins origin, licence, version and digests, and pulls the bytes onto the
/// device. This is what makes a fresh clone runnable without anyone wiring a
/// 1.3 GB blob into the build.
class ModelTask {
  const ModelTask({
    required this.model,
    required this.title,
    required this.purpose,
    required this.version,
    required this.license,
    required this.bytes,
    required this.status,
    this.fraction,
    this.receivedBytes,
    this.totalBytes,
    this.eta,
    this.stage,
    this.error,
  });

  final LocalModel model;
  final String title;

  /// Plain-language reason the device needs this weight, shown to the clinician.
  final String purpose;
  final String version;
  final String license;
  final int bytes;
  final ModelStatus status;

  /// 0..1 while installing, null when the total size is not yet known.
  final double? fraction;
  final int? receivedBytes;
  final int? totalBytes;
  final Duration? eta;

  /// Coarse phase name reported by the installer, for the progress line.
  final String? stage;
  final String? error;

  ModelTask copyWith({
    ModelStatus? status,
    double? fraction,
    int? receivedBytes,
    int? totalBytes,
    Duration? eta,
    bool clearProgress = false,
    String? stage,
    String? error,
    bool clearError = false,
  }) => ModelTask(
    model: model,
    title: title,
    purpose: purpose,
    version: version,
    license: license,
    bytes: bytes,
    status: status ?? this.status,
    fraction: fraction ?? this.fraction,
    receivedBytes: clearProgress ? null : (receivedBytes ?? this.receivedBytes),
    totalBytes: clearProgress ? null : (totalBytes ?? this.totalBytes),
    eta: clearProgress ? null : (eta ?? this.eta),
    stage: stage ?? (clearProgress ? null : this.stage),
    error: clearError ? null : (error ?? this.error),
  );

  /// Human-readable download size, e.g. `207,6 MB`.
  String get sizeLabel {
    final mb = bytes / (1024 * 1024);
    if (mb >= 1000) return '${(mb / 1000).toStringAsFixed(2)} GB';
    return '${mb.toStringAsFixed(1)} MB';
  }

  String get stageLabel => switch (stage) {
    'descargando' => 'Descargando',
    'verificando' => 'Comprobando descarga',
    'descomprimiendo' => 'Descomprimiendo',
    'extrayendo' => 'Preparando modelos de IA',
    _ => 'Preparando',
  };
}

/// Provisions the on-device weights declared by the shipped manifests.
///
/// This is the only network work in the app: it moves model bytes, never
/// clinical content. Once a model is installed its engine runs fully offline
/// (ADR-016, ADR-017).
class ModelProvisioner {
  const ModelProvisioner();

  /// Total bytes a first run has to pull.
  int totalBytes(List<ModelTask> tasks) =>
      tasks.fold(0, (sum, task) => sum + task.bytes);

  /// Describes both models from their manifests, probing what is on disk.
  List<ModelTask> describe({
    required AsrModelManifest speech,
    required LlmModelManifest writing,
    required Directory speechTarget,
    required Directory writingTarget,
  }) => [
    ModelTask(
      model: LocalModel.speech,
      title: 'Dictado de hitos',
      purpose:
          'Transcribe la voz en el dispositivo. El audio nunca sale del '
          'teléfono.',
      version: speech.version,
      license: speech.license,
      bytes: speech.archiveBytes,
      status: _speechPresent(speech, speechTarget)
          ? ModelStatus.ready
          : ModelStatus.missing,
    ),
    ModelTask(
      model: LocalModel.writing,
      title: 'Mejora de redacción',
      purpose:
          'Sugiere una redacción más clara del hito. Es opcional y nunca '
          'bloquea la escritura clínica.',
      version: writing.file,
      license: writing.license,
      bytes: writing.bytes,
      status: _writingPresent(writing, writingTarget)
          ? ModelStatus.ready
          : ModelStatus.missing,
    ),
  ];

  /// Cheap presence probe used to gate the first-run screen.
  ///
  /// This compares sizes rather than digests on purpose: hashing 1.3 GB on every
  /// launch would cost more than the download itself. The digest is the gate at
  /// install time, which is the moment bytes arrive from the network.
  bool _speechPresent(AsrModelManifest manifest, Directory target) =>
      manifest.files.every((file) {
        final onDisk = File(
          '${target.path}${Platform.pathSeparator}${file.name}',
        );
        return onDisk.existsSync() && onDisk.lengthSync() == file.bytes;
      });

  bool _writingPresent(LlmModelManifest manifest, Directory target) {
    final onDisk = File(
      '${target.path}${Platform.pathSeparator}${manifest.fileName}',
    );
    return onDisk.existsSync() && onDisk.lengthSync() == manifest.bytes;
  }

  /// Downloads and verifies one model, reporting progress on every step.
  Future<void> install(
    ModelTask task, {
    required Directory speechTarget,
    required Directory writingTarget,
    required AsrModelManifest speech,
    required LlmModelManifest writing,
    required void Function(double? fraction, String stage) onProgress,
  }) async {
    switch (task.model) {
      case LocalModel.speech:
        await const AsrModelInstaller().install(
          speech,
          speechTarget,
          onProgress: (p) => onProgress(p.fraction, p.stage),
        );
      case LocalModel.writing:
        await const LlmModelInstaller().install(
          writing,
          writingTarget,
          onProgress: (p) => onProgress(p.fraction, p.stage),
        );
    }
  }
}
