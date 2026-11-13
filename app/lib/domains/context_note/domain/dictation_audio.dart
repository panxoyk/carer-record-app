abstract interface class DictationAudio {
  Future<bool> requestPermission();
  Future<String> prepareSandboxPath(String operationId);
  Future<void> startPcm16(String path);
  Future<String?> stop();
  Future<String> prepareWav(String path);
  Future<bool> togglePreview(String path);
  Future<void> stopPreview();
  Future<void> dispose();
}

abstract interface class DictationArtifacts {
  Future<void> registerCapture(String operationId, String recordingPath);
  Future<void> putDraft(
    String operationId, {
    required String transcription,
    required String recordingPath,
  });
  Future<void> purge(String operationId, {String? recordingPath});
}

/// Optional capabilities of a recorder used by the Figma recording screen:
/// pause/resume and a normalized input level (0..1) for the waveform.
abstract interface class PausableDictationAudio {
  Future<void> pause();
  Future<void> resume();
  Stream<double> levels();
}
