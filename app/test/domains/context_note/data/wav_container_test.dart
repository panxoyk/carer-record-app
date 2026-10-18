import 'dart:io';
import 'dart:typed_data';

import 'package:carer_record_app/domains/on_device_ai/data/wav_container.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecordingFormat', () {
    test('matches what the local recognizer expects', () {
      expect(RecordingFormat.sampleRate, 16000);
      expect(RecordingFormat.channels, 1);
      expect(RecordingFormat.bitsPerSample, 16);
      expect(RecordingFormat.byteRate, 32000);
      expect(RecordingFormat.headerBytes, 44);
    });

    test('detects an existing RIFF header', () {
      expect(
        RecordingFormat.hasWaveHeader(<int>[0x52, 0x49, 0x46, 0x46]),
        isTrue,
      );
      expect(RecordingFormat.hasWaveHeader(<int>[0, 0, 0, 0]), isFalse);
      expect(RecordingFormat.hasWaveHeader(<int>[0x52, 0x49]), isFalse);
    });

    test('builds a canonical WAV header', () {
      final dataBytes = 32000;
      final header = RecordingFormat.header(dataBytes);
      expect(header.length, 44);
      final view = ByteData.sublistView(header);

      expect(String.fromCharCodes(header.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(header.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(header.sublist(12, 16)), 'fmt ');
      expect(view.getUint32(16, Endian.little), 16);
      expect(view.getUint16(20, Endian.little), 1); // PCM
      expect(view.getUint16(22, Endian.little), 1); // mono
      expect(view.getUint32(24, Endian.little), 16000);
      expect(view.getUint32(28, Endian.little), 32000); // byte rate
      expect(view.getUint16(32, Endian.little), 2); // block align
      expect(view.getUint16(34, Endian.little), 16); // bits
      expect(String.fromCharCodes(header.sublist(36, 40)), 'data');
      expect(view.getUint32(40, Endian.little), dataBytes);
      expect(view.getUint32(4, Endian.little), dataBytes + 36);
    });
  });

  group('ensureWaveHeader', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('cra-wav-');
    });

    tearDown(() async {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    test('wraps raw PCM the plugin wrote without a container', () async {
      final raw = File('${dir.path}/grab.wav');
      final pcm = Uint8List.fromList(List<int>.generate(640, (i) => i % 256));
      await raw.writeAsBytes(pcm);

      final decoded = await ensureWaveHeader(raw.path);
      expect(decoded, '${raw.path}.wav');

      final wrapped = File(decoded);
      final bytes = await wrapped.readAsBytes();
      expect(RecordingFormat.hasWaveHeader(bytes), isTrue);
      expect(bytes.length, 44 + pcm.length);
      // The payload must survive untouched.
      expect(bytes.sublist(44), pcm);
      final view = ByteData.sublistView(bytes);
      expect(view.getUint32(40, Endian.little), pcm.length);
    });

    test('leaves an already valid WAV untouched', () async {
      final file = File('${dir.path}/valid.wav');
      final header = RecordingFormat.header(320);
      await file.writeAsBytes(<int>[...header, ...List<int>.filled(320, 7)]);

      expect(await ensureWaveHeader(file.path), file.path);
      expect(await file.length(), 44 + 320);
      expect(File('${file.path}.wav').existsSync(), isFalse);
    });

    test('fails clearly on a missing capture', () async {
      await expectLater(
        ensureWaveHeader('${dir.path}/nope.wav'),
        throwsFormatException,
      );
    });

    test(
      'fails clearly on a truncated capture instead of decoding silence',
      () async {
        final empty = File('${dir.path}/empty.wav');
        await empty.writeAsBytes(<int>[]);
        await expectLater(ensureWaveHeader(empty.path), throwsFormatException);
      },
    );
  });
}
