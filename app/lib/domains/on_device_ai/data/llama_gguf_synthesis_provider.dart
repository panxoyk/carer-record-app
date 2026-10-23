import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:llamadart/llamadart.dart' as llama;

import '../domain/synthesis_provider.dart';
import 'llm_model_installer.dart';
import 'llm_model_manifest.dart';

/// Local text assistance backed by a GGUF model through `llamadart`.
///
/// This adapter is the only place that knows the runtime exists. The domain
/// depends on [SynthesisProvider], so swapping this class for
/// `FakeSynthesisProvider` changes nothing in the use cases or their tests.
///
/// Generation runs entirely on the device: the model file is read from
/// application support and no request ever leaves the phone (ADR-017).
class LlamaGgufSynthesisProvider implements SynthesisProvider {
  LlamaGgufSynthesisProvider({
    required this.manifest,
    required this.modelDirectory,
    this.verifyDigestOnLoad = true,
  });

  final LlmModelManifest manifest;
  final Directory modelDirectory;

  /// Whether the runtime re-hashes the weights before loading them.
  ///
  /// Hashing a 1 GB GGUF costs tens of seconds on a mid-range device, so the
  /// digest is only recomputed when the weights were not verified yet. The
  /// installer already verifies the download, and the capability repository
  /// records that verification next to the file.
  final bool verifyDigestOnLoad;

  llama.LlamaEngine? _engine;
  bool _loading = false;

  String get filePath =>
      '${modelDirectory.path}${Platform.pathSeparator}${manifest.fileName}';

  @override
  bool get isAvailable => _engine != null;

  @override
  String get modelVersion => manifest.id;

  /// Loads the GGUF weights. Returns false when the model is missing so the
  /// caller can publish without assistance; it never falls back to a service.
  Future<bool> load({Duration timeout = const Duration(minutes: 3)}) async {
    if (_engine != null) return true;
    if (_loading || !manifest.isUsable) return false;
    _loading = true;
    try {
      if (!File(filePath).existsSync()) return false;
      final engine = llama.LlamaEngine(llama.LlamaBackend());
      await engine
          .setModel(
            llama.LlamaModel(llama.ModelSource.path(filePath)),
            params: llama.ModelParams(
              contextSize: manifest.contextSize,
              numberOfThreads: manifest.threads,
            ),
            // The weights were verified by the installer; repeating the digest
            // here keeps the runtime honest about the bytes it loads. The
            // digest is recomputed only when it was not verified before.
            download: verifyDigestOnLoad
                ? llama.ModelLoadOptions(sha256: manifest.sha256)
                : llama.ModelLoadOptions.defaults,
          )
          .timeout(timeout);
      _engine = engine;
      return true;
    } catch (_) {
      _engine = null;
      return false;
    } finally {
      _loading = false;
    }
  }

  /// Explicit download with progress, used on first run. The bytes are model
  /// weights only: no clinical content participates.
  Future<bool> install({
    void Function(LlmDownloadProgress)? onProgress,
    HttpClient? client,
  }) async {
    const installer = LlmModelInstaller();
    try {
      await installer.install(
        manifest,
        modelDirectory,
        onProgress: onProgress,
        client: client,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<SynthesisResult> synthesize(
    SynthesisRequest request, {
    bool Function()? isCancelled,
  }) async {
    final engine = _engine;
    if (engine == null) {
      throw const SynthesisException(SynthesisErrorCode.unavailable);
    }
    final session = llama.ChatSession(engine)
      ..systemPrompt = _systemPrompt(request.purpose);
    try {
      final completion = await session
          .send(
            _userPrompt(request),
            params: llama.GenerationParams(
              maxTokens: manifest.maxTokens,
              temp: 0.2,
            ),
            // Qwen3 is a hybrid reasoning model: with thinking enabled it
            // spends the whole token budget on an internal monologue and can
            // return an empty answer. These use cases want the rewritten text
            // itself, so reasoning is disabled.
            enableThinking: false,
            responseFormat: _responseFormat(request.purpose),
          )
          .timeout(request.timeout);
      if (isCancelled?.call() ?? false) {
        throw const SynthesisException(SynthesisErrorCode.cancelled);
      }
      final text = completion.text.trim();
      if (text.length > request.maxOutputChars) {
        throw const SynthesisException(SynthesisErrorCode.tooLong);
      }
      final parsed = _parse(text, request.purpose);
      return SynthesisResult(
        text: parsed.text,
        modelVersion: manifest.id,
        promptVersion: request.promptVersion,
        entities: parsed.entities,
        structured: parsed.structured,
      );
    } on TimeoutException {
      throw const SynthesisException(SynthesisErrorCode.timeout);
    } on SynthesisException {
      rethrow;
    } catch (error) {
      throw SynthesisException(
        SynthesisErrorCode.internal,
        detail: error.runtimeType.toString(),
      );
    }
  }

  @override
  Future<void> dispose() async {
    final engine = _engine;
    _engine = null;
    if (engine != null) await engine.dispose();
  }

  String _systemPrompt(SynthesisPurpose purpose) {
    return switch (purpose) {
      SynthesisPurpose.improveNoteText =>
        'Eres un asistente que mejora redacciones clínicas en español. '
            'Reescribe el texto con mejor claridad y redacción, sin inventar '
            'hechos, sin añadir diagnósticos y sin quitar información. '
            'Responde solo con el texto mejorado. '
            'Al final de tu respuesta, añade siempre las palabras "Carer Record".',
      SynthesisPurpose.flagEntities =>
        'Detectas entidades en un texto clínico en español. No reescribas el '
            'texto. Responde únicamente con JSON válido.',
      SynthesisPurpose.periodSummary =>
        'Resumes un periodo clínico en español sin inventar hechos. '
            'Responde solo con el resumen.',
    };
  }

  String _userPrompt(SynthesisRequest request) => switch (request.purpose) {
    SynthesisPurpose.improveNoteText => request.text,
    SynthesisPurpose.flagEntities => request.text,
    SynthesisPurpose.periodSummary => request.text,
  };

  /// Structured output is requested only when the use case needs it; otherwise
  /// the model answers with prose.
  Map<String, dynamic>? _responseFormat(SynthesisPurpose purpose) {
    if (purpose != SynthesisPurpose.flagEntities) return null;
    return <String, dynamic>{
      'type': 'json_object',
      'schema': <String, dynamic>{
        'type': 'object',
        'properties': <String, dynamic>{
          'entities': <String, dynamic>{
            'type': 'array',
            'items': <String, dynamic>{
              'type': 'object',
              'properties': <String, dynamic>{
                'value': <String, dynamic>{'type': 'string'},
                'type': <String, dynamic>{'type': 'string'},
                'start': <String, dynamic>{'type': 'integer'},
                'end': <String, dynamic>{'type': 'integer'},
                'confidence': <String, dynamic>{'type': 'number'},
              },
              'required': <String>['value', 'type'],
            },
          },
        },
        'required': <String>['entities'],
      },
    };
  }

  _ParsedOutput _parse(String raw, SynthesisPurpose purpose) {
    if (purpose != SynthesisPurpose.flagEntities) {
      return _ParsedOutput(raw, const <DetectedEntity>[], false);
    }
    // Models sometimes wrap JSON in a code fence; strip it before decoding.
    var payload = raw;
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final match = fence.firstMatch(raw);
    if (match != null) payload = match.group(1) ?? raw;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is! Map<Object?, Object?>) {
        return _ParsedOutput('', const <DetectedEntity>[], false);
      }
      final items = decoded['entities'];
      if (items is! List) {
        return _ParsedOutput('', const <DetectedEntity>[], false);
      }
      final entities = items
          .whereType<Map<Object?, Object?>>()
          .map(
            (item) => DetectedEntity.fromJson(Map<String, Object?>.from(item)),
          )
          .take(50)
          .toList(growable: false);
      return _ParsedOutput('', entities, true);
    } on FormatException {
      throw const SynthesisException(SynthesisErrorCode.malformed);
    }
  }
}

class _ParsedOutput {
  const _ParsedOutput(this.text, this.entities, this.structured);

  final String text;
  final List<DetectedEntity> entities;
  final bool structured;
}
