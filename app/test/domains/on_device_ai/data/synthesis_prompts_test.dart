import 'package:carer_record_app/domains/on_device_ai/data/synthesis_prompts.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'note prompt preserves original correction contract without signature',
    () {
      final prompt = synthesisSystemPrompt(SynthesisPurpose.improveNoteText);

      expect(prompt, contains('sin parafrasear de forma genérica'));
      expect(prompt, contains('Responde únicamente con el texto corregido.'));
      expect(prompt, isNot(contains('Carer Record')));
      expect(prompt, isNot(contains('Al final de tu respuesta')));
    },
  );

  test(
    'period summary prompt limits output to source facts without analysis',
    () {
      final prompt = synthesisSystemPrompt(SynthesisPurpose.periodSummary);

      expect(prompt, contains('exclusivamente hechos'));
      expect(
        prompt,
        contains('No infieras, analices, interpretes ni recomiendes'),
      );
      expect(prompt, contains('No incluyas la fecha/rango seleccionado'));
      expect(prompt, contains('consta registrado'));
      expect(
        prompt,
        contains('No formules diagnósticos ni conclusiones clínicas.'),
      );
    },
  );
}
