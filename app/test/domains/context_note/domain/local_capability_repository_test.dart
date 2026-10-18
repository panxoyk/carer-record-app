import 'package:carer_record_app/domains/context_note/domain/local_capability_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('capabilities remain independent of configured model identity', () {
    const first = LocalCapabilitySnapshot(
      capability: LocalCapability.transcription,
      status: LocalCapabilityStatus.missing,
      model: LocalModelIdentity(
        id: 'whisper-es',
        version: '1',
        runtime: 'sherpa_onnx',
      ),
    );
    const second = LocalCapabilitySnapshot(
      capability: LocalCapability.transcription,
      status: LocalCapabilityStatus.missing,
      model: LocalModelIdentity(
        id: 'other-es',
        version: '2',
        runtime: 'other-runtime',
      ),
    );

    expect(first.capability, second.capability);
    expect(first.model!.id, isNot(second.model!.id));
    expect(first.status, LocalCapabilityStatus.missing);
  });

  test(
    'progress communicates common lifecycle state and optional fraction',
    () {
      const event = LocalModelProgress(
        capability: LocalCapability.textAssistance,
        status: LocalCapabilityStatus.installing,
        stage: LocalModelProgressStage.downloading,
        receivedBytes: 5,
        totalBytes: 10,
        fraction: .5,
      );

      expect(event.status, LocalCapabilityStatus.installing);
      expect(event.fraction, .5);
      expect(
        const LocalModelProgress(
          capability: LocalCapability.transcription,
          status: LocalCapabilityStatus.checking,
          stage: LocalModelProgressStage.preparing,
        ).fraction,
        isNull,
      );
    },
  );
}
