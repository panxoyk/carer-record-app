/// Versioned manifest of the speech-recognition model the app runs on-device.
///
/// The file `app/assets/asr_model_manifest.json` is the single source of truth
/// for origin, licence, version and integrity of the weights. The weights
/// themselves are never committed: they are downloaded or pre-installed into the
/// application support directory and verified before use.
library;

import 'dart:convert';

class AsrModelFile {
  const AsrModelFile({
    required this.name,
    required this.sha256,
    this.bytes = 0,
  });

  final String name;
  final String sha256;
  final int bytes;

  factory AsrModelFile.fromJson(Map<String, Object?> json) {
    return AsrModelFile(
      name: json['name'] as String? ?? '',
      sha256: (json['sha256'] as String? ?? '').toLowerCase(),
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'name': name,
    'sha256': sha256,
    'bytes': bytes,
  };
}

class AsrModelManifest {
  const AsrModelManifest({
    required this.id,
    required this.family,
    required this.language,
    required this.engine,
    required this.engineVersion,
    required this.version,
    required this.license,
    required this.sourceUrl,
    required this.archiveSha256,
    required this.archiveBytes,
    required this.parts,
    required this.files,
    required this.parameters,
  });

  final String id;

  /// Recognizer family understood by the adapter, e.g. `whisper`.
  final String family;
  final String language;

  /// Engine identifier recorded in the provenance metadata.
  final String engine;
  final String engineVersion;
  final String version;

  /// SPDX-ish identifier plus any usage condition, kept verbatim from the
  /// upstream model card.
  final String license;

  final String sourceUrl;
  final String archiveSha256;
  final int archiveBytes;

  /// Family-specific role to file name, e.g. `encoder`, `decoder`, `tokens`.
  final Map<String, String> parts;

  final List<AsrModelFile> files;

  /// Decoder parameters recorded in the provenance metadata. They are numbers
  /// and booleans only: the database rejects free text inside
  /// `transcription_metadata` (ADR-016).
  final Map<String, Object?> parameters;

  factory AsrModelManifest.fromJson(Map<String, Object?> json) {
    final files = json['files'];
    final parts = json['parts'];
    return AsrModelManifest(
      id: json['id'] as String? ?? '',
      family: json['family'] as String? ?? '',
      language: json['language'] as String? ?? 'es',
      engine: json['engine'] as String? ?? 'sherpa_onnx',
      engineVersion: json['engine_version'] as String? ?? '',
      version: json['version'] as String? ?? '',
      license: json['license'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
      archiveSha256: (json['archive_sha256'] as String? ?? '').toLowerCase(),
      archiveBytes: (json['archive_bytes'] as num?)?.toInt() ?? 0,
      parts:
          parts is Map<Object?, Object?>
              ? parts.map(
                (key, value) => MapEntry(key.toString(), value.toString()),
              )
              : const <String, String>{},
      files:
          files is List
              ? files
                  .whereType<Map<Object?, Object?>>()
                  .map(
                    (item) =>
                        AsrModelFile.fromJson(Map<String, Object?>.from(item)),
                  )
                  .toList(growable: false)
              : const <AsrModelFile>[],
      parameters: Map<String, Object?>.from(
        (json['parameters'] as Map<Object?, Object?>?) ??
            const <String, Object?>{},
      ),
    );
  }

  factory AsrModelManifest.parse(String source) {
    final value = jsonDecode(source);
    if (value is! Map) {
      throw const FormatException(
        'El manifiesto de modelo debe ser un objeto.',
      );
    }
    return AsrModelManifest.fromJson(Map<String, Object?>.from(value));
  }

  /// Identifier-style values only, because this string ends up in jsonb that the
  /// database constrains to `^[A-Za-z0-9._:+/-]{1,128}$`.
  String get safeId => id.replaceAll(RegExp(r'[^A-Za-z0-9._:+/-]'), '-');

  String get safeVersion =>
      version.replaceAll(RegExp(r'[^A-Za-z0-9._:+/-]'), '-');

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'family': family,
    'language': language,
    'engine': engine,
    'engine_version': engineVersion,
    'version': version,
    'license': license,
    'source_url': sourceUrl,
    'archive_sha256': archiveSha256,
    'archive_bytes': archiveBytes,
    'parts': parts,
    'files': files.map((file) => file.toJson()).toList(),
    'parameters': parameters,
  };

  bool get isUsable =>
      id.isNotEmpty &&
      family.isNotEmpty &&
      version.isNotEmpty &&
      archiveUrl.isNotEmpty &&
      archiveSha256.isNotEmpty &&
      files.isNotEmpty;

  /// Every role the family needs must be declared, otherwise the engine would
  /// be pointed at a missing file at load time.
  bool get hasRequiredParts {
    const requiredByFamily = <String, List<String>>{
      'whisper': ['encoder', 'decoder', 'tokens'],
    };
    final required = requiredByFamily[family] ?? const <String>[];
    return required.every((role) => (parts[role] ?? '').isNotEmpty) &&
        parts.keys.toSet().containsAll(required);
  }

  String get archiveUrl => '$sourceUrl/$id.tar.bz2';
}
