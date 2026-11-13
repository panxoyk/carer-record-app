import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/on_device_ai/data/period_summary_generation_policy.dart';

void main() {
  group('PeriodSummaryGenerationPolicy', () {
    test('reserves requested output and margin against smaller context', () {
      expect(
        PeriodSummaryGenerationPolicy.hasContextBudget(
          promptTokens: 100,
          generationTokens: 100,
          manifestContextSize: 232,
          engineContextSize: 240,
        ),
        true,
      );
      expect(
        PeriodSummaryGenerationPolicy.hasContextBudget(
          promptTokens: 101,
          generationTokens: 100,
          manifestContextSize: 232,
          engineContextSize: 240,
        ),
        false,
      );
    });

    test('fails closed when measurement is unavailable', () {
      expect(
        PeriodSummaryGenerationPolicy.hasContextBudget(
          promptTokens: null,
          generationTokens: 1,
          manifestContextSize: 2048,
          engineContextSize: 2048,
        ),
        false,
      );
    });

    test('accepts only normally stopped, context-fitting text output', () {
      bool accepts({
        bool fits = true,
        bool stopped = true,
        bool text = true,
        bool tools = false,
      }) => PeriodSummaryGenerationPolicy.acceptsCompletion(
        requestFitContext: fits,
        stoppedNormally: stopped,
        hasText: text,
        hasToolCalls: tools,
      );

      expect(accepts(), true);
      expect(accepts(fits: false), false);
      expect(accepts(stopped: false), false);
      expect(accepts(text: false), false);
      expect(accepts(tools: true), false);
    });
  });
}
