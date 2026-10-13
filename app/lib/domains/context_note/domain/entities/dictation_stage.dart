/// Local dictation lifecycle of a bitácora milestone, as defined in
/// `docs/foundation/flows/audio-note.md`. The audio and the raw transcription
/// never leave the device (ADR-016): a milestone only becomes a row once its
/// author confirms it in [readyToConfirm].
enum DictationStage {
  /// Nothing captured yet.
  idle,

  /// Microphone capture is running inside the app sandbox.
  recording,

  /// The local ASR engine is decoding the recording.
  transcribingLocal,

  /// The transcription is an editable draft waiting for its author.
  readyToConfirm,

  /// The confirmed note is being written; RLS is the authority.
  publishing,

  /// The note exists server-side and every temporary artifact is gone.
  published,

  /// Recoverable error; the author can retry or switch to a text milestone.
  failed,

  /// The author dropped the draft; nothing is published.
  discarded;

  /// Stages where a temporary artifact exists on the device.
  bool get holdsTemporaryArtifacts =>
      this == recording ||
      this == transcribingLocal ||
      this == readyToConfirm ||
      this == publishing ||
      this == failed;

  /// True once the flow can no longer produce a note without new input.
  bool get isTerminal => this == published || this == discarded;
}
