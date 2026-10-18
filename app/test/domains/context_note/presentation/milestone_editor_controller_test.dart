import 'dart:async';

import 'package:carer_record_app/domains/context_note/domain/entities/context_note.dart';
import 'package:carer_record_app/domains/context_note/domain/confirmed_milestone_writer.dart';
import 'package:carer_record_app/domains/context_note/presentation/controllers/milestone_editor_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('retry uses the same deeply frozen milestone snapshot', () async {
    final writer = _Writer()..failNext = true;
    final controller = _controller(writer);
    final parameters = <String, Object?>{
      'nested': <Object?>['original'],
    };
    final metadata = TranscriptionMetadata(
      engine: 'local',
      pipelineVersion: 'v1',
      parameters: parameters,
    );

    await expectLater(
      controller.publish(
        content: 'confirmed',
        inputMethod: MilestoneInputMethod.audio,
        transcription: metadata,
      ),
      throwsStateError,
    );
    parameters['nested'] = ['changed'];
    final first = writer.values.single;
    expect(
      (first.transcription!.parameters['nested']! as List).single,
      'original',
    );
    expect(
      await controller.publish(
        content: 'edited after failure',
        inputMethod: MilestoneInputMethod.text,
      ),
      isTrue,
    );
    expect(writer.values[1].clientEventId, first.clientEventId);
    expect(writer.values[1].content, first.content);
    expect(
      writer.values[1].transcription!.toJson(),
      first.transcription!.toJson(),
    );
    expect(
      await controller.publish(
        content: 'again',
        inputMethod: MilestoneInputMethod.text,
      ),
      isFalse,
    );
    controller.dispose();
  });

  test('reports successful publication once', () async {
    final writer = _Writer();
    final controller = _controller(writer);
    expect(
      await controller.publish(
        content: 'note',
        inputMethod: MilestoneInputMethod.text,
      ),
      isTrue,
    );
    expect(
      await controller.publish(
        content: 'note',
        inputMethod: MilestoneInputMethod.text,
      ),
      isFalse,
    );
    expect(writer.values, hasLength(1));
    controller.dispose();
  });

  test('invalid length does not freeze the draft', () async {
    final writer = _Writer();
    final controller = _controller(writer);
    expect(
      await controller.publish(
        content: 'x' * (maxMilestoneTextLength + 1),
        inputMethod: MilestoneInputMethod.text,
      ),
      isFalse,
    );
    expect(controller.isPublicationLocked, isFalse);
    expect(
      await controller.publish(
        content: 'corrected',
        inputMethod: MilestoneInputMethod.text,
      ),
      isTrue,
    );
    controller.dispose();
  });

  test('account switch and disposal ignore a late completion', () async {
    final writer = _Writer()..gate = Completer<void>();
    String? account = 'a';
    final controller = _controller(writer, () => account);
    final pending = controller.publish(
      content: 'note',
      inputMethod: MilestoneInputMethod.text,
    );
    await Future<void>.delayed(Duration.zero);
    account = 'b';
    expect(controller.accountChanged, isTrue);
    writer.gate!.complete();
    expect(await pending, isFalse);
    expect(controller.pendingPublication, isNotNull);
    controller.dispose();

    final lateWriter = _Writer()..gate = Completer<void>();
    final disposed = _controller(lateWriter);
    final late = disposed.publish(
      content: 'note',
      inputMethod: MilestoneInputMethod.text,
    );
    await Future<void>.delayed(Duration.zero);
    disposed.dispose();
    lateWriter.gate!.complete();
    expect(await late, isFalse);
  });
}

MilestoneEditorController _controller(
  _Writer writer, [
  String? Function()? account,
]) => MilestoneEditorController(
  writer: writer,
  organizationId: 'org',
  hospitalizationId: 'episode',
  patientId: 'patient',
  readAccountId: account ?? () => 'account',
  newEventId: () => 'event-id',
);

class _Writer implements ConfirmedMilestoneWriter {
  final values = <ContextNoteMilestone>[];
  bool failNext = false;
  Completer<void>? gate;

  @override
  Future<void> saveMilestone(ContextNoteMilestone milestone) async {
    values.add(milestone);
    if (failNext) {
      failNext = false;
      throw StateError('ambiguous failure');
    }
    await gate?.future;
  }
}
