import 'dart:convert';
import 'dart:io';

import 'package:carer_record_app/domains/on_device_ai/data/llama_gguf_synthesis_provider.dart';
import 'package:carer_record_app/domains/on_device_ai/data/llm_model_manifest.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';
import 'package:carer_record_app/domains/period_summary/domain/period_summary.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/summary_evaluation_corpus.dart';

void main() {
  final enabled = Platform.environment['CRA_SUMMARY_EVALUATION'] == '1';
  final modelPath = Platform.environment['CRA_LLM_MODEL_DIR'];

  test(
    'opt-in native summary evaluation (human review only)',
    () async {
      if (modelPath == null || modelPath.isEmpty) {
        throw StateError('Missing CRA_LLM_MODEL_DIR for opt-in evaluation.');
      }
      final manifestFile = File('assets/llm_model_manifest.json');
      final manifest = LlmModelManifest.parse(
        await manifestFile.readAsString(),
      );
      final weights = File(
        '$modelPath${Platform.pathSeparator}${manifest.fileName}',
      );
      if (!manifest.isUsable || !await weights.exists()) {
        throw StateError(
          'Manifest/model file unavailable; no downloader is used.',
        );
      }
      if ((await weights.stat()).size != manifest.bytes ||
          (await sha256.bind(weights.openRead()).first).toString() !=
              manifest.sha256) {
        throw StateError('Local weights do not match manifest size/checksum.');
      }

      final repeat =
          Platform.environment['CRA_SUMMARY_EVALUATION_REPEAT'] == '3' ? 3 : 1;
      final provider = LlamaGgufSynthesisProvider(
        manifest: manifest,
        modelDirectory: Directory(modelPath),
        // The stream hash above verified local bytes; avoid rereading 1.1 GB.
        verifyDigestOnLoad: false,
      );
      if (!await provider.load()) {
        // ignore: avoid_print
        print('evaluation_status=load_failure model=${manifest.id}');
        throw StateError('Local model failed to load in native runtime.');
      }
      try {
        final window = SummaryWindow.utc(
          from: evaluationFrom,
          to: evaluationNow,
          timezone: evaluationTimezone,
          now: evaluationNow,
        );
        for (final item in summaryEvaluationCorpus) {
          final prepared = prepareSummary(
            item.sources,
            window: window,
            selectedKinds: SummarySourceKind.values.toSet(),
          );
          for (var run = 1; run <= repeat; run++) {
            try {
              final stopwatch = Stopwatch()..start();
              final output = await provider.synthesize(
                SynthesisRequest(
                  purpose: SynthesisPurpose.periodSummary,
                  text: prepared.prompt,
                  promptVersion: periodSummaryPromptVersion,
                  timeout: const Duration(minutes: 3),
                  maxOutputChars: 20000,
                  idempotencyKey: 'evaluation-${item.id}-$run',
                ),
              );
              stopwatch.stop();
              final outputShapeValid = isPeriodSummaryNarrativeOutput(
                output.text,
                prepared,
              );
              // Shape check only; passing is not a quality verdict.
              // ignore: avoid_print
              print(
                '''evaluation_candidate case=${item.id} run=$run model=${output.modelVersion} prompt=$periodSummaryPromptVersion candidate_status=${outputShapeValid ? 'raw_candidate_only' : 'invalid_output'} runtime=${manifest.runtime}/${manifest.runtimeVersion} platform=${Platform.operatingSystem}/${Platform.operatingSystemVersion} elapsed_ms=${stopwatch.elapsedMilliseconds}
focus=${item.focus}
required_facts=${jsonEncode(item.requiredFacts)}
prohibited_claims=${jsonEncode(item.prohibitedClaims)}
output=${jsonEncode(output.text)}''',
              );
            } on SynthesisException catch (error) {
              // ignore: avoid_print
              print(
                'evaluation_status case=${item.id} run=$run model=${manifest.id} result=${error.code}',
              );
            } catch (error) {
              // ignore: avoid_print
              print(
                'evaluation_status case=${item.id} run=$run model=${manifest.id} result=${error.runtimeType}',
              );
            }
          }
        }
      } finally {
        await provider.dispose();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 100)),
  );
}
