import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
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
        await _deleteQuietly(archive);
        throw const FormatException(
          'El modelo descargado no coincide con el checksum del manifiesto.',
        );
      }
      final wanted = manifest.files.map((file) => file.name).toSet();
      try {
        await _extract(archive, target, wanted, (stage) {
          onProgress?.call(
            ModelDownloadProgress(
              received: manifest.archiveBytes,
              total: manifest.archiveBytes,
              stage: stage,
            ),
          );
        });
        await _verifyFiles(manifest, target);
      } catch (_) {
        // Verification runs after extraction, so a weight that fails its digest
        // would otherwise survive a failed install and be picked up by the
        // engine on the next launch.
        for (final file in manifest.files) {
          await _deleteQuietly(
            File('${target.path}${Platform.pathSeparator}${file.name}'),
          );
        }
        rethrow;
      }
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

  /// Unpacks a `.tar.bz2` into [target] in pure Dart.
  ///
  /// Shelling out to `tar` is not an option: there is no system tar on Android
  /// or iOS, so the archive is inflated through bzip2 into a temporary tar on
  /// disk and then walked entry by entry. Only the file names declared in
  /// [wanted] are written, and only by base name, so a crafted entry cannot
  /// escape [target] through `../` segments or absolute paths.
  Future<void> _extract(
    File archive,
    Directory target,
    Set<String> wanted,
    void Function(String stage) onStage,
  ) async {
    final unpacked = File('${archive.path}.tar');
    final extracted = <String>{};
    try {
      onStage('descomprimiendo');
      if (!await _inflate(archive, unpacked)) {
        throw const FormatException(
          'El archivo de modelo está corrupto y no se pudo descomprimir.',
        );
      }

      onStage('extrayendo');
      // The tar stays open while its entries are pulled lazily, so the stream is
      // only released once the walk is over. Leaving it open would hold a
      // descriptor and block the temporary file from being removed. Entries keep
      // their content in a lazy stream over that file rather than in memory:
      // `storeData: false` is not an option, because the tar decoder turns that
      // into `ArchiveFile.noData` and drops the payload entirely.
      final stream = InputFileStream(unpacked.path);
      try {
        final entries = TarDecoder().decodeStream(stream, verify: true);
        for (final entry in entries) {
          if (!entry.isFile) continue;
          final name = _declaredName(entry.name, wanted);
          if (name == null) continue;
          final sink = OutputFileStream(
            '${target.path}${Platform.pathSeparator}$name',
          );
          try {
            entry.writeContent(sink);
          } finally {
            sink.closeSync();
          }
          extracted.add(name);
        }
      } finally {
        stream.closeSync();
      }
      final missing = wanted.difference(extracted);
      if (missing.isNotEmpty) {
        throw FormatException(
          'El archivo de modelo no contenía ${missing.join(', ')}.',
        );
      }
    } catch (_) {
      // A half-written weight is worse than none: the engine would load it and
      // mis-transcribe. Drop whatever landed so the next attempt starts clean.
      for (final name in extracted) {
        final file = File('${target.path}${Platform.pathSeparator}$name');
        if (file.existsSync()) {
          try {
            await file.delete();
          } on FileSystemException {
            // Best effort: the caller's digest check will reject it anyway.
          }
        }
      }
      rethrow;
    } finally {
      // The tar can still be held open by a failed lazy read, and a file this
      // installer did not get to remove is recoverable while a leftover the app
      // cannot delete is not. Never let cleanup mask the real failure.
      await _deleteQuietly(unpacked);
      await _deleteQuietly(archive);
    }
  }

  Future<void> _deleteQuietly(File file) async {
    if (!file.existsSync()) return;
    try {
      await file.delete();
    } on FileSystemException {
      // Left behind on purpose; a later run overwrites it.
    }
  }

  /// Streams [archive] through bzip2 into [out], releasing both descriptors even
  /// when the data is malformed. Returns false when the stream did not decode.
  Future<bool> _inflate(File archive, File out) async {
    final input = InputFileStream(archive.path);
    final output = OutputFileStream(out.path);
    try {
      return BZip2Decoder().decodeStream(input, output);
    } finally {
      output.closeSync();
      input.closeSync();
    }
  }

  /// The base name of [raw] when the manifest declares it, otherwise null.
  ///
  /// Directory components are discarded instead of honoured, so an entry named
  /// `../../evil` can only ever resolve to `evil` inside [target] — and only if
  /// `evil` is one of the weights the manifest already vouches for.
  String? _declaredName(String raw, Set<String> wanted) {
    final base = raw.replaceAll(r'\', '/').split('/').last;
    if (base.isEmpty || base == '.' || base == '..') return null;
    return wanted.contains(base) ? base : null;
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
