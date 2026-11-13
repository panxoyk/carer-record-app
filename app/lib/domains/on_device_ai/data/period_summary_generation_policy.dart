/// Pure acceptance policy for local period-summary generation.
class PeriodSummaryGenerationPolicy {
  const PeriodSummaryGenerationPolicy._();

  /// Explicit allowance for framing/estimation variation beyond the rendered
  /// prompt token count and the requested generation limit.
  static const int contextMarginTokens = 32;

  static bool hasContextBudget({
    required int? promptTokens,
    required int generationTokens,
    required int manifestContextSize,
    required int engineContextSize,
  }) {
    if (promptTokens == null || promptTokens < 0) return false;
    final usableContext = manifestContextSize < engineContextSize
        ? manifestContextSize
        : engineContextSize;
    return promptTokens + generationTokens + contextMarginTokens <=
        usableContext;
  }

  static bool acceptsCompletion({
    required bool requestFitContext,
    required bool stoppedNormally,
    required bool hasText,
    required bool hasToolCalls,
  }) => requestFitContext && stoppedNormally && hasText && !hasToolCalls;
}
