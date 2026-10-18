import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'llm_model_manifest.dart';

/// Progress of the model download shown on first run.
class LlmDownloadProgress {
  const LlmDownloadProgress({
    required this.received,
    required this.total,
    required this.stage,
  });

  final int received;
  final int total;
  final String stage;

  double? get fraction =>
      total <= 0 ? null : (received / total).clamp(0.0, 1.0);
}

/// Downloads and verifies the GGUF weights declared in the manifest.
///
/// This download is the only network traffic the synthesis pipeline produces,
/// and it carries model bytes, not clinical content. Generation itself never
/// touches the network.
class LlmModelInstaller {
  const LlmModelInstaller();

  Future<void> install(
    LlmModelManifest manifest,
    Directory target, {
    void Function(LlmDownloadProgress)? onProgress,
    HttpClient? client,
  }) async {
    if (!manifest.isUsable) {
      throw const FormatException('El manifiesto de modelo no es utilizable.');
    }
    await target.create(recursive: true);
    final http = client ?? HttpClient();
    final partial = File(
      '${target.path}${Platform.pathSeparator}${manifest.fileName}.part',
    );
    try {
      await _download(manifest, partial, onProgress, http);
      final digest = (await sha256.bind(partial.openRead()).first).toString();
      if (digest != manifest.sha256) {
        unawaited(partial.delete());
        throw const FormatException(
          'El modelo descargado no coincide con el checksum del manifiesto.',
        );
      }
      final finalFile = File(
        '${target.path}${Platform.pathSeparator}${manifest.fileName}',
      );
      await partial.rename(finalFile.path);
    } finally {
      if (client == null) http.close(force: true);
    }
  }

  /// True only when the weight exists with the expected digest.
  Future<bool> isInstalled(LlmModelManifest manifest, Directory target) async {
    if (!manifest.isUsable) return false;
    final file = File(
      '${target.path}${Platform.pathSeparator}${manifest.fileName}',
    );
    if (!file.existsSync()) return false;
    final digest = (await sha256.bind(file.openRead()).first).toString();
    return digest == manifest.sha256;
  }

  /// Deletes the weights, for instance when the declared version changes.
  Future<void> remove(LlmModelManifest manifest, Directory target) async {
    final file = File(
      '${target.path}${Platform.pathSeparator}${manifest.fileName}',
    );
    if (file.existsSync()) await file.delete();
  }

  Future<void> _download(
    LlmModelManifest manifest,
    File target,
    void Function(LlmDownloadProgress)? onProgress,
    HttpClient http,
  ) async {
    final request = await http.getUrl(manifest.downloadUri);
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException(
        'No se pudo descargar el modelo (${response.statusCode}).',
        uri: manifest.downloadUri,
      );
    }
    final total = response.contentLength > 0
        ? response.contentLength
        : manifest.bytes;
    final sink = target.openWrite();
    var received = 0;
    onProgress?.call(
      LlmDownloadProgress(received: 0, total: total, stage: 'descargando'),
    );
    try {
      await for (final chunk in response) {
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(
          LlmDownloadProgress(
            received: received,
            total: total,
            stage: 'descargando',
          ),
        );
      }
    } finally {
      await sink.close();
    }
    onProgress?.call(
      LlmDownloadProgress(
        received: received,
        total: total,
        stage: 'verificando',
      ),
    );
  }
}
