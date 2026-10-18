import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../core/design_system/clinical_toast.dart';
import '../../../core/design_system/clinical_design_system.dart';
import '../../auth/presentation/auth_providers.dart';

import '../../patient/domain/entities/patient.dart';
import '../domain/entities/context_note.dart';
import '../domain/confirmed_milestone_writer.dart';
import 'controllers/milestone_editor_controller.dart';
import 'controllers/dictation_controller.dart';
import '../domain/entities/dictation_stage.dart';
import '../../on_device_ai/domain/synthesis_provider.dart';
import '../../on_device_ai/domain/local_capability_repository.dart';
import '../../on_device_ai/domain/local_capability_usage.dart';
import '../../on_device_ai/presentation/local_ai_providers.dart';
import '../domain/usecases/synthesis_usecases.dart';
import 'controllers/note_assistance_controller.dart';
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
  required ValueChanged<bool> onSaved,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(
        top: Radius.circular(ClinicalRadii.card),
      ),
    ),
    builder: (_) => _MilestoneEditorSheet(patient: patient, onSaved: onSaved),
  );
}

class _MilestoneEditorSheet extends ConsumerStatefulWidget {
  const _MilestoneEditorSheet({required this.patient, required this.onSaved});

  final Patient patient;
  final ValueChanged<bool> onSaved;

  @override
  ConsumerState<_MilestoneEditorSheet> createState() =>
      _MilestoneEditorSheetState();
}

class _MilestoneEditorSheetState extends ConsumerState<_MilestoneEditorSheet> {
  static const _uuid = Uuid();

  MilestoneInputMethod _mode = MilestoneInputMethod.audio;
  final TextEditingController _textController = TextEditingController();
  late final DictationController _dictation;
  DictationSession get _session => _dictation.session;
  String? get _operationId => _dictation.operationId;
  bool _busy = false;
  String? _formError;
  bool get _isBusy => _busy || _dictation.busy;
  late final NoteAssistanceController _assistance;
  String? _assistNote;
  LocalCapabilityUsageLease? _usageLease;
  late final MilestoneEditorController _publication;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onTextChanged);
    _assistance = NoteAssistanceController(
      load: () async {
        final provider = await ref.read(synthesisProviderProvider.future);
        return provider == null ? null : ImproveNoteDraft(provider: provider);
      },
    )..addListener(_onAssistanceChanged);
    _dictation = DictationController(
      audioFactory: ref.read(dictationAudioFactoryProvider),
      artifactsFactory: () => ref.read(draftVaultProvider),
      loadEngine: () => ref.read(asrEngineProvider.future),
      newId: _uuid.v4,
    )..addListener(_onDictationChanged);
    _usageLease = ref
        .read(localCapabilityUsageProvider)
        .acquire(LocalCapability.values);
    final patient = widget.patient;
    _publication = MilestoneEditorController(
      writer: _DeferredMilestoneWriter(
        (milestone) =>
            ref.read(contextNoteRepositoryProvider).saveMilestone(milestone),
      ),
      organizationId: patient.organizationId,
      hospitalizationId: patient.hospitalizationId,
      patientId: patient.patientId,
      readAccountId: () => ref.read(sessionProvider)?.user.id,
      newEventId: _uuid.v4,
    )..addListener(_onPublicationChanged);
  }

  void _onTextChanged() {
    _assistance.invalidate();
    if (mounted) setState(() {});
  }

  void _onAssistanceChanged() {
    if (mounted) setState(() {});
  }

  void _onPublicationChanged() {
    if (!mounted) return;
    setState(() {
      if (!_publication.busy && _publication.isPublicationLocked) {
        _formError = 'No pudimos confirmar el guardado. Puedes reintentar la misma nota.';
      }
    });
  }

  @override
  void dispose() {
    _usageLease?.release();
    _dictation.removeListener(_onDictationChanged);
    _dictation.dispose();
    _textController.removeListener(_onTextChanged);
    _publication.removeListener(_onPublicationChanged);
    _publication.dispose();
    _assistance.removeListener(_onAssistanceChanged);
    _assistance.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _showOperationError(String detail, {required String toastMessage}) {
    if (!mounted) return;
    setState(() => _formError = detail);
    ClinicalToast.failure(context, message: toastMessage);
  }

  void _patch(DictationSession next) {
    _dictation.updateDraft(next.draftText ?? '');
  }

  void _onDictationChanged() {
    if (!mounted) return;
    setState(() {});
    final transcript = _session.transcript;
    if (transcript != null &&
        !identical(transcript, _lastAppliedTranscriptObject)) {
      _lastAppliedTranscriptObject = transcript;
      _textController.text = transcript.text;
    }
    if (_session.error != null) {
      _showOperationError(
        _session.error!,
        toastMessage: 'No se pudo procesar el dictado.',
      );
    }
  }

  AsrTranscript? _lastAppliedTranscriptObject;

  Future<void> _toggleRecording() async {
    final recording = _session.stage == DictationStage.recording;
    if (_publication.isPublicationLocked) return;
    if (!recording) {
      _lastAppliedTranscriptObject = null;
    }
    await _dictation.toggleRecording();
    if (!recording && _session.stage == DictationStage.recording) {
      _textController.clear();
    }
  }

  Future<void> _previewRecording() async {
    if (!await _dictation.preview()) {
      _showOperationError(
        'No se pudo reproducir la grabación.',
        toastMessage: 'No se pudo reproducir el dictado.',
      );
    }
  }

  Future<bool> _discardArtifacts({bool notifyFailure = true}) async {
    final success = await _dictation.discard(notifyFailure: notifyFailure);
    if (success) {
      _lastAppliedTranscriptObject = null;
      _textController.clear();
    }
    return success;
  }

  Future<void> _cancel() async {
    _assistance.invalidate();
    if (!await _discardArtifacts(notifyFailure: false)) {
      _showOperationError(
        'No se pudo descartar la nota. Vuelve a intentarlo.',
        toastMessage: 'No se pudo descartar la nota.',
      );
      return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  // -- publish ------------------------------------------------------------

  Future<void> _save() async {
    _assistance.invalidate();
    if (_isBusy || _publication.busy) return;
    if (_publication.accountChanged) {
      _showOperationError(
        'La sesión cambió. Descarta este borrador e inicia uno nuevo.',
        toastMessage: 'No se pudo continuar con este borrador.',
      );
      return;
    }
    final pending = _publication.pendingPublication?.milestone;
    final content = pending?.content ?? _textController.text.trim();
    if (content.isEmpty || content.length > maxMilestoneTextLength) {
      _showOperationError(
        'La nota debe tener entre 1 y 20000 caracteres.',
        toastMessage: 'No se pudo validar la nota.',
      );
      return;
    }
    final isAudio = _mode == MilestoneInputMethod.audio;
    if (isAudio && _session.transcript == null) {
      _showOperationError(
        'Confirma una transcripción o vuelve a grabar.',
        toastMessage: 'No se pudo confirmar el guardado.',
      );
      return;
    }
    if (isAudio && content.isEmpty) {
      _showOperationError(
        'La transcripción está vacía. Escribe la nota o vuelve a grabar.',
        toastMessage: 'No se pudo confirmar el guardado.',
      );
      return;
    }
    setState(() => _busy = true);
    setState(() => _formError = null);

    try {
      final saved = await _publication.publish(
        content: content,
        inputMethod: pending?.inputMethod ?? _mode,
        transcription:
            pending?.transcription ??
            (isAudio ? _session.transcript?.metadata : null),
      );
      if (!saved) {
        if (_publication.isPublicationLocked) {
          _formError = 'No pudimos confirmar el guardado. Puedes reintentar la misma nota.';
        }
        if (_publication.accountChanged) {
          _showOperationError(
            'La sesión cambió. Descarta este borrador e inicia uno nuevo.',
            toastMessage: 'No se pudo continuar con este borrador.',
          );
        }
        if (mounted) setState(() => _busy = false);
        return;
      }
    } catch (error) {
      _showOperationError(
        'No pudimos confirmar el guardado. Puedes reintentar la misma nota.',
        toastMessage: 'No se pudo confirmar el guardado.',
      );
      if (mounted) setState(() => _busy = false);
      return;
    }
    // Persistence has succeeded. Cleanup is a separate best-effort step: never
    // leave the editor open where a fresh clientEventId could publish twice.
    var cleanupPending = false;
    try {
      cleanupPending = !await _discardArtifacts(notifyFailure: false);
    } catch (_) {
      cleanupPending = true;
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onSaved(cleanupPending);
  }

  // -- view ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(asrEngineProvider);
    final asrReady = engineState.valueOrNull != null;
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(ClinicalRadii.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ClinicalSpacing.page,
          ClinicalSpacing.card,
          ClinicalSpacing.page,
          ClinicalSpacing.card + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Nueva nota de contexto', style: theme.textTheme.titleLarge),
              const SizedBox(height: ClinicalSpacing.compact),
              SegmentedButton<MilestoneInputMethod>(
                segments: [
                  ButtonSegment(
                    value: MilestoneInputMethod.audio,
                    label: const Text('Dictado'),
                    icon: Icon(
                      asrReady ? Icons.mic_none : Icons.mic_off_outlined,
                    ),
                  ),
                  const ButtonSegment(
                    value: MilestoneInputMethod.text,
                    label: Text('Texto'),
                    icon: Icon(Icons.subject_outlined),
                  ),
                ],
                selected: {_mode},
                onSelectionChanged: _isBusy || _publication.isPublicationLocked
                    ? null
                    : (selection) => setState(() => _mode = selection.first),
              ),
              const SizedBox(height: ClinicalSpacing.compact),
              if (_mode == MilestoneInputMethod.text)
                TextField(
                  controller: _textController,
                  readOnly: _isBusy || _publication.isPublicationLocked,
                  maxLines: 5,
                  decoration: clinicalInputDecoration(
                    labelText: 'Nota',
                    hintText: 'Describe brevemente el contexto clínico.',
                  ),
                )
              else
                _buildDictationSection(),
              if (_mode == MilestoneInputMethod.audio &&
                  (engineState.isLoading ||
                      engineState.hasError ||
                      !asrReady)) ...[
                const SizedBox(height: ClinicalSpacing.compact),
                Text(
                  engineState.isLoading ? 'Preparando dictado…' : 'El dictado no está disponible. Puedes escribir la nota.',
                  key: const Key('asr-availability'),
                  style: theme.textTheme.bodySmall,
                ),
                if (!engineState.isLoading)
                  TextButton(
                    onPressed: () => context.push('/models'),
                    child: const Text('Configurar dictado'),
                  ),
              ],
              _buildAssistRow(),
              if (_formError != null || _publication.isPublicationLocked) ...[
                const SizedBox(height: ClinicalSpacing.compact),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _formError ?? 'No pudimos confirmar el guardado. Puedes reintentar la misma nota.',
                    key: const Key('milestone-operation-error'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ],
              const SizedBox(height: ClinicalSpacing.compact),
              Text(
                'Una vez guardada, no podrás editarla.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: ClinicalSpacing.item),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: ClinicalSpacing.item,
                runSpacing: ClinicalSpacing.compact,
                children: [
                  OutlinedButton(
                    onPressed: _isBusy ? null : _cancel,
                    child: const Text('Descartar'),
                  ),
                  FilledButton(
                    onPressed:
                        _isBusy ||
                            (_mode == MilestoneInputMethod.text &&
                                _textController.text.trim().isEmpty)
                        ? null
                        : _save,
                    child: _isBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            !_publication.isPublicationLocked
                                ? 'Guardar nota'
                                : 'Reintentar guardado',
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssistRow() {
    final providerState = ref.watch(synthesisProviderProvider);
    final provider = providerState.valueOrNull;
    final hasDraft = _textController.text.trim().isNotEmpty;
    if (providerState.isLoading) {
      return const SizedBox.shrink();
    }
    if (providerState.hasError) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Ayuda de redacción no disponible.'),
          TextButton(
            onPressed: () => context.push('/models'),
            child: const Text('Configurar ayuda'),
          ),
        ],
      );
    }
    if (provider == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.offline_bolt_outlined, size: 18),
          Text(
            'Ayuda de redacción no disponible.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          TextButton(
            onPressed: () => context.push('/models'),
            child: const Text('Configurar ayuda'),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed:
              _isBusy ||
                  _assistance.busy ||
                  _publication.isPublicationLocked ||
                  !hasDraft
              ? null
              : _improveDraft,
          icon: const Icon(Icons.auto_fix_high_outlined),
          label: const Text('Mejorar redacción', softWrap: true),
        ),
        const SizedBox(height: ClinicalSpacing.compact),
        if (_assistance.busy)
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else if (_assistNote != null)
          Text(_assistNote!, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  Future<void> _improveDraft() async {
    final original = _textController.text;
    if (mounted) setState(() => _assistNote = null);
    final outcome = await _assistance.improve(
      original,
      idempotencyKey: _operationId,
    );
    if (!mounted ||
        outcome == null ||
        _assistance.isClosed ||
        _publication.busy ||
        _publication.isPublicationLocked ||
        _textController.text != original ||
        !identical(_assistance.outcome, outcome)) {
      return;
    }
    if (!outcome.hasSuggestion) {
      setState(() => _assistNote = _assistMessageFor(outcome.errorCode));
      return;
    }
    // The suggestion is a draft: the author keeps editing before confirming.
    _textController.text = outcome.suggestion!;
    setState(() => _assistNote = 'Revisa la sugerencia antes de guardarla.');
  }

  String _assistMessageFor(String? code) {
    return switch (code) {
      SynthesisErrorCode.unavailable => 'Ayuda de redacción no disponible.',
      SynthesisErrorCode.timeout =>
        'No se pudo mejorar la redacción. Tu texto se conserva.',
      SynthesisErrorCode.tooLong =>
        'No se pudo mejorar la redacción. Tu texto se conserva.',
      SynthesisErrorCode.cancelled =>
        'No se pudo mejorar la redacción. Tu texto se conserva.',
      SynthesisErrorCode.malformed =>
        'No se pudo mejorar la redacción. Tu texto se conserva.',
      SynthesisErrorCode.internal =>
        'No se pudo mejorar la redacción. Tu texto se conserva.',
      _ => 'No se pudo mejorar la redacción. Tu texto se conserva.',
    };
  }

  Widget _buildDictationSection() {
    final stage = _session.stage;
    final transcript = _session.transcript;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.tonalIcon(
              onPressed:
                  _isBusy ||
                      _publication.isPublicationLocked ||
                      stage == DictationStage.transcribingLocal ||
                      (stage != DictationStage.recording &&
                          (ref.watch(asrEngineProvider).isLoading ||
                              ref.watch(asrEngineProvider).hasError ||
                              ref.watch(asrEngineProvider).valueOrNull == null))
                  ? null
                  : _toggleRecording,
              icon: Icon(
                stage == DictationStage.recording ? Icons.stop : Icons.mic_none,
              ),
              label: Text(
                stage == DictationStage.recording
                    ? 'Detener dictado'
                    : 'Iniciar dictado',
              ),
            ),
            const SizedBox(height: ClinicalSpacing.compact),
            if (stage == DictationStage.recording)
              const Text('Grabando…')
            else if (stage == DictationStage.transcribingLocal)
              const Text('Transcribiendo…'),
          ],
        ),
        if (_session.canListen)
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextButton.icon(
                onPressed: _isBusy ? null : _previewRecording,
                // The visible label names the action; the tooltip supports
                // assistive technologies without duplicating visual copy.
                icon: const Icon(Icons.play_arrow),
                label: const Text('Escuchar'),
              ),
            ],
          ),
        if (transcript != null) ...[
          const SizedBox(height: ClinicalSpacing.compact),
          TextField(
            controller: _textController,
            readOnly: _isBusy || _publication.isPublicationLocked,
            maxLines: 4,
            decoration: clinicalInputDecoration(labelText: 'Nota').copyWith(
              helper: Text(
                transcript.hasUncertainSegments
                    ? 'Algunas palabras pueden ser incorrectas. Revisa el texto.'
                    : 'Revisa el texto antes de guardar.',
              ),
            ),
            onChanged: (value) => _patch(
              _session.copyWith(
                draftText: value,
                stage: DictationStage.readyToConfirm,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DeferredMilestoneWriter implements ConfirmedMilestoneWriter {
  const _DeferredMilestoneWriter(this._save);
  final Future<void> Function(ContextNoteMilestone) _save;

  @override
  Future<void> saveMilestone(ContextNoteMilestone milestone) =>
      _save(milestone);
}
