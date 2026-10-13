import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../patient/domain/entities/patient.dart';
import '../data/draft_vault.dart';
import '../data/wav_container.dart';
import '../domain/asr_engine.dart';
import '../domain/entities/context_note.dart';
import '../domain/entities/dictation_stage.dart';
import '../domain/synthesis_provider.dart';
import '../domain/usecases/synthesis_usecases.dart';
import 'context_note_providers.dart';

/// Bottom sheet to add a bitácora milestone as text or as a locally dictated
/// note.
///
/// The audio branch follows ADR-016: record, transcribe on the device, let the
/// author listen and correct the draft, and only then persist the text the
/// author confirmed. The recording and the raw transcription are deleted on
/// every exit path, and nothing about them ever leaves the device.
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
  DictationSession _session = const DictationSession();
  Timer? _ticker;
  AudioRecorder? _recorder;
  AudioPlayer? _previewPlayer;
  String? _operationId;
  bool _busy = false;
  bool _assisting = false;
  String? _assistNote;

  @override
  void dispose() {
    _ticker?.cancel();
    _textController.dispose();
    _previewPlayer?.dispose();
    _recorder?.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _patch(DictationSession next) {
    if (mounted) setState(() => _session = next);
  }

  // -- capture ------------------------------------------------------------

  Future<void> _toggleRecording() async {
    if (_session.stage == DictationStage.recording) {
      await _stopRecording();
      return;
    }
    final engine = await ref.read(asrEngineProvider.future);
    if (engine == null) {
      _showError(
        'El ASR local no está disponible en este dispositivo. '
        'Escribe el hito en texto.',
      );
      return;
    }
    final recorder = AudioRecorder();
    _recorder = recorder;
    if (!await recorder.hasPermission()) {
      await recorder.dispose();
      _recorder = null;
      _showError('El micrófono está bloqueado. Revisa el permiso del sistema.');
      return;
    }
    try {
      final operationId = _uuid.v4();
      final root = (await getTemporaryDirectory()).path;
      final directory = DraftVault.recordingDirectory(root, operationId);
      await directory.create(recursive: true);
      final path =
          '${directory.path}${Platform.pathSeparator}'
          '${DraftVault.recordingFileName(operationId)}';
      // PCM16 with headers: sherpa-onnx decodes this container directly, so no
      // lossy re-encode sits between the microphone and the recognizer.
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: RecordingFormat.sampleRate,
          numChannels: RecordingFormat.channels,
        ),
        path: path,
      );
      _operationId = operationId;
      _patch(
        _session.copyWith(
          stage: DictationStage.recording,
          recordingPath: path,
          transcript: null,
          draftText: '',
          clearError: true,
        ),
      );
      _textController.clear();
      _startTicker();
    } catch (_) {
      await recorder.dispose();
      _recorder = null;
      _showError('No se pudo iniciar la grabación de audio.');
    }
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  Future<void> _stopRecording() async {
    _ticker?.cancel();
    final recorder = _recorder;
    var path = _session.recordingPath;
    if (recorder != null) {
      try {
        final stopped = await recorder.stop();
        if (stopped != null && stopped.isNotEmpty) path = stopped;
      } finally {
        await recorder.dispose();
        _recorder = null;
      }
    }
    if (path == null) {
      _patch(_session.copyWith(stage: DictationStage.idle));
      return;
    }
    _patch(_session.copyWith(stage: DictationStage.transcribingLocal));
    setState(() => _busy = true);
    final engine = await ref.read(asrEngineProvider.future);
    if (engine == null) {
      setState(() => _busy = false);
      _patch(
        _session.copyWith(
          stage: DictationStage.failed,
          error: 'El ASR local no está disponible.',
        ),
      );
      _showError('No se pudo transcribir localmente. Intenta de nuevo.');
      return;
    }
    try {
      // Capture can be raw PCM without a container; the recognizer needs WAV.
      final wavePath = await ensureWaveHeader(path);
      final transcript = await engine.transcribe(wavePath);
      await ref
          .read(draftVaultProvider)
          .putDraft(
            _operationId ?? '',
            transcription: transcript.text,
            recordingPath: path,
          );
      _patch(
        _session.copyWith(
          stage: DictationStage.readyToConfirm,
          transcript: transcript,
          draftText: transcript.text,
          clearError: true,
        ),
      );
      _textController.text = transcript.text;
      if (transcript.isEmpty) {
        _showError(
          'La transcripción local quedó vacía. Vuelve a grabar o escribe el hito.',
        );
      }
    } on AsrUnavailableException catch (error) {
      _patch(
        _session.copyWith(stage: DictationStage.failed, error: error.reason),
      );
      _showError(error.reason);
    } on AsrTranscriptionException catch (error) {
      _patch(
        _session.copyWith(stage: DictationStage.failed, error: error.reason),
      );
      _showError(error.reason);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- review -------------------------------------------------------------

  Future<void> _previewRecording() async {
    final path = _session.recordingPath;
    if (path == null) return;
    final player = _previewPlayer ??= AudioPlayer();
    try {
      if (player.playing) {
        await player.pause();
        return;
      }
      if (player.duration == null) await player.setFilePath(path);
      await player.play();
    } catch (_) {
      _showError('No se pudo reproducir la grabación.');
    }
  }

  Future<void> _discardArtifacts() async {
    final operationId = _operationId;
    _ticker?.cancel();
    await _previewPlayer?.stop();
    _patch(
      _session.copyWith(
        stage: DictationStage.discarded,
        recordingPath: null,
        transcript: null,
        draftText: null,
        clearError: true,
      ),
    );
    _textController.clear();
    if (operationId == null) return;
    // Purge is idempotent, so it is safe to call again from dispose-like paths.
    await ref
        .read(draftVaultProvider)
        .purge(operationId, recordingPath: _session.recordingPath);
    _operationId = null;
  }

  Future<void> _cancel() async {
    await _discardArtifacts();
    if (mounted) Navigator.of(context).pop();
  }

  // -- publish ------------------------------------------------------------

  Future<void> _save() async {
    final patient = widget.patient;
    final content = _textController.text.trim();
    if (content.isEmpty) {
      _showError('Escribe el texto del hito antes de guardarlo.');
      return;
    }
    final isAudio = _mode == MilestoneInputMethod.audio;
    if (isAudio && _session.transcript == null) {
      _showError(
        'Graba y transcribe el hito antes de guardarlo, o usa el modo texto.',
      );
      return;
    }
    setState(() => _busy = true);
    _patch(_session.copyWith(stage: DictationStage.publishing));
    final milestone = ContextNoteMilestone(
      organizationId: patient.organizationId,
      hospitalizationId: patient.hospitalizationId,
      patientId: patient.patientId,
      inputMethod: _mode,
      content: content,
      transcription: _session.transcript?.metadata,
      clientEventId: _uuid.v4(),
    );
    try {
      await ref.read(contextNoteRepositoryProvider).saveMilestone(milestone);
      _patch(_session.copyWith(stage: DictationStage.published));
      await _discardArtifacts();
      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (error) {
      _patch(
        _session.copyWith(
          stage: DictationStage.failed,
          error: 'No se pudo guardar el hito.',
        ),
      );
      _showError('No se pudo guardar el hito: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // -- view ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(asrEngineProvider);
    final asrReady = engineState.valueOrNull != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: SingleChildScrollView(
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
              segments: [
                const ButtonSegment(
                  value: MilestoneInputMethod.text,
                  label: Text('Texto'),
                  icon: Icon(Icons.subject_outlined),
                ),
                ButtonSegment(
                  value: MilestoneInputMethod.audio,
                  label: const Text('Dictado'),
                  icon: Icon(
                    asrReady ? Icons.mic_none : Icons.mic_off_outlined,
                  ),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (selection) => setState(() => _mode = selection.first),
            ),
            const SizedBox(height: 8),
            Text(
              asrReady
                  ? 'La transcripción ocurre en este dispositivo y el audio no '
                        'sale del teléfono.'
                  : 'El reconocimiento de voz local no está disponible; '
                        'el hito de texto sigue funcionando.',
              style: Theme.of(context).textTheme.bodySmall,
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
              _buildDictationSection(),
            const SizedBox(height: 12),
            _buildAssistRow(),
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
                    onPressed:
                        _busy ||
                            (_mode == MilestoneInputMethod.text &&
                                _textController.text.trim().isEmpty)
                        ? null
                        : _save,
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Confirmar hito'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssistRow() {
    final provider = ref.watch(synthesisProviderProvider).valueOrNull;
    final hasDraft = _textController.text.trim().isNotEmpty;
    if (provider == null) {
      return Row(
        children: [
          const Icon(Icons.offline_bolt_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'La mejora de texto no está disponible: el modelo local no está '
              'instalado. El hito se publica tal como lo escribiste.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        OutlinedButton.icon(
          onPressed: _busy || !hasDraft ? null : _improveDraft,
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('Mejorar redacción'),
        ),
        const SizedBox(width: 12),
        if (_assisting)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (_assistNote != null)
          Expanded(
            child: Text(
              _assistNote!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Future<void> _improveDraft() async {
    final provider = await ref.read(synthesisProviderProvider.future);
    if (provider == null) {
      setState(() => _assistNote = 'El modelo local no está instalado.');
      return;
    }
    setState(() {
      _assisting = true;
      _assistNote = null;
    });
    final outcome = await ImproveNoteDraft(provider: provider)(
      text: _textController.text,
      idempotencyKey: _operationId,
    );
    if (!mounted) return;
    setState(() => _assisting = false);
    if (!outcome.hasSuggestion) {
      setState(() => _assistNote = _assistMessageFor(outcome.errorCode));
      return;
    }
    // The suggestion is a draft: the author keeps editing before confirming.
    _textController.text = outcome.suggestion!;
    setState(() => _assistNote = 'Revisa la sugerencia antes de confirmar.');
  }

  String _assistMessageFor(String? code) {
    return switch (code) {
      SynthesisErrorCode.unavailable => 'El modelo local no está disponible.',
      SynthesisErrorCode.timeout => 'La mejora local tardó demasiado.',
      SynthesisErrorCode.tooLong => 'La sugerencia era demasiado larga.',
      SynthesisErrorCode.cancelled => 'Mejora cancelada.',
      SynthesisErrorCode.malformed => 'La mejora local no se pudo interpretar.',
      SynthesisErrorCode.internal => 'La mejora local falló.',
      _ => 'Sin mejora local; se conserva tu texto.',
    };
  }

  Widget _buildDictationSection() {
    final stage = _session.stage;
    final transcript = _session.transcript;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              onPressed: _busy || stage == DictationStage.transcribingLocal
                  ? null
                  : _toggleRecording,
              tooltip: stage == DictationStage.recording
                  ? 'Detener grabación'
                  : 'Grabar dictado',
              icon: Icon(
                stage == DictationStage.recording ? Icons.stop : Icons.mic_none,
              ),
            ),
            const SizedBox(width: 12),
            if (stage == DictationStage.recording)
              const Text('Grabando localmente…')
            else if (stage == DictationStage.transcribingLocal)
              const Text('Transcribiendo en el dispositivo…')
            else if (stage == DictationStage.readyToConfirm)
              const Text('Revisa la transcripción antes de confirmar.')
            else
              const Text('Graba el hito con voz.'),
          ],
        ),
        if (_session.canListen)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _busy ? null : _previewRecording,
                icon: const Icon(Icons.play_arrow),
              ),
              const Text('Escuchar la grabación local'),
            ],
          ),
        if (transcript != null) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _textController,
            maxLines: 4,
            decoration: InputDecoration(
              labelText: 'Texto del hito (editable)',
              helperText: transcript.hasUncertainSegments
                  ? 'Revisa los tramos marcados: la confianza local fue baja.'
                  : 'Corrige lo que el reconocimiento local no entendió.',
              border: const OutlineInputBorder(),
            ),
            onChanged: (value) => _patch(
              _session.copyWith(
                draftText: value,
                stage: DictationStage.readyToConfirm,
              ),
            ),
          ),
          const SizedBox(height: 8),
          _ProvenanceChip(metadata: transcript.metadata),
        ],
      ],
    );
  }
}

class _ProvenanceChip extends StatelessWidget {
  const _ProvenanceChip({required this.metadata});

  final TranscriptionMetadata metadata;

  @override
  Widget build(BuildContext context) {
    final engine = metadata.engine;
    final model = metadata.model;
    final label = model == null || model.isEmpty
        ? 'Transcrito localmente con $engine'
        : 'Transcrito localmente · $engine · $model';
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(label, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
