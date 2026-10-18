import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import '../domain/dictation_audio.dart';
import 'draft_vault.dart';
import '../../on_device_ai/data/wav_container.dart';

class PluginDictationAudio implements DictationAudio {
  PluginDictationAudio({AudioPlayer Function()? playerFactory})
    : _playerFactory = playerFactory ?? AudioPlayer.new;

  final AudioPlayer Function() _playerFactory;
  AudioRecorder? _recorder;
  AudioPlayer? _player;
  String? _loadedPath;

  @override
  Future<bool> requestPermission() async =>
      (_recorder ??= AudioRecorder()).hasPermission();

  @override
  Future<String> prepareSandboxPath(String operationId) async {
    final root = (await getTemporaryDirectory()).path;
    final directory = DraftVault.recordingDirectory(root, operationId);
    await directory.create(recursive: true);
    return '${directory.path}${Platform.pathSeparator}${DraftVault.recordingFileName(operationId)}';
  }

  @override
  Future<void> startPcm16(String path) async {
    await (_recorder ??= AudioRecorder()).start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: RecordingFormat.sampleRate,
        numChannels: RecordingFormat.channels,
      ),
      path: path,
    );
  }

  @override
  Future<String?> stop() async {
    final recorder = _recorder;
    if (recorder == null) return null;
    return recorder.stop();
  }

  @override
  Future<String> prepareWav(String path) => ensureWaveHeader(path);

  @override
  Future<bool> togglePreview(String path) async {
    final player = _player ??= _playerFactory();
    if (player.playing) {
      await player.pause();
      return false;
    }
    if (_loadedPath != path) {
      await player.setFilePath(path);
      _loadedPath = path;
    }
    await player.play();
    return true;
  }

  @override
  Future<void> stopPreview() async {
    await _player?.stop();
  }

  @override
  Future<void> dispose() async {
    await _player?.dispose();
    await _recorder?.dispose();
    _player = null;
    _loadedPath = null;
    _recorder = null;
  }
}
