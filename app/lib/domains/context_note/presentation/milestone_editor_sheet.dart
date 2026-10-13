import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../patient/domain/entities/patient.dart';
import '../domain/entities/context_note.dart';
import 'context_note_providers.dart';

/// Bottom sheet to add a bitácora milestone as text or stored audio.
/// Saving the sheet is the author's confirmation; RLS remains the
/// authorization authority on the server.
Future<void> showMilestoneEditorSheet(
  BuildContext context, {
  required Patient patient,
  required VoidCallback onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _MilestoneEditorSheet(patient: patient, onSaved: onSaved),
  );
}

class _MilestoneEditorSheet extends ConsumerStatefulWidget {
  const _MilestoneEditorSheet({required this.patient, required this.onSaved});

  final Patient patient;
  final VoidCallback onSaved;

  @override
  ConsumerState<_MilestoneEditorSheet> createState() =>
      _MilestoneEditorSheetState();
}

class _MilestoneEditorSheetState extends ConsumerState<_MilestoneEditorSheet> {
  static const _uuid = Uuid();

  MilestoneInputMethod _mode = MilestoneInputMethod.text;
  final TextEditingController _textController = TextEditingController();
  String? _recordingPath;
  Duration _elapsed = Duration.zero;
  Timer? _ticker;
  AudioRecorder? _recorder;
  AudioPlayer? _previewPlayer;
  bool _recording = false;
  bool _busy = false;

  @override
  void dispose() {
    _ticker?.cancel();
    _textController.dispose();
    _previewPlayer?.dispose();
    _recorder?.dispose();
    final path = _recordingPath;
    if (path != null) File(path).delete().ignore();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    final recorder = AudioRecorder();
    _recorder = recorder;
    final allowed = await recorder.hasPermission();
    if (!allowed) {
      await recorder.dispose();
      _recorder = null;
      _showError('El micrófono está bloqueado. Revisa el permiso del sistema.');
      return;
    }
    try {
      final directory = await Directory.systemTemp.createTemp('cra_milestone_');
      final path = '${directory.path}/${_uuid.v4()}.m4a';
      await recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recordingPath = path;
      _recording = true;
      _elapsed = Duration.zero;
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed += const Duration(seconds: 1));
      });
      setState(() {});
    } catch (_) {
      await recorder.dispose();
      _recorder = null;
      _showError('No se pudo iniciar la grabación de audio.');
    }
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    final recorder = _recorder;
    if (recorder != null) {
      try {
        final path = await recorder.stop();
        if (path != null && path.isNotEmpty) _recordingPath = path;
      } finally {
        await recorder.dispose();
        _recorder = null;
      }
    }
    setState(() => _recording = false);
    final path = _recordingPath;
    if (path != null) {
      final player = AudioPlayer();
      _previewPlayer?.dispose();
      _previewPlayer = player;
      try {
        await player.setFilePath(path);
        _elapsed = player.duration ?? _elapsed;
      } catch (_) {
        // Duration is cosmetic; the raw length is kept as fallback.
      }
      setState(() {});
    }
  }

  Future<void> _previewRecording() async {
    final player = _previewPlayer ??= AudioPlayer();
    try {
      if (player.playing) {
        await player.pause();
      } else {
        if (player.duration == null && _recordingPath != null) {
          await player.setFilePath(_recordingPath!);
        }
        await player.play();
      }
      setState(() {});
    } catch (_) {
      _showError('No se pudo reproducir la grabación.');
    }
  }

  Future<void> _cancel() async {
    _cleanupLocalAudio();
    if (mounted) Navigator.of(context).pop();
  }

  void _cleanupLocalAudio() {
    _ticker?.cancel();
    _recording = false;
    _elapsed = Duration.zero;
    final path = _recordingPath;
    _recordingPath = null;
    if (path != null) File(path).delete().ignore();
  }

  Future<void> _save() async {
    final patient = widget.patient;
    final content = _textController.text.trim();
    if (_mode == MilestoneInputMethod.text && content.isEmpty) {
      _showError('Escribe el texto del hito antes de guardarlo.');
      return;
    }
    if (_mode == MilestoneInputMethod.audio && _recordingPath == null) {
      _showError('Graba el audio del hito antes de guardarlo.');
      return;
    }
    setState(() => _busy = true);
    final clientEventId = _uuid.v4();
    final milestone = ContextNoteMilestone(
      organizationId: patient.organizationId,
      hospitalizationId: patient.hospitalizationId,
      patientId: patient.patientId,
      inputMethod: _mode,
      content: _mode == MilestoneInputMethod.text ? content : null,
      audioStoragePath:
          _mode == MilestoneInputMethod.audio
              ? '${patient.hospitalizationId}/$clientEventId.m4a'
              : null,
      audioDurationMs:
          _mode == MilestoneInputMethod.audio ? _elapsed.inMilliseconds : null,
      clientEventId: clientEventId,
    );
    try {
      await ref
          .read(contextNoteRepositoryProvider)
          .saveMilestone(
            milestone,
            audioFile:
                _mode == MilestoneInputMethod.audio
                    ? File(_recordingPath!)
                    : null,
          );
      _cleanupLocalAudio();
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (error) {
      _showError('No se pudo guardar el hito: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Agregar hito a la bitácora',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          SegmentedButton<MilestoneInputMethod>(
            segments: const [
              ButtonSegment(
                value: MilestoneInputMethod.text,
                label: Text('Texto'),
                icon: Icon(Icons.subject_outlined),
              ),
              ButtonSegment(
                value: MilestoneInputMethod.audio,
                label: Text('Audio'),
                icon: Icon(Icons.mic_none),
              ),
            ],
            selected: {_mode},
            onSelectionChanged:
                (selection) => setState(() => _mode = selection.first),
          ),
          const SizedBox(height: 16),
          if (_mode == MilestoneInputMethod.text)
            TextField(
              controller: _textController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Describe el hito (síntesis clínica breve).',
                border: OutlineInputBorder(),
              ),
            )
          else
            _buildAudioSection(),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Descartar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : _save,
                  child:
                      _busy
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : const Text('Guardar hito'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAudioSection() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formatDuration(_elapsed),
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: _busy ? null : _toggleRecording,
              tooltip: _recording ? 'Detener grabación' : 'Grabar audio',
              icon: Icon(_recording ? Icons.stop : Icons.mic_none),
            ),
          ],
        ),
        if (_recordingPath != null && !_recording)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _busy ? null : _previewRecording,
                icon: const Icon(Icons.play_arrow),
              ),
              const Text('Preescuchar grabación'),
            ],
          ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}
