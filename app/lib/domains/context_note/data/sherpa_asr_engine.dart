import 'dart:io';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../domain/asr_engine.dart';
import '../domain/entities/context_note.dart';
import 'asr_model_manifest.dart';

/// On-device speech recognition backed by `sherpa_onnx`.
///
/// The adapter is the only place that knows about the native SDK, the WAV
/// container and where the weights live. The domain depends on [AsrEngine] only,
/// and nothing here performs any network call: the model is read from the local
/// application support directory, which is what makes ADR-016's "no egress"
/// claim checkable by inspection as well as by network capture.
class SherpaAsrEngine implements AsrEngine {
  SherpaAsrEngine({
    required AsrModelManifest manifest,
    required Directory modelDirectory,
    Duration loadTimeout = const Duration(seconds: 60),
  }) : _manifest = manifest,
       _modelDirectory = modelDirectory,
       _loadTimeout = loadTimeout;

  final AsrModelManifest _manifest;
  final Directory _modelDirectory;
  final Duration _loadTimeout;

  sherpa.OfflineRecognizer? _recognizer;
  bool _bindingsReady = false;

  @override
  String get engineId => _manifest.engine;

  @override
  bool get isAvailable => _recognizer != null;

  /// Short description used in error messages and the model screen.
  String get modelId => _manifest.safeId;

  /// Absolute path of a weight declared in the manifest.
  String filePath(String name) =>
      '${_modelDirectory.path}${Platform.pathSeparator}$name';

  /// Loads the recognizer. Returns false when the weights are not installed, so
  /// the caller can keep the text milestone available instead of failing.
  Future<bool> load() async {
    if (_recognizer != null) return true;
    if (!_manifest.isUsable || !_manifest.hasRequiredParts) return false;
    for (final file in _manifest.files) {
      if (!File(filePath(file.name)).existsSync()) return false;
    }
    try {
      if (!_bindingsReady) {
        await sherpa.initBindingsAsync().timeout(_loadTimeout);
        _bindingsReady = true;
      }
      _recognizer = sherpa.OfflineRecognizer(
        sherpa.OfflineRecognizerConfig(
          model: _buildModelConfig(),
          decodingMethod: 'greedy_search',
          maxActivePaths: 4,
        ),
      );
      return _recognizer != null;
    } catch (_) {
      // A missing or incompatible runtime is reported as "not available"; it
      // never escalates to a remote service.
      _recognizer = null;
      return false;
    }
  }

  sherpa.OfflineModelConfig _buildModelConfig() {
    final part = _manifest.parts;
    switch (_manifest.family) {
      case 'whisper':
        return sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: filePath(part['encoder'] ?? ''),
            decoder: filePath(part['decoder'] ?? ''),
            language: _manifest.language,
            task: 'transcribe',
          ),
          tokens: filePath(part['tokens'] ?? ''),
          numThreads: _numThreads,
          provider: 'cpu',
        );
      default:
        throw AsrUnavailableException(
          'Familia de modelo no soportada: ${_manifest.family}',
        );
    }
  }

  int get _numThreads {
    final value = _manifest.parameters['num_threads'];
    return value is int && value > 0 ? value : 2;
  }

  @override
  Future<AsrTranscript> transcribe(String wavPath) async {
    final recognizer = _recognizer;
    if (recognizer == null) {
      throw const AsrUnavailableException(
        'El motor de transcripción local no está disponible.',
      );
    }
    if (!File(wavPath).existsSync()) {
      throw const AsrUnavailableException('La grabación local no existe.');
    }
    final wave = sherpa.readWave(wavPath);
    if (wave.samples.isEmpty || wave.sampleRate <= 0) {
      throw const AsrTranscriptionException(
        'El audio grabado no se pudo decodificar.',
      );
    }
    final stream = recognizer.createStream();
    try {
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      final durationMs = (wave.samples.length / wave.sampleRate * 1000).round();
      return AsrTranscript(
        text: result.text.trim(),
        metadata: buildMetadata(durationMs: durationMs),
      );
    } catch (error) {
      throw AsrTranscriptionException('Falló la transcripción local: $error');
    } finally {
      stream.free();
    }
  }

  /// Provenance recorded with the milestone. It carries no text: only the
  /// engine, the model identity and technical measurements, exactly the keys the
  /// database accepts (ADR-016 decision 3).
  TranscriptionMetadata buildMetadata({required int durationMs}) {
    return TranscriptionMetadata(
      engine: _manifest.engine,
      model: _manifest.safeId,
      modelVersion: _manifest.safeVersion,
      modelChecksum:
          _manifest.archiveSha256.isEmpty ? null : _manifest.archiveSha256,
      durationMs: durationMs,
      parameters: Map<String, Object?>.from(_manifest.parameters),
      pipelineVersion: _pipelineVersion,
    );
  }

  static const String _pipelineVersion = '1.0.0';

  Future<void> dispose() async {
    _recognizer?.free();
    _recognizer = null;
  }
}
