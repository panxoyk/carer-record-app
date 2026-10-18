/// Stable, UI-independent contract for the optional on-device capabilities.
///
/// A capability describes what the app can do; [LocalModelIdentity] describes
/// the configured implementation. Keeping these separate lets model choices
/// change without changing ASR or text-assistance callers.
enum LocalCapability { transcription, textAssistance }

enum LocalCapabilityStatus {
  checking,
  unavailable,
  missing,
  installing,
  ready,
  failed,
}

/// Provenance/configuration identity of the model backing a capability.
class LocalModelIdentity {
  const LocalModelIdentity({
    required this.id,
    required this.version,
    required this.runtime,
    this.checksum = '',
  });

  final String id;
  final String version;
  final String runtime;
  final String checksum;
}

/// A snapshot has stable capability identity and separately optional model
/// configuration. A missing model does not imply the capability is unsupported.
class LocalCapabilitySnapshot {
  const LocalCapabilitySnapshot({
    required this.capability,
    required this.status,
    this.model,
    this.errorCode,
  });

  final LocalCapability capability;
  final LocalCapabilityStatus status;
  final LocalModelIdentity? model;
  final String? errorCode;
}

enum LocalModelProgressStage {
  preparing,
  downloading,
  verifying,
  extracting,
  installing,
  cleaning,
}

/// Shared progress event. Fraction is null when total work is unknown.
class LocalModelProgress {
  const LocalModelProgress({
    required this.capability,
    required this.status,
    required this.stage,
    this.fraction,
    this.receivedBytes,
    this.totalBytes,
  });

  final LocalCapability capability;
  final LocalCapabilityStatus status;
  final LocalModelProgressStage stage;
  final double? fraction;
  final int? receivedBytes;
  final int? totalBytes;
}

/// Device-local model lifecycle. Implementations may fetch model weights, but
/// must never send clinical content; inference remains behind AsrEngine and
/// SynthesisProvider respectively.
abstract interface class LocalCapabilityRepository {
  Future<List<LocalCapabilitySnapshot>> query();

  Stream<LocalModelProgress> install(LocalCapability capability);

  Future<bool> verify(LocalCapability capability);

  Future<void> clean(LocalCapability capability);
}
