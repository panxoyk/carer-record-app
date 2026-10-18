import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../domain/entities/context_note.dart';
import '../../domain/confirmed_milestone_writer.dart';

/// Immutable snapshot of an ambiguous publication. Its identifier and metadata
/// must not change while the same confirmation is being retried.
class MilestonePublicationSnapshot {
  MilestonePublicationSnapshot(ContextNoteMilestone milestone)
    : milestone = _freezeMilestone(milestone);

  final ContextNoteMilestone milestone;
}

/// Coordinates the publication boundary for a milestone editor.
///
/// The controller deliberately knows nothing about widgets, patients, plugins,
/// or the repository implementation. The caller supplies episode identifiers,
/// identity and IDs at the feature boundary.
class MilestoneEditorController extends ChangeNotifier {
  MilestoneEditorController({
    required this.writer,
    required this.organizationId,
    required this.hospitalizationId,
    required this.patientId,
    required this.readAccountId,
    required this.newEventId,
  });

  final ConfirmedMilestoneWriter writer;
  final String organizationId;
  final String hospitalizationId;
  final String patientId;
  final String? Function() readAccountId;
  final String Function() newEventId;

  MilestonePublicationSnapshot? _pending;
  String? _pendingAccountId;
  bool _busy = false;
  bool _closed = false;
  bool _published = false;

  bool get busy => _busy;
  bool get isPublicationLocked => _pending != null;
  bool get isClosed => _closed;
  MilestonePublicationSnapshot? get pendingPublication => _pending;
  bool get accountChanged =>
      _pending != null && readAccountId() != _pendingAccountId;

  /// Returns false for invalid input or a duplicate concurrent invocation.
  /// On writer failure the exact same frozen payload is retained for retry.
  Future<bool> publish({
    required String content,
    required MilestoneInputMethod inputMethod,
    TranscriptionMetadata? transcription,
  }) async {
    if (_closed || _busy || _published) return false;
    final trimmed = content.trim();
    if (trimmed.isEmpty ||
        trimmed.length > maxMilestoneTextLength ||
        (inputMethod == MilestoneInputMethod.text && transcription != null) ||
        (inputMethod == MilestoneInputMethod.audio && transcription == null)) {
      return false;
    }
    final accountId = readAccountId();
    if (_pending != null && accountId != _pendingAccountId) return false;
    _pending ??= MilestonePublicationSnapshot(
      ContextNoteMilestone(
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
        patientId: patientId,
        inputMethod: inputMethod,
        content: trimmed,
        transcription: transcription,
        clientEventId: newEventId(),
      ),
    );
    _pendingAccountId ??= accountId;
    _busy = true;
    _notify();
    try {
      await writer.saveMilestone(_pending!.milestone);
      if (_closed || readAccountId() != _pendingAccountId) return false;
      _published = true;
      _pending = null;
      _pendingAccountId = null;
      return true;
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Discards retry state. This does not report or publish success.
  void discardPendingPublication() {
    if (_busy || _closed) return;
    _pending = null;
    _pendingAccountId = null;
    _notify();
  }

  /// Closes the controller and prevents late async completions from notifying.
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }

  void _notify() {
    if (!_closed) notifyListeners();
  }
}

ContextNoteMilestone _freezeMilestone(ContextNoteMilestone source) {
  final metadata = source.transcription;
  final frozenMetadata = metadata == null
      ? null
      : TranscriptionMetadata(
          engine: metadata.engine,
          pipelineVersion: metadata.pipelineVersion,
          model: metadata.model,
          modelVersion: metadata.modelVersion,
          modelChecksum: metadata.modelChecksum,
          durationMs: metadata.durationMs,
          meanConfidence: metadata.meanConfidence,
          parameters: _freezeMap(metadata.parameters),
          lowConfidenceSegments: List<LowConfidenceSegment>.unmodifiable(
            metadata.lowConfidenceSegments,
          ),
        );
  return ContextNoteMilestone(
    organizationId: source.organizationId,
    hospitalizationId: source.hospitalizationId,
    patientId: source.patientId,
    inputMethod: source.inputMethod,
    content: source.content,
    transcription: frozenMetadata,
    clientEventId: source.clientEventId,
  );
}

Map<String, Object?> _freezeMap(Map<String, Object?> source) =>
    UnmodifiableMapView<String, Object?>(
      source.map((key, value) => MapEntry(key, _freezeValue(value))),
    );

Object? _freezeValue(Object? value) {
  if (value is Map) {
    return UnmodifiableMapView<Object?, Object?>(
      value.map((key, item) => MapEntry(key, _freezeValue(item))),
    );
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freezeValue));
  if (value is Set) return Set.unmodifiable(value.map(_freezeValue));
  return value;
}
