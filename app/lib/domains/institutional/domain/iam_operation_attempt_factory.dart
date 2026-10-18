import 'dart:math';

import 'iam_entities.dart';

typedef UuidByteSource = int Function();
typedef UtcClock = DateTime Function();

class IamOperationAttemptFactory {
  IamOperationAttemptFactory({UuidByteSource? nextByte, UtcClock? now})
    : _byteSource = nextByte,
      _random = nextByte == null ? Random.secure() : null,
      _now = now ?? DateTime.now;

  final UuidByteSource? _byteSource;
  final Random? _random;
  final UtcClock _now;

  int _nextRandomByte() => _byteSource?.call() ?? _random!.nextInt(256);

  AdminOperationAttempt create({bool usesValidFrom = false}) {
    return AdminOperationAttempt(
      idempotencyKey: _newUuidV4(),
      validFrom: usesValidFrom ? _now().toUtc() : null,
    );
  }

  String _newUuidV4() {
    final bytes = List<int>.generate(16, (_) => _nextRandomByte());
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
