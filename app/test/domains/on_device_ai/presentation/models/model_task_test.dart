import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/on_device_ai/presentation/models/model_task.dart';

void main() {
  test('formats model size and progress stage', () {
    final task = _task.copyWith(stage: 'descargando');
    expect(task.sizeLabel, '1.0 MB');
    expect(task.stageLabel, 'Descargando');
  });

  test('copyWith preserves values and can clear progress and error', () {
    final task = _task.copyWith(
      fraction: .5,
      receivedBytes: 10,
      totalBytes: 20,
      eta: const Duration(seconds: 2),
      stage: 'descargando',
      error: 'fallo',
    );
    final reset = task.copyWith(clearProgress: true, clearError: true);
    expect(reset.status, ModelStatus.missing);
    expect(reset.fraction, .5);
    expect(reset.receivedBytes, isNull);
    expect(reset.totalBytes, isNull);
    expect(reset.eta, isNull);
    expect(reset.stage, isNull);
    expect(reset.error, isNull);
  });
}

const _task = ModelTask(
  model: LocalModel.speech,
  title: 'Dictado',
  purpose: 'Transcripción local',
  version: '1',
  license: 'test',
  bytes: 1024 * 1024,
  status: ModelStatus.missing,
);
