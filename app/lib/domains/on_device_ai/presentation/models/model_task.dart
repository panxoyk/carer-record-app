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
