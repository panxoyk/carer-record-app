import 'local_capability_repository.dart';

/// Tracks active consumers of local capabilities without provider notifications.
class LocalCapabilityUsage {
  final Map<LocalCapability, int> _counts = {
    for (final capability in LocalCapability.values) capability: 0,
  };

  bool isInUse(LocalCapability capability) => _counts[capability]! > 0;

  LocalCapabilityUsageLease acquire(Iterable<LocalCapability> capabilities) {
    final held = Set<LocalCapability>.of(capabilities);
    for (final capability in held) {
      _counts[capability] = _counts[capability]! + 1;
    }
    return LocalCapabilityUsageLease._(this, held);
  }

  void _release(Set<LocalCapability> held) {
    for (final capability in held) {
      _counts[capability] = _counts[capability]! - 1;
    }
  }
}

class LocalCapabilityUsageLease {
  LocalCapabilityUsageLease._(this._usage, this._capabilities);

  final LocalCapabilityUsage _usage;
  final Set<LocalCapability> _capabilities;
  bool _released = false;

  void release() {
    if (_released) return;
    _released = true;
    _usage._release(_capabilities);
  }
}
