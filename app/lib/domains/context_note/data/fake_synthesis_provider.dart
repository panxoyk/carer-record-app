import 'dart:math';

import '../domain/synthesis_provider.dart';

/// Deterministic in-memory provider used by every test and by the demo when no
/// model is installed. It obeys the same contract as the GGUF adapter: same
/// limits, same stable error codes, same structured output rules.
class FakeSynthesisProvider implements SynthesisProvider {
  FakeSynthesisProvider({
    this.available = true,
    this.modelVersion = 'fake-1.0.0',
    this.failWith,
    this.structured = true,
  });

  /// Whether the use case must behave as if no model were installed.
  final bool available;

  @override
  final String modelVersion;

  /// When set, every call fails with this stable code. Exercises the
  /// never-blocking path without a real runtime.
  final String? failWith;

  /// When false, the fake returns prose only, like a model without JSON
  /// support.
  final bool structured;

  /// Requests observed by the fake, for assertions about what crossed the port.
  final List<SynthesisRequest> calls = <SynthesisRequest>[];

  @override
  bool get isAvailable => available;

  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    calls.add(request);
    if (isCancelled?.call() ?? false) {
      throw const SynthesisException(SynthesisErrorCode.cancelled);
    }
    final failure = failWith;
    if (failure != null) {
      throw SynthesisException(failure);
    }
    if (!available) {
      throw const SynthesisException(SynthesisErrorCode.unavailable);
    }
    if (request.text.length > request.maxOutputChars) {
      throw const SynthesisException(SynthesisErrorCode.tooLong);
    }
    final stopwatch = Stopwatch()..start();
    final improved = _improve(request.text, request.purpose);
    return SynthesisResult(
      text: improved,
      modelVersion: modelVersion,
      promptVersion: request.promptVersion,
      // A model without structured output cannot report entities; the use case
      // receives an empty list instead of a guess.
      entities: structured && request.purpose == SynthesisPurpose.flagEntities
          ? _entities(request.text)
          : const <DetectedEntity>[],
      structured: structured,
      elapsed: stopwatch.elapsed,
    );
  }

  @override
  Future<void> dispose() async {}

  /// Deterministic rewrite: same input, same output, no randomness. It only
  /// tidies punctuation and capitalisation; it never invents clinical facts.
  String _improve(String text, SynthesisPurpose purpose) {
    if (purpose == SynthesisPurpose.flagEntities) return '';
    final sentences = text
        .split(RegExp(r'(?<=[.!?])\s+'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (sentences.isEmpty) return text.trim();
    return sentences
        .map((sentence) {
          final withPeriod = RegExp(r'[.!?]$').hasMatch(sentence)
              ? sentence
              : '$sentence.';
          return '${withPeriod[0].toUpperCase()}${withPeriod.substring(1)}';
        })
        .join(' ');
  }

  static final RegExp _entityPattern = RegExp(
    r'\b\d{1,2}\.\d{3}\.\d{3}\b|\b[A-ZÁÉÍÓÚÑ][\wáéíóúñ]*\s[A-ZÁÉÍÓÚÑ][\wáéíóúñ]+\b',
  );

  List<DetectedEntity> _entities(String text) {
    final found = <DetectedEntity>[];
    for (final match in _entityPattern.allMatches(text)) {
      found.add(
        DetectedEntity(
          value: match.group(0) ?? '',
          type: RegExp(r'^\d').hasMatch(match.group(0) ?? '')
              ? 'identifier'
              : 'person_name',
          start: match.start,
          end: match.end,
          confidence: 0.8,
        ),
      );
    }
    return found.take(20).toList(growable: false);
  }
}

/// Helper for tests that need a provider whose availability flips.
class ScriptedSynthesisProvider implements SynthesisProvider {
  ScriptedSynthesisProvider(this.responses);

  final List<SynthesisResult> responses;
  int _index = 0;

  @override
  bool get isAvailable => true;

  @override
  String get modelVersion => 'scripted-1.0.0';

  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    final random = Random(_index);
    _index++;
    await Future<void>.delayed(Duration(milliseconds: random.nextInt(2)));
    return responses[_index - 1];
  }

  @override
  Future<void> dispose() async {}
}
