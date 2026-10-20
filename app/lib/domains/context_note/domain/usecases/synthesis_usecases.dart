import '../../../on_device_ai/domain/synthesis_provider.dart';

/// Asks the local model to polish the text the author wrote by hand.
///
/// The contract that matters here is the negative one: this use case never
/// blocks a clinical note. Any failure — model absent, timeout, malformed
/// output — resolves to the author's own text with a stable error code, and the
/// caller publishes that.
class ImproveNoteDraft {
  const ImproveNoteDraft({
    required this.provider,
    this.promptVersion = 'note-improve.v1',
    // A local 1.7B model needs tens of seconds to load and to rewrite a note
    // on a mid-range device, and considerably more on an emulator. A timeout
    // below a couple of minutes turns a working model into a permanent
    // failure, so the budget covers the slowest supported target. Assistance
    // never blocks the note: the author's own text is published on timeout.
    this.timeout = const Duration(minutes: 3),
    this.maxOutputChars = 20000,
  });

  final SynthesisProvider provider;
  final String promptVersion;
  final Duration timeout;
  final int maxOutputChars;

  Future<SynthesisOutcome> call({
    required String text,
    String? idempotencyKey,
    bool Function()? isCancelled,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const SynthesisOutcome(fallback: '');
    }
    if (!provider.isAvailable) {
      return SynthesisOutcome(
        fallback: trimmed,
        errorCode: SynthesisErrorCode.unavailable,
      );
    }
    try {
      final result = await provider.synthesize(
        SynthesisRequest(
          purpose: SynthesisPurpose.improveNoteText,
          text: trimmed,
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
          fallback: trimmed,
          errorCode: SynthesisErrorCode.malformed,
          modelVersion: result.modelVersion,
          elapsed: result.elapsed,
        );
      }
      if (suggestion.length > maxOutputChars) {
        return SynthesisOutcome(
          fallback: trimmed,
          errorCode: SynthesisErrorCode.tooLong,
          modelVersion: result.modelVersion,
          elapsed: result.elapsed,
        );
      }
      return SynthesisOutcome(
        fallback: trimmed,
        suggestion: suggestion,
        entities: result.entities,
        modelVersion: result.modelVersion,
        elapsed: result.elapsed,
      );
    } on SynthesisException catch (error) {
      return SynthesisOutcome(
        fallback: trimmed,
        errorCode: error.code,
        modelVersion: provider.modelVersion,
      );
    } catch (_) {
      // An unexpected runtime failure is reported as a stable code, never as a
      // raw error string in the UI.
      return SynthesisOutcome(
        fallback: trimmed,
        errorCode: SynthesisErrorCode.internal,
      );
    }
  }
}

/// Points out entities in the local text without touching it. No token map
/// exists any more: with nothing leaving the device there is nothing to protect
/// by substitution (ADR-017).
class FlagNoteEntities {
  const FlagNoteEntities({
    required this.provider,
    this.promptVersion = 'note-entities.v1',
    this.timeout = const Duration(minutes: 3),
    this.maxOutputChars = 20000,
  });

  final SynthesisProvider provider;
  final String promptVersion;
  final Duration timeout;
  final int maxOutputChars;

  Future<SynthesisOutcome> call({
    required String text,
    bool Function()? isCancelled,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || !provider.isAvailable) {
      return SynthesisOutcome(
        fallback: trimmed,
        errorCode: trimmed.isEmpty ? null : SynthesisErrorCode.unavailable,
      );
    }
    try {
      final result = await provider.synthesize(
        SynthesisRequest(
          purpose: SynthesisPurpose.flagEntities,
          text: trimmed,
          promptVersion: promptVersion,
          timeout: timeout,
          maxOutputChars: maxOutputChars,
        ),
        isCancelled: isCancelled,
      );
      return SynthesisOutcome(
        fallback: trimmed,
        entities: result.entities,
        modelVersion: result.modelVersion,
        elapsed: result.elapsed,
      );
    } on SynthesisException catch (error) {
      return SynthesisOutcome(fallback: trimmed, errorCode: error.code);
    } catch (_) {
      return SynthesisOutcome(
        fallback: trimmed,
        errorCode: SynthesisErrorCode.internal,
      );
    }
  }
}
