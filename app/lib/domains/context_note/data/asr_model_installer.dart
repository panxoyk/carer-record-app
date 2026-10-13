import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'asr_model_manifest.dart';

/// Progress of one model installation, in bytes.
class ModelDownloadProgress {
  const ModelDownloadProgress({
    required this.received,
    required this.total,
    required this.stage,
  });

  final int received;
  final int total;
  final String stage;

  /// 0..1, or null while the total size is unknown.
  double? get fraction =>
      total <= 0 ? null : (received / total).clamp(0.0, 1.0);
}

/// Installs the ASR weights declared in the manifest.
///
/// The download is the only network operation in the dictation pipeline and it
/// carries no clinical content: the bytes are the published model archive. Once
/// installed, the engine runs entirely offline. Integrity is enforced before the
/// archive is unpacked, and every extracted file is verified again.
class AsrModelInstaller {
  const AsrModelInstaller();

  /// Verifies the archive and extracts it into [target], then checks each file
  /// declared in the manifest.
  Future<void> install(
    AsrModelManifest manifest,
    Directory target, {
    void Function(ModelDownloadProgress)? onProgress,
    HttpClient? client,
  }) async {
    if (!manifest.isUsable) {
      throw const FormatException('El manifiesto de modelo no es utilizable.');
    }
    await target.create(recursive: true);
    final archive = File(
      '${target.path}${Platform.pathSeparator}${manifest.id}.tar.bz2',
    );
    final http = client ?? HttpClient();

    try {
      await _download(
        Uri.parse(manifest.archiveUrl),
        archive,
        manifest.archiveBytes,
        onProgress,
        http,
      );
      final archiveDigest = await sha256.bind(archive.openRead()).first;
      if (archiveDigest.toString() != manifest.archiveSha256) {
        unawaited(archive.delete());
        throw const FormatException(
          'El modelo descargado no coincide con el checksum del manifiesto.',
        );
      }
      await _extract(archive, target);
      await _verifyFiles(manifest, target);
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// True when every declared weight is present with the expected digest.
  Future<bool> isInstalled(AsrModelManifest manifest, Directory target) async {
    for (final file in manifest.files) {
      final path = File('${target.path}${Platform.pathSeparator}${file.name}');
      if (!path.existsSync()) return false;
      if (file.sha256.isEmpty) continue;
      final digest = await sha256.bind(path.openRead()).first;
      if (digest.toString() != file.sha256) return false;
    }
    return manifest.files.isNotEmpty;
  }

  Future<void> _download(
    Uri uri,
    File archive,
    int expectedBytes,
    void Function(ModelDownloadProgress)? onProgress,
    HttpClient http,
  ) async {
    final request = await http.getUrl(uri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'No se pudo descargar el modelo (${response.statusCode}).',
        uri: uri,
      );
    }
    final total = response.contentLength > 0 ? response.contentLength : 0;
    final sink = archive.openWrite();
    var received = 0;
    onProgress?.call(
      ModelDownloadProgress(received: 0, total: total, stage: 'descargando'),
    );
    try {
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          ModelDownloadProgress(
            received: received,
            total: total == 0 ? expectedBytes : total,
            stage: 'descargando',
          ),
        );
      }
    } finally {
      await sink.close();
    }
    onProgress?.call(
      ModelDownloadProgress(
        received: received,
        total: total == 0 ? expectedBytes : total,
        stage: 'verificando',
      ),
    );
  }

  Future<void> _extract(File archive, Directory target) async {
    final result = await Process.run('tar', [
      '-xjf',
      archive.path,
      '-C',
      target.path,
    ]);
    if (result.exitCode != 0) {
      throw const FormatException('No se pudo descomprimir el modelo.');
    }
    unawaited(archive.delete());
  }

  Future<void> _verifyFiles(AsrModelManifest manifest, Directory target) async {
    for (final file in manifest.files) {
      final path = File('${target.path}${Platform.pathSeparator}${file.name}');
      if (!path.existsSync()) {
        throw FormatException('Falta el archivo de modelo ${file.name}.');
      }
      if (file.sha256.isEmpty) continue;
      final digest = await sha256.bind(path.openRead()).first;
      if (digest.toString() != file.sha256) {
        throw FormatException('Checksum incorrecto para ${file.name}.');
      }
    }
  }
}

/// sha256 of a byte buffer, exposed for tests and pre-install tooling.
Future<String> sha256OfBytes(List<int> bytes) async =>
    (await sha256.bind(Stream<List<int>>.value(bytes)).first).toString();

/// Decodes a manifest from a file, with a single, testable boundary.
Future<AsrModelManifest> readManifestFile(File file) async =>
    AsrModelManifest.parse(await file.readAsString());

/// Pretty-prints a manifest for the pre-install tooling.
String formatManifest(AsrModelManifest manifest) =>
    const JsonEncoder.withIndent('  ').convert(manifest.toJson());
