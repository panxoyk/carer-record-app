import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:carer_record_app/domains/context_note/data/plugin_dictation_audio.dart';

void main() {
  test(
    'preview lazily creates player and reloads every changed path',
    () async {
      final player = _FakeAudioPlayer();
      var factoryCalls = 0;
      final audio = PluginDictationAudio(
        playerFactory: () {
          factoryCalls++;
          return player;
        },
      );

      expect(factoryCalls, 0);
      expect(await audio.togglePreview('/audio/a.wav'), isTrue);
      expect(factoryCalls, 1);
      expect(player.paths, ['/audio/a.wav']);
      player.duration = const Duration(seconds: 1);
      await audio.stopPreview();
      expect(await audio.togglePreview('/audio/b.wav'), isTrue);
      expect(player.paths, ['/audio/a.wav', '/audio/b.wav']);

      player.playing = true;
      expect(await audio.togglePreview('/audio/b.wav'), isFalse);
      expect(player.pauseCalls, 1);
      await audio.dispose();
    },
  );
}

class _FakeAudioPlayer implements AudioPlayer {
  final paths = <String>[];
  @override
  Duration? duration;
  @override
  bool playing = false;
  int pauseCalls = 0;

  @override
  Future<Duration?> setFilePath(
    String path, {
    Duration? initialPosition,
    bool preload = true,
    dynamic tag,
  }) async {
    paths.add(path);
    return duration;
  }

  @override
  Future<void> play() async {
    playing = true;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    playing = false;
  }

  @override
  Future<void> stop() async {
    playing = false;
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
