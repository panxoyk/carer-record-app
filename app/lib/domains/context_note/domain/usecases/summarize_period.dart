import '../../../on_device_ai/domain/synthesis_provider.dart';

/// Asks the local model to produce a summary of a period's notes (bitacora).
///
/// Assistance never blocks clinical work: any failure resolves to an empty
/// suggestion with a stable error code, and the caller keeps the original notes.
class SummarizePeriod {
  const SummarizePeriod({
    required this.provider,
    this.promptVersion = 'period-summary.v1',
    this.timeout = const Duration(minutes: 3),
    this.maxOutputChars = 20000,
  });

  final SynthesisProvider provider;
  final String promptVersion;
  final Duration timeout;
  final int maxOutputChars;

  Future<SynthesisOutcome> call({
    required List<String> notes,
    String? idempotencyKey,
    bool Function()? isCancelled,
  }) async {
    final trimmedNotes = notes
        .map((n) => n.trim())
        .where((n) => n.isNotEmpty)
        .toList();
    if (trimmedNotes.isEmpty) {
      return const SynthesisOutcome(fallback: '');
    }
    final text = trimmedNotes.join('\n\n---\n\n');
    if (!provider.isAvailable) {
      return SynthesisOutcome(
        fallback: text,
        errorCode: SynthesisErrorCode.unavailable,
      );
    }
    try {
      final result = await provider.synthesize(
        SynthesisRequest(
          purpose: SynthesisPurpose.periodSummary,
          text: text,
          promptVersion: promptVersion,
          timeout: timeout,
          maxOutputChars: maxOutputChars,
          idempotencyKey: idempotencyKey,
        ),
        isCancelled: isCancelled,
      );
      final suggestion = result.text.trim();
      if (suggestion.isEmpty) {
        return SynthesisOutcome(
          fallback: text,
          errorCode: SynthesisErrorCode.malformed,
          modelVersion: result.modelVersion,
          elapsed: result.elapsed,
        );
      }
      if (suggestion.length > maxOutputChars) {
        return SynthesisOutcome(
          fallback: text,
          errorCode: SynthesisErrorCode.tooLong,
          modelVersion: result.modelVersion,
          elapsed: result.elapsed,
        );
      }
      return SynthesisOutcome(
        fallback: text,
        suggestion: suggestion,
        entities: result.entities,
        modelVersion: result.modelVersion,
        elapsed: result.elapsed,
      );
    } on SynthesisException catch (error) {
      return SynthesisOutcome(
        fallback: text,
        errorCode: error.code,
        modelVersion: provider.modelVersion,
      );
    } catch (_) {
      return SynthesisOutcome(
        fallback: text,
        errorCode: SynthesisErrorCode.internal,
      );
    }
  }
}
