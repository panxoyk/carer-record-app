import 'dart:io';
import 'dart:typed_data';

/// Recording contract shared by capture and decoding.
///
/// The recorder captures raw PCM16 mono at 16 kHz, which is exactly what the
/// local recognizer expects. Some Android devices and the `record` plugin build
/// do not write a WAV container at all, so the header is rebuilt here instead of
/// assuming the file is already valid.
class RecordingFormat {
  const RecordingFormat._();

  static const int sampleRate = 16000;
  static const int channels = 1;
  static const int bitsPerSample = 16;

  static const int bytesPerSample = bitsPerSample ~/ 8;
  static const int headerBytes = 44;

  /// Bytes per second of captured audio.
  static int get byteRate => sampleRate * channels * bytesPerSample;

  /// A plausible WAV always starts with the ASCII `RIFF`.
  static bool hasWaveHeader(List<int> head) {
    if (head.length < 4) return false;
    return head[0] == 0x52 &&
        head[1] == 0x49 &&
        head[2] == 0x46 &&
        head[3] == 0x46;
  }

  /// Builds a canonical 44-byte RIFF/WAVE header for [dataBytes] of PCM.
  static Uint8List header(int dataBytes) {
    final bytes = ByteData(headerBytes);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        bytes.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    final byteRate = RecordingFormat.byteRate;
    final blockAlign = channels * bytesPerSample;

    ascii(0, 'RIFF');
    bytes.setUint32(4, dataBytes + headerBytes - 8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little); // PCM chunk size
    bytes.setUint16(20, 1, Endian.little); // PCM format
    bytes.setUint16(22, channels, Endian.little);
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, byteRate, Endian.little);
    bytes.setUint16(32, blockAlign, Endian.little);
    bytes.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataBytes, Endian.little);

    return bytes.buffer.asUint8List();
  }
}

/// Ensures the recording on disk is a WAV container the recognizer can read.
///
/// Returns the path to decode. When the capture already wrote a valid header
/// the original file is used untouched; otherwise a sibling file with the
/// header is written and returned, and the original is left in place for the
/// purge to remove with its directory.
///
/// Throws [FormatException] when the file is missing or empty, so a truncated
/// capture fails as a recoverable error instead of decoding silence.
Future<String> ensureWaveHeader(String path) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw FormatException('La grabación local no existe: $path');
  }
  final length = await file.length();
  if (length == 0) {
    throw const FormatException('La grabación local está vacía.');
  }

  final head = await _readHead(file, 4);
  if (RecordingFormat.hasWaveHeader(head)) return path;

  final pcm = await file.readAsBytes();
  final sink = File('$path.wav').openWrite();
  try {
    sink.add(RecordingFormat.header(pcm.length));
    sink.add(pcm);
  } finally {
    await sink.close();
  }
  return '$path.wav';
}

Future<List<int>> _readHead(File file, int count) async {
  final handle = await file.open();
  try {
    final bytes = await handle.read(count);
    return bytes;
  } finally {
    await handle.close();
  }
}
