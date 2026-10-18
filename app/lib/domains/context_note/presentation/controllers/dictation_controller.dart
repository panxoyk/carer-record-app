import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../on_device_ai/domain/asr_engine.dart';
import '../../domain/dictation_audio.dart';
import '../../domain/entities/context_note.dart';
import '../../domain/entities/dictation_stage.dart';

/// Owns the temporary lifecycle of a single dictation session.
class DictationController extends ChangeNotifier {
  DictationController({
    required this.audioFactory,
    required this.artifactsFactory,
    required this.loadEngine,
    required this.newId,
  });

  final DictationAudio Function() audioFactory;
  final DictationArtifacts Function() artifactsFactory;
  final Future<AsrEngine?> Function() loadEngine;
  final String Function() newId;
  DictationAudio? _audio;
  DictationArtifacts? _artifacts;
  DictationAudio get _sound => _audio ??= audioFactory();
  DictationArtifacts get _vault => _artifacts ??= artifactsFactory();
  DictationSession session = const DictationSession();
  String? operationId;
  bool busy = false;
  bool _closed = false;
  int _epoch = 0;
  Future<void>? _cleanup;
  bool _cleanupFailed = false;

  void updateDraft(String value) {
    if (session.transcript == null || _closed) return;
    _emit(
      session.copyWith(draftText: value, stage: DictationStage.readyToConfirm),
    );
  }

  void _emit(DictationSession value) {
    session = value;
    if (!_closed) notifyListeners();
  }

  Future<void> toggleRecording() async {
    if (session.stage == DictationStage.recording) return stopAndTranscribe();
    if (_closed) return;
    if (operationId != null && !await discard()) return;
    final epoch = _epoch;
    final engine = await loadEngine();
    if (_closed || epoch != _epoch) return;
    if (engine == null) {
      _emit(
        session.copyWith(
          stage: DictationStage.failed,
          error: 'El Dictado no está disponible.',
        ),
      );
      return;
    }
    final allowed = await _sound.requestPermission();
    if (_closed || epoch != _epoch) return;
    if (!allowed) {
      _emit(
        session.copyWith(
          stage: DictationStage.failed,
          error: 'El micrófono está bloqueado. Revisa el permiso del sistema.',
        ),
      );
      return;
    }
    final id = newId();
    operationId = id;
    try {
      final path = await _sound.prepareSandboxPath(id);
      if (_closed || epoch != _epoch) return;
      _emit(session.copyWith(recordingPath: path));
      await _vault.registerCapture(id, path);
      if (_closed || epoch != _epoch) return;
      _emit(
        session.copyWith(
          stage: DictationStage.recording,
          recordingPath: path,
          transcript: null,
          draftText: '',
          clearError: true,
        ),
      );
      await _sound.startPcm16(path);
      if (_closed || epoch != _epoch) return;
    } catch (_) {
      try {
        await discard();
      } catch (_) {
        // Retain operationId so a later discard can retry the registered purge.
      }
      _emit(
        session.copyWith(
          stage: DictationStage.failed,
          error: 'No se pudo iniciar la grabación de audio.',
        ),
      );
    }
  }

  Future<void> stopAndTranscribe() async {
    final id = operationId;
    var path = session.recordingPath;
    final epoch = _epoch;
    try {
      final stopped = await _sound.stop();
      if (stopped != null && stopped.isNotEmpty) path = stopped;
      if (path == null) return;
      _emit(
        session.copyWith(
          stage: DictationStage.transcribingLocal,
          recordingPath: path,
        ),
      );
      busy = true;
      notifyListeners();
      final engine = await loadEngine();
      if (_closed || epoch != _epoch) {
        return;
      }
      if (engine == null) {
        throw const AsrUnavailableException('El Dictado no está disponible.');
      }
      final wave = await _sound.prepareWav(path);
      final transcript = await engine.transcribe(wave);
      if (_closed || epoch != _epoch || id == null) return;
      if (_closed || epoch != _epoch) return;
      await _vault.putDraft(
        id,
        transcription: transcript.text,
        recordingPath: path,
      );
      if (_closed || epoch != _epoch) return;
      if (transcript.text.trim().isEmpty) {
        _emit(
          session.copyWith(
            stage: DictationStage.readyToConfirm,
            transcript: transcript,
            draftText: '',
            error: 'La transcripción local quedó vacía. Vuelve a grabar o escribe el hito.',
          ),
        );
        return;
      }
      _emit(
        session.copyWith(
          stage: DictationStage.readyToConfirm,
          transcript: transcript,
          draftText: transcript.text,
          clearError: true,
        ),
      );
    } on AsrUnavailableException catch (e) {
      if (!_closed && epoch == _epoch) {
        _emit(session.copyWith(stage: DictationStage.failed, error: e.reason));
      }
    } on AsrTranscriptionException catch (e) {
      if (!_closed && epoch == _epoch) {
        _emit(session.copyWith(stage: DictationStage.failed, error: e.reason));
      }
    } catch (_) {
      if (!_closed && epoch == _epoch) {
        _emit(
          session.copyWith(
            stage: DictationStage.failed,
            error: 'No se pudo transcribir localmente. Intenta de nuevo.',
          ),
        );
      }
    } finally {
      busy = false;
      if (!_closed) notifyListeners();
    }
  }

  Future<bool> preview() async {
    final path = session.recordingPath;
    if (path == null) return false;
    try {
      await _sound.togglePreview(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _discardArtifacts() async {
    final id = operationId;
    final path = session.recordingPath;
    if (_audio != null && session.stage == DictationStage.recording) {
      await _audio!.stop();
    }
    await _audio?.stopPreview();
    if (id != null) await _vault.purge(id, recordingPath: path);
    operationId = null;
    _emit(
      session.copyWith(
        stage: DictationStage.discarded,
        recordingPath: null,
        transcript: null,
        draftText: null,
        clearError: true,
      ),
    );
  }

  Future<bool> discard({bool notifyFailure = true}) async {
    ++_epoch;
    try {
      await _discardArtifacts();
      _cleanupFailed = false;
      return true;
    } catch (_) {
      _cleanupFailed = true;
      if (notifyFailure) {
        _emit(
          session.copyWith(
            error: 'No se pudieron eliminar los archivos temporales.',
          ),
        );
      }
      return false;
    }
  }

  @override
  void dispose() {
    _closed = true;
    ++_epoch;
    _cleanup = (_cleanupFailed ? Future<void>.value() : _discardArtifacts())
        .catchError((Object _) {})
        .whenComplete(() async {
          try {
            await _audio?.dispose();
          } catch (_) {}
        });
    unawaited(_cleanup!);
    super.dispose();
  }
}
