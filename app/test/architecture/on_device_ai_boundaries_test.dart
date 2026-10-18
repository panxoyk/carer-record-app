import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/asr_engine.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/asr_transcript.dart';
import 'package:carer_record_app/domains/on_device_ai/domain/synthesis_provider.dart';

void main() {
  final root = Directory('lib/domains');

  test(
    'on-device AI has no clinical, auth, institution or Supabase imports',
    () {
      final files = root
          .sublist('on_device_ai')
          .where((file) => file.path.endsWith('.dart'));
      expect(files, isNotEmpty);
      for (final file in files) {
        final directives = file
            .readAsLinesSync()
            .where(
              (line) =>
                  line.startsWith('import ') || line.startsWith('export '),
            )
            .join('\n')
            .toLowerCase();
        for (final forbidden in [
          'context_note',
          'patient',
          'auth',
          'institutional',
          'supabase',
        ]) {
          expect(directives, isNot(contains(forbidden)));
        }
      }
    },
  );

  test('domain files do not import implementation or presentation layers', () {
    for (final file in root.listSync(recursive: true).whereType<File>()) {
      if (!file.path.contains('/domain/') || !file.path.endsWith('.dart')) {
        continue;
      }
      final source = file.readAsStringSync();
      expect(source, isNot(matches(RegExp(r"package:flutter/"))));
      expect(
        source,
        isNot(matches(RegExp(r"package:(record|just_audio|path_provider)/"))),
      );
      final uriPattern = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
      for (final match in uriPattern.allMatches(source)) {
        final uri = match.group(1)!;
        String? targetPath;
        if (uri.startsWith('package:carer_record_app/')) {
          targetPath =
              'lib/${uri.substring('package:carer_record_app/'.length)}';
        } else if (uri.startsWith('.')) {
          targetPath = Uri.file(file.absolute.path).resolve(uri).toFilePath();
        }
        if (targetPath != null) {
          final segments = Uri.file(targetPath).pathSegments;
          expect(
            segments,
            isNot(contains('data')),
            reason: '$uri in ${file.path}',
          );
          expect(
            segments,
            isNot(contains('presentation')),
            reason: '$uri in ${file.path}',
          );
        }
      }
    }
  });

  test('milestone editor has no platform IO or persistence imports', () {
    final source = File(
      'lib/domains/context_note/presentation/milestone_editor_sheet.dart',
    ).readAsStringSync();
    for (final dependency in [
      "'dart:io'",
      'package:record/',
      'package:just_audio/',
      'package:path_provider/',
      'package:supabase',
    ]) {
      expect(source, isNot(contains(dependency)));
    }
  });

  test('capability ports accept independent consumers and fakes', () async {
    final engine = _FakeAsr();
    final transcript = await engine.transcribe('local.wav');
    expect(transcript.text, 'synthetic');
    final provider = _FakeSynthesis();
    final result = await provider.synthesize(
      const SynthesisRequest(
        purpose: SynthesisPurpose.improveNoteText,
        text: 'draft',
        promptVersion: 'test',
        timeout: Duration(seconds: 1),
        maxOutputChars: 100,
      ),
    );
    expect(result.text, 'draft');
  });
}

extension on Directory {
  Iterable<File> sublist(String child) =>
      Directory('$path/$child').listSync(recursive: true).whereType<File>();
}

class _FakeAsr implements AsrEngine {
  @override
  bool get isAvailable => true;
  @override
  String get engineId => 'fake';
  @override
  Future<AsrTranscript> transcribe(String wavPath) async => AsrTranscript(
    text: 'synthetic',
    metadata: const TranscriptionMetadata(
      engine: 'fake',
      pipelineVersion: 'test',
    ),
  );
}

class _FakeSynthesis implements SynthesisProvider {
  @override
  bool get isAvailable => true;
  @override
  String get modelVersion => 'fake';
  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async => SynthesisResult(
    text: request.text,
    modelVersion: modelVersion,
    promptVersion: request.promptVersion,
  );
  @override
  Future<void> dispose() async {}
}
