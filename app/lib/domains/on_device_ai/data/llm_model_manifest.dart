import 'dart:convert';

/// Versioned manifest of the local text-assistance model (ADR-017).
///
/// `app/assets/llm_model_manifest.json` records origin, licence, version and
/// integrity. The weights are never committed: they are downloaded on first use
/// into the application support directory, verified, and deleted when they fail
/// verification. A missing model is not an error — the milestone is published
/// with the author's own text.

class LlmModelManifest {
  const LlmModelManifest({
    required this.id,
    required this.runtime,
    required this.runtimeVersion,
    required this.language,
    required this.license,
    required this.sourceUrl,
    required this.file,
    required this.fileName,
    required this.sha256,
    required this.bytes,
    required this.parameters,
  });

  final String id;
  final String runtime;
  final String runtimeVersion;
  final String language;
  final String license;

  /// Base URL the weights are fetched from. It is the only network endpoint in
  /// the synthesis pipeline and it carries no clinical content.
  final String sourceUrl;

  /// Name of the weight inside the archive-less download.
  final String file;

  /// Name used on disk, so the version is visible in the file system.
  final String fileName;

  final String sha256;
  final int bytes;
  final Map<String, Object?> parameters;

  factory LlmModelManifest.fromJson(Map<String, Object?> json) {
    return LlmModelManifest(
      id: json['id'] as String? ?? '',
      runtime: json['runtime'] as String? ?? 'llamadart',
      runtimeVersion: json['runtime_version'] as String? ?? '',
      language: json['language'] as String? ?? 'es',
      license: json['license'] as String? ?? '',
      sourceUrl: json['source_url'] as String? ?? '',
      file: json['file'] as String? ?? '',
      fileName: json['file_name'] as String? ?? '',
      sha256: (json['sha256'] as String? ?? '').toLowerCase(),
      bytes: (json['bytes'] as num?)?.toInt() ?? 0,
      parameters: Map<String, Object?>.from(
        (json['parameters'] as Map<Object?, Object?>?) ??
            const <String, Object?>{},
      ),
    );
  }

  factory LlmModelManifest.parse(String source) {
    final value = jsonDecode(source);
    if (value is! Map<Object?, Object?>) {
      throw const FormatException(
        'El manifiesto de modelo debe ser un objeto.',
      );
    }
    return LlmModelManifest.fromJson(Map<String, Object?>.from(value));
  }

  Uri get downloadUri => Uri.parse('$sourceUrl/$file');

  int get contextSize => _intParameter('context_size', 2048);
  int get threads => _intParameter('threads', 4);
  int get maxTokens => _intParameter('max_tokens', 512);

  /// Without a checksum the weights cannot be trusted, so the manifest is
  /// unusable. Failing here is what keeps a tampered download from reaching the
  /// runtime.
  bool get isUsable =>
      id.isNotEmpty &&
      file.isNotEmpty &&
      fileName.isNotEmpty &&
      sha256.isNotEmpty &&
      downloadUri.isScheme('https');

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'runtime': runtime,
    'runtime_version': runtimeVersion,
    'language': language,
    'license': license,
    'source_url': sourceUrl,
    'file': file,
    'file_name': fileName,
    'sha256': sha256,
    'bytes': bytes,
    'parameters': parameters,
  };

  int _intParameter(String key, int fallback) {
    final value = parameters[key];
    return value is int && value > 0 ? value : fallback;
  }
}
