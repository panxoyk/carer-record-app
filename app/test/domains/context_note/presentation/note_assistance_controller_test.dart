import 'dart:async';

import 'package:carer_record_app/domains/context_note/domain/usecases/synthesis_usecases.dart';
import 'package:carer_record_app/domains/context_note/presentation/controllers/note_assistance_controller.dart';
import 'package:carer_record_app/domains/on_device_ai/data/fake_synthesis_provider.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns suggestions and stable fallback errors', () async {
    final working = FakeSynthesisProvider();
    final controller = NoteAssistanceController(
      load: () async => ImproveNoteDraft(provider: working),
    );
    final suggestion = await controller.improve('texto inicial');
    expect(suggestion?.hasSuggestion, isTrue);

    final unavailable = FakeSynthesisProvider(available: false);
    final fallbackController = NoteAssistanceController(
      load: () async => ImproveNoteDraft(provider: unavailable),
    );
    final fallback = await fallbackController.improve('texto inicial');
    expect(fallback?.fallback, 'texto inicial');
    expect(fallback?.errorCode, SynthesisErrorCode.unavailable);
    controller.dispose();
    fallbackController.dispose();
  });

  test('invalidating changed input drops the late result', () async {
    final provider = _PendingProvider();
    final controller = NoteAssistanceController(
      load: () async => ImproveNoteDraft(provider: provider),
    );
    final pending = controller.improve('original');
    await Future<void>.delayed(Duration.zero);
    controller.invalidate();
    provider.complete('late suggestion');
    expect(await pending, isNull);
    expect(controller.outcome, isNull);
    expect(controller.busy, isFalse);
    controller.dispose();
  });

  test('disposed controller ignores a pending result', () async {
    final provider = _PendingProvider();
    final controller = NoteAssistanceController(
      load: () async => ImproveNoteDraft(provider: provider),
    );
    final pending = controller.improve('original');
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    provider.complete('late suggestion');
    expect(await pending, isNull);
    expect(controller.outcome, isNull);
  });
}

class _PendingProvider implements SynthesisProvider {
  final Completer<SynthesisResult> _result = Completer<SynthesisResult>();

  void complete(String text) => _result.complete(
    SynthesisResult(
      text: text,
      modelVersion: 'fake',
      promptVersion: 'note-improve.v1',
    ),
  );

  @override
  bool get isAvailable => true;

  @override
  String get modelVersion => 'fake';

  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) => _result.future;

  @override
  Future<void> dispose() async {}
}
