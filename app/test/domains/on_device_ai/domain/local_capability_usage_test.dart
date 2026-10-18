import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/local_capability_repository.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/local_capability_usage.dart';

void main() {
  test('tracks two consumers independently', () {
    final usage = LocalCapabilityUsage();
    final first = usage.acquire([LocalCapability.transcription]);
    final second = usage.acquire([LocalCapability.transcription]);

    first.release();
    expect(usage.isInUse(LocalCapability.transcription), isTrue);
    second.release();
    expect(usage.isInUse(LocalCapability.transcription), isFalse);
  });

  test('release is idempotent', () {
    final usage = LocalCapabilityUsage();
    final lease = usage.acquire([LocalCapability.textAssistance]);

    lease.release();
    lease.release();

    expect(usage.isInUse(LocalCapability.textAssistance), isFalse);
  });
}
