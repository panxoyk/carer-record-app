import 'dart:convert';
import 'dart:io';

import 'package:carer_record_app/domains/context_note/data/asr_model_installer.dart';
import 'package:carer_record_app/domains/context_note/data/asr_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/data/sherpa_asr_engine.dart';
import 'package:carer_record_app/domains/context_note/domain/asr_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AsrModelManifest', () {
    test('parses the versioned manifest contract', () {
      final manifest = AsrModelManifest.parse(_manifestJson());
      expect(manifest.id, 'sherpa-onnx-whisper-base');
      expect(manifest.family, 'whisper');
      expect(manifest.language, 'es');
      expect(manifest.engine, 'sherpa_onnx');
      expect(manifest.license, contains('MIT'));
      expect(manifest.files, hasLength(2));
      expect(manifest.parts['encoder'], 'encoder.onnx');
      expect(manifest.isUsable, isTrue);
      expect(manifest.hasRequiredParts, isTrue);
      expect(
        manifest.archiveUrl,
        'https://example.test/models/sherpa-onnx-whisper-base.tar.bz2',
      );
    });

    test('rejects a non-object payload', () {
      expect(() => AsrModelManifest.parse('[]'), throwsFormatException);
    });

    test('is unusable without integrity data', () {
      final manifest = AsrModelManifest.parse(
        jsonEncode(<String, Object?>{
          'id': 'x',
          'family': 'whisper',
          'source_url': 'https://example.test',
        }),
      );
      expect(manifest.isUsable, isFalse);
    });

    test('is unusable when the family is missing a required role', () {
      final manifest = AsrModelManifest.parse(
        jsonEncode(<String, Object?>{
          'id': 'x',
          'family': 'whisper',
          'version': 'v1',
          'source_url': 'https://example.test',
          'archive_sha256': 'abc',
          'files': <Object?>[
            <String, Object?>{'name': 'encoder.onnx', 'sha256': 'aa'},
          ],
          'parts': <String, Object?>{'encoder': 'encoder.onnx'},
        }),
      );
      expect(manifest.isUsable, isTrue);
      expect(manifest.hasRequiredParts, isFalse);
    });
  });

  group('AsrModelInstaller', () {
    late Directory target;

    setUp(() async {
      target = await Directory.systemTemp.createTemp('cra-model-');
    });

    tearDown(() async {
      if (target.existsSync()) target.deleteSync(recursive: true);
    });

    test(
      'reports an installation as complete only with matching digests',
      () async {
        final manifest = _manifestJson2();
        final file = File(
          '${target.path}${Platform.pathSeparator}encoder.onnx',
        );
        file.writeAsStringSync('weights');
        final installer = const AsrModelInstaller();
        expect(
          await installer.isInstalled(
            AsrModelManifest.parse(
              jsonEncode(<String, Object?>{
                ...manifest,
                'files': <Object?>[
                  <String, Object?>{
                    'name': 'encoder.onnx',
                    'sha256': await sha256OfBytes('weights'.codeUnits),
                  },
                ],
              }),
            ),
            target,
          ),
          isTrue,
        );
        file.writeAsStringSync('tampered');
        expect(
          await installer.isInstalled(
            AsrModelManifest.parse(
              jsonEncode(<String, Object?>{
                ...manifest,
                'files': <Object?>[
                  <String, Object?>{
                    'name': 'encoder.onnx',
                    'sha256': await sha256OfBytes('weights'.codeUnits),
                  },
                ],
              }),
            ),
            target,
          ),
          isFalse,
        );
      },
    );
  });

  group('SherpaAsrEngine', () {
    test('fails closed when the declared weights are absent', () async {
      final manifest = AsrModelManifest.parse(_manifestJson());
      final directory = await Directory.systemTemp.createTemp('cra-asr-');
      addTearDown(() async {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final engine = SherpaAsrEngine(
        manifest: manifest,
        modelDirectory: directory,
      );
      expect(engine.isAvailable, isFalse);
      expect(await engine.load(), isFalse);
      await engine.dispose();
    });

    test('never reaches the network to decide availability', () async {
      final manifest = AsrModelManifest.parse(_manifestJson());
      final directory = await Directory.systemTemp.createTemp('cra-asr-');
      addTearDown(() async {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });
      final engine = SherpaAsrEngine(
        manifest: manifest,
        modelDirectory: directory,
      );
      // No weights present: the engine must refuse locally instead of trying to
      // fetch anything.
      expect(await engine.load(), isFalse);
      expect(engine.isAvailable, isFalse);
    });

    test('builds provenance that carries no transcribed content', () {
      final manifest = AsrModelManifest.parse(_manifestJson());
      final engine = SherpaAsrEngine(
        manifest: manifest,
        modelDirectory: Directory.systemTemp,
      );
      final metadata = engine.buildMetadata(durationMs: 12345);
      expect(metadata.engine, 'sherpa_onnx');
      expect(metadata.durationMs, 12345);
      expect(metadata.pipelineVersion, '1.0.0');
      final json = metadata.toJson();
      expect(json['asr_model'], 'sherpa-onnx-whisper-base');
      expect(json['asr_model_version'], 'base-int8');
      expect(json['asr_model_checksum'], isA<String>());
      final pattern = RegExp(r'^[A-Za-z0-9._:+/-]{1,128}$');
      for (final value in json.values.whereType<String>()) {
        expect(pattern.hasMatch(value), isTrue, reason: value);
      }
    });

    test('throws the domain exception when asked to transcribe unloaded', () {
      final manifest = AsrModelManifest.parse(_manifestJson());
      final engine = SherpaAsrEngine(
        manifest: manifest,
        modelDirectory: Directory.systemTemp,
      );
      expect(
        () => engine.transcribe('missing.wav'),
        throwsA(isA<AsrUnavailableException>()),
      );
    });
  });
}

String _manifestJson() => jsonEncode(<String, Object?>{
  'id': 'sherpa-onnx-whisper-base',
  'family': 'whisper',
  'language': 'es',
  'engine': 'sherpa_onnx',
  'engine_version': '1.13.8',
  'version': 'base-int8',
  'license': 'MIT',
  'source_url': 'https://example.test/models',
  'archive_sha256':
      '911b2083efd7c0dca2ac3b358b75222660dc09fb716d64fbfc417ba6c99ff3de',
  'archive_bytes': 207557382,
  'parts': <String, Object?>{
    'encoder': 'encoder.onnx',
    'decoder': 'decoder.onnx',
    'tokens': 'tokens.txt',
  },
  'files': <Object?>[
    <String, Object?>{'name': 'encoder.onnx', 'sha256': 'aa'},
    <String, Object?>{'name': 'decoder.onnx', 'sha256': 'bb'},
  ],
  'parameters': <String, Object?>{'num_threads': 2},
});

Map<String, Object?> _manifestJson2() => <String, Object?>{
  'id': 'sherpa-onnx-whisper-base',
  'family': 'whisper',
  'language': 'es',
  'engine': 'sherpa_onnx',
  'engine_version': '1.13.8',
  'version': 'base-int8',
  'license': 'MIT',
  'source_url': 'https://example.test/models',
  'archive_sha256':
      '911b2083efd7c0dca2ac3b358b75222660dc09fb716d64fbfc417ba6c99ff3de',
  'archive_bytes': 207557382,
  'parts': <String, Object?>{
    'encoder': 'encoder.onnx',
    'decoder': 'decoder.onnx',
    'tokens': 'tokens.txt',
  },
  'files': <Object?>[],
  'parameters': <String, Object?>{'num_threads': 2},
};
