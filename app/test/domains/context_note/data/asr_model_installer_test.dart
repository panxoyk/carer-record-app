import 'dart:io';

import 'package:archive/archive.dart';
import 'package:carer_record_app/domains/context_note/data/asr_model_installer.dart';
import 'package:carer_record_app/domains/context_note/data/asr_model_manifest.dart';
import 'package:flutter_test/flutter_test.dart';

/// The installer used to shell out to `tar`, which does not exist on Android or
/// iOS. These tests pin the pure-Dart replacement: it must inflate a `.tar.bz2`,
/// write only the weights the manifest declares, and refuse to be walked out of
/// its target directory.
void main() {
  const weights = <String, String>{
    'base-encoder.int8.onnx': 'encoder-bytes',
    'base-decoder.int8.onnx': 'decoder-bytes',
    'base-tokens.txt': 'tokens-bytes',
  };

  late Directory workspace;
  late Directory target;

  /// The server binds in `setUp` so the manifest can carry a real port, while
  /// each test still decides which bytes the route hands out.
  late HttpServer server;
  List<int> servedBytes = const [];

  setUp(() async {
    workspace = await Directory.systemTemp.createTemp('asr-installer-');
    target = Directory('${workspace.path}${Platform.pathSeparator}asr');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path.endsWith('.tar.bz2')) {
        request.response
          ..statusCode = HttpStatus.ok
          ..contentLength = servedBytes.length
          ..add(servedBytes);
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() async {
    await server.close(force: true);
    if (workspace.existsSync()) await workspace.delete(recursive: true);
  });

  Future<AsrModelManifest> manifestFor(List<int> archiveBytes) async {
    final files = <AsrModelFile>[];
    for (final entry in weights.entries) {
      files.add(
        AsrModelFile(
          name: entry.key,
          sha256: await sha256OfBytes(entry.value.codeUnits),
          bytes: entry.value.length,
        ),
      );
    }
    return AsrModelManifest(
      id: 'sherpa-onnx-whisper-base',
      family: 'whisper',
      language: 'es',
      engine: 'sherpa_onnx',
      engineVersion: '1.13.8',
      version: 'base-int8',
      license: 'MIT',
      sourceUrl: 'http://${server.address.address}:${server.port}',
      archiveSha256: await sha256OfBytes(archiveBytes),
      archiveBytes: archiveBytes.length,
      parts: const {
        'encoder': 'base-encoder.int8.onnx',
        'decoder': 'base-decoder.int8.onnx',
        'tokens': 'base-tokens.txt',
      },
      files: files,
      parameters: const {'num_threads': 2},
    );
  }

  String pathIn(String name) => '${target.path}${Platform.pathSeparator}$name';

  test('installs every declared weight from a served tar.bz2', () async {
    servedBytes = _tarBz2({
      for (final entry in weights.entries)
        'sherpa-onnx-whisper-base/${entry.key}': entry.value,
    });
    final manifest = await manifestFor(servedBytes);
    final stages = <String>[];

    await AsrModelInstaller().install(
      manifest,
      target,
      onProgress: (progress) => stages.add(progress.stage),
    );

    expect(File(pathIn('base-tokens.txt')).readAsStringSync(), 'tokens-bytes');
    expect(
      File(pathIn('base-encoder.int8.onnx')).readAsStringSync(),
      'encoder-bytes',
    );
    expect(stages, contains('descomprimiendo'));
    expect(stages, contains('extrayendo'));
    expect(await AsrModelInstaller().isInstalled(manifest, target), isTrue);
  });

  test(
    'writes only declared weights and keeps traversal inside target',
    () async {
      servedBytes = _tarBz2({
        'pkg/base-tokens.txt': 'tokens-bytes',
        'pkg/base-encoder.int8.onnx': 'encoder-bytes',
        'pkg/base-decoder.int8.onnx': 'decoder-bytes',
        // None of these is vouched for by the manifest, so none may land.
        '../../escaped.txt': 'escaped',
        '/etc/passwd': 'root',
        'pkg/notes.md': 'unrelated',
      });
      final manifest = await manifestFor(servedBytes);

      await AsrModelInstaller().install(manifest, target);

      expect(File(pathIn('base-tokens.txt')).existsSync(), isTrue);
      expect(
        File('${workspace.path}${Platform.pathSeparator}escaped.txt')
            .existsSync(),
        isFalse,
      );
      expect(File(pathIn('notes.md')).existsSync(), isFalse);
    },
  );

  test('fails when the archive lacks a declared weight', () async {
    servedBytes = _tarBz2({'pkg/base-tokens.txt': 'tokens-bytes'});
    final manifest = await manifestFor(servedBytes);

    await expectLater(
      AsrModelInstaller().install(manifest, target),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects bytes that do not match the manifest digest', () async {
    final bytes = _tarBz2({
      'pkg/base-encoder.int8.onnx': 'encoder-bytes',
      'pkg/base-decoder.int8.onnx': 'decoder-bytes',
      'pkg/base-tokens.txt': 'tokens-bytes',
    });
    final manifest = await manifestFor(bytes);
    // Same archive, one byte flipped: the digest gate must stop it before a
    // single weight is written.
    servedBytes = List<int>.from(bytes);
    servedBytes[servedBytes.length - 1] ^= 0xFF;

    await expectLater(
      AsrModelInstaller().install(manifest, target),
      throwsA(isA<FormatException>()),
    );
    expect(target.existsSync() && target.listSync().isNotEmpty, isFalse);
  });

  test('isInstalled turns false when a weight is corrupted on disk', () async {
    servedBytes = _tarBz2({
      for (final entry in weights.entries) 'pkg/${entry.key}': entry.value,
    });
    final manifest = await manifestFor(servedBytes);
    await AsrModelInstaller().install(manifest, target);

    File(pathIn('base-tokens.txt')).writeAsStringSync('tampered');

    expect(await AsrModelInstaller().isInstalled(manifest, target), isFalse);
  });
}

List<int> _tarBz2(Map<String, String> entries) {
  final archive = Archive();
  entries.forEach((name, content) {
    final bytes = content.codeUnits;
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return BZip2Encoder().encode(TarEncoder().encode(archive));
}
