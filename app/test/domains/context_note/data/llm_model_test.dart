import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:carer_record_app/domains/context_note/data/llama_gguf_synthesis_provider.dart';
import 'package:carer_record_app/domains/context_note/data/llm_model_installer.dart';
import 'package:carer_record_app/domains/context_note/data/llm_model_manifest.dart';
import 'package:carer_record_app/domains/context_note/domain/synthesis_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LlmModelManifest', () {
    test('parses the shipped manifest contract', () {
      final manifest = LlmModelManifest.parse(_manifestJson());
      expect(manifest.id, 'qwen3-1.7b-instruct-q4_k_m');
      expect(manifest.runtime, 'llamadart');
      expect(manifest.license, contains('Apache-2.0'));
      expect(manifest.sha256, hasLength(64));
      expect(manifest.isUsable, isTrue);
      expect(manifest.contextSize, 2048);
      expect(manifest.threads, 4);
      expect(manifest.maxTokens, 512);
      expect(
        manifest.downloadUri.toString(),
        'https://example.test/Qwen3-1.7B-Q4_K_M.gguf',
      );
    });

    test('rejects a non-object payload', () {
      expect(() => LlmModelManifest.parse('"x"'), throwsFormatException);
    });

    test('is unusable without a checksum, so tampered weights cannot load', () {
      final manifest = LlmModelManifest.parse(
        jsonEncode(<String, Object?>{
          'id': 'x',
          'file': 'x.gguf',
          'file_name': 'x.gguf',
          'source_url': 'https://example.test',
        }),
      );
      expect(manifest.sha256, isEmpty);
      expect(manifest.isUsable, isFalse);
    });

    test('is unusable over a non-https source', () {
      final manifest = LlmModelManifest.parse(
        jsonEncode(<String, Object?>{
          'id': 'x',
          'file': 'x.gguf',
          'file_name': 'x.gguf',
          'sha256': 'a' * 64,
          'source_url': 'http://example.test',
        }),
      );
      expect(manifest.isUsable, isFalse);
    });
  });

  group('LlmModelInstaller', () {
    late Directory target;

    setUp(() async {
      target = await Directory.systemTemp.createTemp('cra-llm-');
    });

    tearDown(() async {
      if (target.existsSync()) target.deleteSync(recursive: true);
    });

    test('an absent weight is reported as not installed', () async {
      const installer = LlmModelInstaller();
      expect(
        await installer.isInstalled(
          LlmModelManifest.parse(_manifestJson()),
          target,
        ),
        isFalse,
      );
    });

    test('a weight with a matching digest is installed', () async {
      const installer = LlmModelInstaller();
      final manifest = LlmModelManifest.parse(_manifestJson());
      final file = File(
        '${target.path}${Platform.pathSeparator}${manifest.fileName}',
      );
      file.writeAsStringSync('pesos sinteticos');
      expect(
        await installer.isInstalled(
          _withDigest(manifest, await sha256Of(file)),
          target,
        ),
        isTrue,
      );
    });

    test('a weight whose bytes changed is not installed', () async {
      const installer = LlmModelInstaller();
      final manifest = LlmModelManifest.parse(_manifestJson());
      final file = File(
        '${target.path}${Platform.pathSeparator}${manifest.fileName}',
      );
      file.writeAsStringSync('otra cosa');
      expect(await installer.isInstalled(manifest, target), isFalse);
    });

    test(
      'a tampered download is rejected and the partial file removed',
      () async {
        final manifest = LlmModelManifest.parse(_manifestJson());
        await expectLater(
          LlmModelInstaller().install(
            manifest,
            target,
            client: _FakeHttpClient(utf8.encode('pesos alterados')),
          ),
          throwsA(isA<FormatException>()),
        );
        final partial = File(
          '${target.path}${Platform.pathSeparator}${manifest.fileName}.part',
        );
        expect(partial.existsSync(), isFalse);
        expect(
          File('${target.path}${Platform.pathSeparator}${manifest.fileName}')
              .existsSync(),
          isFalse,
        );
      },
    );

    test('a verified download lands with the declared file name', () async {
      final payload = utf8.encode('pesos sinteticos verificados');
      final digest = sha256.convert(payload).toString();
      final manifest = _withDigest(
        LlmModelManifest.parse(_manifestJson()),
        digest,
      );
      await LlmModelInstaller().install(
        manifest,
        target,
        client: _FakeHttpClient(payload),
      );
      final installed = File(
        '${target.path}${Platform.pathSeparator}${manifest.fileName}',
      );
      expect(installed.existsSync(), isTrue);
      expect(await installerInstalled(manifest, target), isTrue);
    });
  });

  group('LlamaGgufSynthesisProvider', () {
    test(
      'is unavailable when the weights are absent and never downloads',
      () async {
        final directory = await Directory.systemTemp.createTemp('cra-llm-run-');
        addTearDown(() async {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final provider = LlamaGgufSynthesisProvider(
          manifest: LlmModelManifest.parse(_manifestJson()),
          modelDirectory: directory,
        );
        expect(await provider.load(), isFalse);
        expect(provider.isAvailable, isFalse);
        await provider.dispose();
      },
    );

    test(
      'reports a stable code instead of generating without a model',
      () async {
        final directory = await Directory.systemTemp.createTemp('cra-llm-run-');
        addTearDown(() async {
          if (directory.existsSync()) directory.deleteSync(recursive: true);
        });
        final provider = LlamaGgufSynthesisProvider(
          manifest: LlmModelManifest.parse(_manifestJson()),
          modelDirectory: directory,
        );
        expect(
          () => provider.synthesize(
            SynthesisRequest(
              purpose: SynthesisPurpose.improveNoteText,
              text: 'texto de la autora',
              promptVersion: 'v1',
              timeout: const Duration(seconds: 1),
              maxOutputChars: 100,
            ),
          ),
          throwsA(
            isA<SynthesisException>().having(
              (e) => e.code,
              'code',
              SynthesisErrorCode.unavailable,
            ),
          ),
        );
        await provider.dispose();
      },
    );
  });
}

Future<String> sha256Of(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

Future<bool> installerInstalled(
  LlmModelManifest manifest,
  Directory target,
) async {
  const installer = LlmModelInstaller();
  return installer.isInstalled(manifest, target);
}

LlmModelManifest _withDigest(LlmModelManifest manifest, String digest) {
  return LlmModelManifest.parse(
    jsonEncode(<String, Object?>{
      'id': manifest.id,
      'runtime': manifest.runtime,
      'runtime_version': manifest.runtimeVersion,
      'language': manifest.language,
      'license': manifest.license,
      'source_url': manifest.sourceUrl,
      'file': manifest.file,
      'file_name': manifest.fileName,
      'sha256': digest,
      'bytes': manifest.bytes,
      'parameters': manifest.parameters,
    }),
  );
}

String _manifestJson() => jsonEncode(<String, Object?>{
  'id': 'qwen3-1.7b-instruct-q4_k_m',
  'runtime': 'llamadart',
  'runtime_version': '0.11.1',
  'language': 'es',
  'license': 'Apache-2.0',
  'source_url': 'https://example.test',
  'file': 'Qwen3-1.7B-Q4_K_M.gguf',
  'file_name': 'qwen3-1.7b-instruct-q4_k_m.gguf',
  'sha256': 'b139949c5bd74937ad8ed8c8cf3d9ffb1e99c866c823204dc42c0d91fa181897',
  'bytes': 1107409472,
  'parameters': <String, Object?>{
    'context_size': 2048,
    'threads': 4,
    'max_tokens': 512,
  },
});

/// Minimal `HttpClient` that replays a fixed payload, so integrity handling can
/// be exercised without a network.
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this.payload);

  final List<int> payload;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeRequest(payload);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used');
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.payload);

  final List<int> payload;

  @override
  Future<HttpClientResponse> close() async => _FakeResponse(payload);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used');
}

class _FakeResponse implements HttpClientResponse {
  _FakeResponse(this.payload);

  final List<int> payload;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  int get contentLength => payload.length;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(payload).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} is not used');
}
