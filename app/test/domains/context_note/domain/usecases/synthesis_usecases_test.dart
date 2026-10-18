import 'package:carer_record_app/domains/on_device_ai/data/fake_synthesis_provider.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';
import 'package:carer_record_app/domains/context_note/domain/usecases/synthesis_usecases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImproveNoteDraft', () {
    test('returns an editable suggestion when the local model works', () async {
      final provider = FakeSynthesisProvider();
      final outcome = await ImproveNoteDraft(provider: provider)(
        text: 'paciente tolere bien. sin cambios',
      );
      expect(outcome.hasSuggestion, isTrue);
      expect(outcome.suggestion, 'Paciente tolere bien. Sin cambios.');
      expect(outcome.errorCode, isNull);
      expect(provider.calls.single.purpose, SynthesisPurpose.improveNoteText);
    });

    test('publishes the author text when no model is installed', () async {
      final provider = FakeSynthesisProvider(available: false);
      final outcome = await ImproveNoteDraft(provider: provider)(
        text: 'texto original de la autora',
      );
      expect(outcome.hasSuggestion, isFalse);
      expect(outcome.fallback, 'texto original de la autora');
      expect(outcome.errorCode, SynthesisErrorCode.unavailable);
      expect(provider.calls, isEmpty);
    });

    test('never blocks the note when the model fails', () async {
      for (final code in [
        SynthesisErrorCode.timeout,
        SynthesisErrorCode.malformed,
        SynthesisErrorCode.internal,
        SynthesisErrorCode.cancelled,
      ]) {
        final provider = FakeSynthesisProvider(failWith: code);
        final outcome = await ImproveNoteDraft(provider: provider)(
          text: 'texto original de la autora',
        );
        expect(outcome.hasSuggestion, isFalse, reason: code);
        expect(outcome.fallback, 'texto original de la autora', reason: code);
        expect(outcome.errorCode, code, reason: code);
      }
    });

    test(
      'never blocks the note when the runtime throws something unknown',
      () async {
        final provider = _ExplodingSynthesisProvider();
        final outcome = await ImproveNoteDraft(provider: provider)(
          text: 'texto original de la autora',
        );
        expect(outcome.hasSuggestion, isFalse);
        expect(outcome.fallback, 'texto original de la autora');
        expect(outcome.errorCode, SynthesisErrorCode.internal);
      },
    );

    test('does not call the model with an empty draft', () async {
      final provider = FakeSynthesisProvider();
      final outcome = await ImproveNoteDraft(provider: provider)(text: '   ');
      expect(outcome.hasSuggestion, isFalse);
      expect(outcome.errorCode, isNull);
      expect(provider.calls, isEmpty);
    });

    test('discards a suggestion beyond the configured length', () async {
      final provider = FakeSynthesisProvider();
      final outcome = await ImproveNoteDraft(
        provider: provider,
        maxOutputChars: 5,
      )(text: 'un texto bastante más largo que el límite');
      expect(outcome.hasSuggestion, isFalse);
      expect(outcome.errorCode, SynthesisErrorCode.tooLong);
      expect(outcome.fallback, 'un texto bastante más largo que el límite');
    });

    test(
      'passes the budget and the idempotency key through the port',
      () async {
        final provider = FakeSynthesisProvider();
        await ImproveNoteDraft(
          provider: provider,
          timeout: const Duration(seconds: 7),
        )(text: 'texto', idempotencyKey: 'op-1');
        final request = provider.calls.single;
        expect(request.timeout, const Duration(seconds: 7));
        expect(request.idempotencyKey, 'op-1');
        expect(request.promptVersion, 'note-improve.v1');
      },
    );

    test('honours cancellation reported through the port', () async {
      final provider = FakeSynthesisProvider();
      final outcome = await ImproveNoteDraft(provider: provider)(
        text: 'texto de la autora',
        isCancelled: () => true,
      );
      expect(outcome.hasSuggestion, isFalse);
      expect(outcome.errorCode, SynthesisErrorCode.cancelled);
      expect(outcome.fallback, 'texto de la autora');
    });
  });

  group('FlagNoteEntities', () {
    test('returns entity hints without altering the text', () async {
      final provider = FakeSynthesisProvider();
      final outcome = await FlagNoteEntities(provider: provider)(
        text: 'Se contacta a Ana Pérez por el 12.345.678-k.',
      );
      expect(outcome.errorCode, isNull);
      expect(outcome.entities, isNotEmpty);
      expect(outcome.fallback, contains('Ana Pérez'));
      expect(provider.calls.single.purpose, SynthesisPurpose.flagEntities);
    });

    test('leaves the text untouched: there is no token map any more', () async {
      final provider = FakeSynthesisProvider();
      const original = 'Se contacta a Ana Pérez.';
      final outcome = await FlagNoteEntities(provider: provider)(
        text: original,
      );
      expect(outcome.fallback, original);
      expect(outcome.hasSuggestion, isFalse);
    });

    test('reports unavailability instead of throwing', () async {
      final provider = FakeSynthesisProvider(available: false);
      final outcome = await FlagNoteEntities(provider: provider)(
        text: 'texto de la autora',
      );
      expect(outcome.entities, isEmpty);
      expect(outcome.errorCode, SynthesisErrorCode.unavailable);
    });
  });

  group('port contract', () {
    test('the fake honours the request length limit', () async {
      final provider = FakeSynthesisProvider();
      expect(
        () => provider.synthesize(
          SynthesisRequest(
            purpose: SynthesisPurpose.improveNoteText,
            text: 'x' * 50,
            promptVersion: 'v1',
            timeout: const Duration(seconds: 1),
            maxOutputChars: 10,
          ),
        ),
        throwsA(
          isA<SynthesisException>().having(
            (e) => e.code,
            'code',
            SynthesisErrorCode.tooLong,
          ),
        ),
      );
    });

    test('the fake is deterministic', () async {
      const text = 'texto estable para comparar';
      final first = await ImproveNoteDraft(provider: FakeSynthesisProvider())(
        text: text,
      );
      final second = await ImproveNoteDraft(provider: FakeSynthesisProvider())(
        text: text,
      );
      expect(first.suggestion, second.suggestion);
    });

    test(
      'the fake can drop structured output like a model without JSON',
      () async {
        final provider = FakeSynthesisProvider(structured: false);
        final outcome = await FlagNoteEntities(provider: provider)(
          text: 'Se contacta a Ana Pérez.',
        );
        expect(outcome.entities, isEmpty);
        expect(outcome.errorCode, isNull);
      },
    );
  });
}

class _ExplodingSynthesisProvider implements SynthesisProvider {
  @override
  bool get isAvailable => true;

  @override
  String get modelVersion => 'boom';

  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    throw StateError('runtime failure with no clinical detail');
  }

  @override
  Future<void> dispose() async {}
}
