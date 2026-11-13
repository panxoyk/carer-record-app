import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../../core/clinical/clinical_vocabulary.dart';
import '../../../core/design_system/clinical_design_system.dart';
import '../../../core/design_system/clinical_toast.dart';
import '../../../core/time/clinical_time.dart';
import '../../auth/presentation/auth_providers.dart';
import '../../fhir_record/data/clinical_attachment_repository.dart';
import '../../fhir_record/presentation/fhir_record_providers.dart';
import '../../institutional/presentation/iam_providers.dart';
import '../../on_device_ai/domain/local_capability_repository.dart';
import '../../on_device_ai/domain/local_capability_usage.dart';
import '../../on_device_ai/presentation/local_ai_providers.dart';
import '../../patient/domain/entities/patient.dart';
import '../domain/confirmed_milestone_writer.dart';
import '../domain/entities/context_note.dart';
import '../domain/entities/dictation_stage.dart';
import '../domain/usecases/synthesis_usecases.dart';
import 'context_note_providers.dart';
import 'controllers/dictation_controller.dart';
import 'controllers/milestone_editor_controller.dart';
import 'controllers/note_assistance_controller.dart';

/// Opens the Figma "Registrar evento" flow for a bitácora event:
/// Registrar → Grabación → Procesando → Revisar y publicar → Evento publicado.
///
/// The audio branch follows ADR-016: record, transcribe on the device, let the
/// author review the draft, and only then persist the text the author
/// confirmed. The recording and the raw transcription are deleted on every
/// exit path and never leave the device. The professional chooses the event
/// category (ADR-022); a clinical photo, if any, goes to the FHIR server
/// through the gateway.
///
/// [onSaved] runs once, when the author leaves the published confirmation,
/// with `true` when local cleanup is still pending.
Future<void> showMilestoneEditorSheet(
  BuildContext context, {
  required Patient patient,
  required ValueChanged<bool> onSaved,
}) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MilestoneEditorSheet(patient: patient, onSaved: onSaved),
    ),
  );
}

enum _Step { compose, recording, processing, review, published }

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

  _Step _step = _Step.compose;
  MilestoneInputMethod _mode = MilestoneInputMethod.audio;
  final TextEditingController _textController = TextEditingController();
  late final DictationController _dictation;
  DictationSession get _session => _dictation.session;
  String? get _operationId => _dictation.operationId;
  bool _busy = false;
  String? _formError;
  bool get _isBusy => _busy || _dictation.busy;
  late final NoteAssistanceController _assistance;
  LocalCapabilityUsageLease? _usageLease;
  late final MilestoneEditorController _publication;
  Timer? _ticker;

  /// Processing progress: index of the running step and whether the local
  /// writing assistant produced the suggested text.
  int _processingStep = 0;
  bool _structuringAvailable = true;
  bool _aiSuggested = false;
  bool _editing = false;
  EventCategory? _category;

  /// Optional clinical photo chosen in the review step.
  Uint8List? _photo;
  String? _photoType;
  bool _photoFailed = false;
  bool _uploadingPhoto = false;
  String? _clientEventId;
  bool _cleanupPending = false;
  DateTime? _publishedAt;
  String? _publishedContent;

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
      // The photo is linked to the note through its client event id.
      newEventId: () => _clientEventId = _uuid.v4(),
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
    _ticker?.cancel();
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

  // -- recording ------------------------------------------------------------

  Future<void> _startRecording() async {
    if (_publication.isPublicationLocked || _isBusy) return;
    _lastAppliedTranscriptObject = null;
    setState(() => _formError = null);
    await _dictation.toggleRecording();
    if (!mounted) return;
    if (_session.stage == DictationStage.recording) {
      _textController.clear();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (mounted) setState(() {});
      });
      setState(() => _step = _Step.recording);
    }
  }

  Future<void> _finishRecording() async {
    _ticker?.cancel();
    setState(() {
      _step = _Step.processing;
      _processingStep = 0;
    });
    await _dictation.stopAndTranscribe();
    if (!mounted) return;
    if (_session.stage != DictationStage.readyToConfirm ||
        _textController.text.trim().isEmpty) {
      // Transcription failed or came back empty: return to the start with the
      // error visible; the author may record again or write the note.
      setState(() => _step = _Step.compose);
      return;
    }
    await _structure();
  }

  Future<void> _confirmDiscardRecording() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Descartar el registro?'),
        content: const Text('La grabación se eliminará de este dispositivo.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Seguir grabando'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: ClinicalColors.destructive,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (discard == true) await _cancel();
  }

  // -- processing -----------------------------------------------------------

  Future<void> _continueWithText() async {
    if (_textController.text.trim().isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _step = _Step.processing;
      _processingStep = 0;
    });
    await _structure();
  }

  /// "Estructurando evento": the local writing assistant proposes a clearer
  /// text. It never diagnoses or classifies; the author validates everything.
  Future<void> _structure() async {
    setState(() {
      _processingStep = _mode == MilestoneInputMethod.audio ? 1 : 0;
      _aiSuggested = false;
    });
    final original = _textController.text;
    final provider = await ref
        .read(synthesisProviderProvider.future)
        .then<Object?>((value) => value, onError: (_) => null);
    if (!mounted) return;
    if (provider == null) {
      setState(() => _structuringAvailable = false);
    } else {
      final outcome = await _assistance.improve(
        original,
        idempotencyKey: _operationId,
      );
      if (!mounted) return;
      if (outcome != null &&
          outcome.hasSuggestion &&
          _textController.text == original) {
        _textController.text = outcome.suggestion!;
        if (_mode == MilestoneInputMethod.audio) {
          _dictation.updateDraft(outcome.suggestion!);
        }
        _aiSuggested = true;
      }
    }
    setState(() => _processingStep += 1);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _step = _Step.review;
      _editing = false;
    });
  }

  // -- discard and publish --------------------------------------------------

  Future<bool> _discardArtifacts({bool notifyFailure = true}) async {
    final success = await _dictation.discard(notifyFailure: notifyFailure);
    if (success) {
      _lastAppliedTranscriptObject = null;
      _textController.clear();
    }
    return success;
  }

  Future<void> _cancel() async {
    _ticker?.cancel();
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
    final category = pending == null
        ? _category
        : EventCategory.fromWire(pending.category);
    if (category == null) {
      _showOperationError(
        'Elige la categoría del evento.',
        toastMessage: 'Falta la categoría.',
      );
      return;
    }
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
    setState(() {
      _busy = true;
      _formError = null;
    });
    try {
      final saved = await _publication.publish(
        content: content,
        inputMethod: pending?.inputMethod ?? _mode,
        transcription:
            pending?.transcription ??
            (isAudio ? _session.transcript?.metadata : null),
        category: category.wire,
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
    // Persistence has succeeded. Cleanup is a separate best-effort step: the
    // editor moves to the confirmation and can never publish twice.
    _publishedContent = content;
    _publishedAt = DateTime.now();
    try {
      _cleanupPending = !await _discardArtifacts(notifyFailure: false);
    } catch (_) {
      _cleanupPending = true;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = _Step.published;
    });
    if (_photo != null) await _uploadPhoto();
  }

  Future<void> _uploadPhoto() async {
    final photo = _photo, type = _photoType, clientEventId = _clientEventId;
    if (photo == null || type == null || clientEventId == null) return;
    setState(() {
      _uploadingPhoto = true;
      _photoFailed = false;
    });
    try {
      await ref
          .read(clinicalAttachmentRepositoryProvider)
          .upload(
            organizationId: widget.patient.organizationId,
            hospitalizationId: widget.patient.hospitalizationId,
            clientEventId: clientEventId,
            contentType: type,
            bytes: photo,
            takenAt: _publishedAt ?? DateTime.now(),
          );
      ref.invalidate(
        authorizedClinicalTimelineProvider(widget.patient.hospitalizationId),
      );
    } catch (_) {
      if (mounted) setState(() => _photoFailed = true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      final type = _imageType(bytes);
      if (type == null) {
        _showOperationError(
          'Elige una foto JPG o PNG.',
          toastMessage: 'Formato de foto no admitido.',
        );
        return;
      }
      if (bytes.length > maxClinicalPhotoBytes) {
        _showOperationError(
          'La foto supera los 5 MB.',
          toastMessage: 'La foto es demasiado grande.',
        );
        return;
      }
      setState(() {
        _photo = bytes;
        _photoType = type;
      });
    } catch (_) {
      _showOperationError(
        'No se pudo abrir la cámara o la galería.',
        toastMessage: 'No se pudo adjuntar la foto.',
      );
    }
  }

  void _leave() {
    Navigator.of(context).pop();
    widget.onSaved(_cleanupPending);
  }

  void _registerAnother() {
    final navigator = Navigator.of(context);
    widget.onSaved(_cleanupPending);
    navigator.pushReplacement(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _MilestoneEditorSheet(
          patient: widget.patient,
          onSaved: widget.onSaved,
        ),
      ),
    );
  }

  // -- view -----------------------------------------------------------------

  String get _patientLabel =>
      '${widget.patient.fullName} · ${widget.patient.locationLabel}';

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _step == _Step.compose && !_isBusy,
    onPopInvokedWithResult: (didPop, _) {
      if (didPop) return;
      if (_step == _Step.published) {
        _leave();
      } else if (_step == _Step.recording) {
        _confirmDiscardRecording();
      }
    },
    child: switch (_step) {
      _Step.compose => _buildCompose(context),
      _Step.recording => _buildRecording(context),
      _Step.processing => _buildProcessing(context),
      _Step.review => _buildReview(context),
      _Step.published => _buildPublished(context),
    },
  );

  Widget _closeButton({VoidCallback? onPressed, Color? color}) => Center(
    child: IconButton(
      tooltip: 'Cerrar',
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: color ?? ClinicalColors.fill,
        foregroundColor: color == null ? ClinicalColors.ink : Colors.white,
        fixedSize: const Size.square(36),
        minimumSize: const Size.square(36),
        padding: EdgeInsets.zero,
      ),
      icon: const Icon(Icons.close_rounded, size: 18),
    ),
  );

  Widget _errorText(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(top: ClinicalSpacing.compact),
    child: Semantics(
      liveRegion: true,
      child: Text(
        _formError ?? 'No pudimos confirmar el guardado. Puedes reintentar la misma nota.',
        key: const Key('milestone-operation-error'),
        style: TextStyle(color: theme.colorScheme.error),
      ),
    ),
  );

  // Paso 1: Registrar evento -------------------------------------------------

  Widget _buildCompose(BuildContext context) {
    final engineState = ref.watch(asrEngineProvider);
    final asrReady = engineState.valueOrNull != null;
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: ClinicalColors.canvas,
      appBar: clinicalAppBar(
        title: '',
        leadingWidth: 60,
        leading: _closeButton(onPressed: _isBusy ? null : _cancel),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ClinicalLargeTitle(
                'Registrar evento',
                padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  'Nueva nota de contexto',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              ClinicalPatientContextPill(label: _patientLabel),
              const SizedBox(height: ClinicalSpacing.card),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: ClinicalColors.fill,
                  borderRadius: BorderRadius.circular(ClinicalRadii.pill),
                ),
                child: SegmentedButton<MilestoneInputMethod>(
                  expandedInsets: EdgeInsets.zero,
                  segments: [
                    ButtonSegment(
                      value: MilestoneInputMethod.audio,
                      label: const Text('Audio'),
                      icon: Icon(
                        asrReady ? Icons.mic_none : Icons.mic_off_outlined,
                      ),
                    ),
                    const ButtonSegment(
                      value: MilestoneInputMethod.text,
                      label: Text('Texto'),
                      icon: Icon(Icons.edit_outlined),
                    ),
                  ],
                  selected: {_mode},
                  onSelectionChanged:
                      _isBusy || _publication.isPublicationLocked
                      ? null
                      : (selection) => setState(() {
                          _mode = selection.first;
                          _formError = null;
                        }),
                ),
              ),
              const SizedBox(height: ClinicalSpacing.section),
              if (_mode == MilestoneInputMethod.audio)
                _buildAudioStart(engineState, asrReady, theme)
              else
                _buildTextEntry(theme),
              if (_formError != null) _errorText(theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioStart(
    AsyncValue<Object?> engineState,
    bool asrReady,
    ThemeData theme,
  ) {
    final enabled = asrReady && !_isBusy && !_publication.isPublicationLocked;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Semantics(
            button: true,
            enabled: enabled,
            label: 'Iniciar dictado',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: enabled ? _startRecording : null,
              child: Column(
                children: [
                  Container(
                    width: 196,
                    height: 196,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: enabled
                          ? ClinicalColors.softMint
                          : ClinicalColors.fillSubtle,
                      shape: BoxShape.circle,
                    ),
                    child: Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: enabled
                            ? ClinicalColors.mint
                            : ClinicalColors.tertiary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.mic_none,
                        size: 64,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: ClinicalSpacing.section),
                  const Text(
                    'Registro por voz',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.4,
                      color: ClinicalColors.mintText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Iniciar dictado',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: ClinicalColors.mintDark,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Describe verbalmente el acontecimiento clínico.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: ClinicalColors.tertiary),
        ),
        if (engineState.isLoading || engineState.hasError || !asrReady) ...[
          const SizedBox(height: ClinicalSpacing.compact),
          Text(
            engineState.isLoading
                ? 'Preparando dictado…'
                : 'El dictado no está disponible. Puedes escribir la nota.',
            key: const Key('asr-availability'),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
          if (!engineState.isLoading)
            TextButton(
              onPressed: () => context.push('/models'),
              child: const Text('Configurar dictado'),
            ),
        ],
        const SizedBox(height: ClinicalSpacing.section),
        for (final (index, tip) in const [
          'Menciona la hora del evento si es relevante',
          'Indica el contexto clínico brevemente',
          'No incluyas datos identificatorios sensibles',
        ].indexed)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                top: index == 0
                    ? const BorderSide(color: ClinicalColors.separator)
                    : BorderSide.none,
                bottom: const BorderSide(color: ClinicalColors.separator),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: const BoxDecoration(
                    color: ClinicalColors.softMint,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 12,
                    color: ClinicalColors.mintDark,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tip,
                    style: const TextStyle(
                      fontSize: 13,
                      color: ClinicalColors.secondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTextEntry(ThemeData theme) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: _textController,
        readOnly: _isBusy || _publication.isPublicationLocked,
        minLines: 6,
        maxLines: 10,
        decoration: clinicalInputDecoration(
          labelText: 'Nota',
          hintText: 'Describe el acontecimiento clínico.',
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: 4, right: 4),
        child: Text(
          '${_textController.text.length}/$maxMilestoneTextLength',
          textAlign: TextAlign.end,
          style: const TextStyle(fontSize: 12, color: ClinicalColors.tertiary),
        ),
      ),
      const SizedBox(height: ClinicalSpacing.card),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
        onPressed: _isBusy || _textController.text.trim().isEmpty
            ? null
            : _continueWithText,
        child: const Text('Continuar'),
      ),
    ],
  );

  // Paso 2: Grabación ------------------------------------------------------

  Widget _buildRecording(BuildContext context) {
    final recording = _session.stage == DictationStage.recording;
    final paused = _dictation.paused;
    final elapsed = _dictation.elapsed;
    final timer =
        '${elapsed.inMinutes.toString().padLeft(2, '0')}:${(elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
    final status = paused
        ? 'Grabación en pausa'
        : recording
        ? 'Grabando'
        : 'Listo para grabar';
    return Scaffold(
      backgroundColor: const Color(0xff0a0a0a),
      appBar: AppBar(
        backgroundColor: const Color(0xff0a0a0a),
        surfaceTintColor: const Color(0xff0a0a0a),
        leadingWidth: 60,
        leading: _closeButton(
          onPressed: _confirmDiscardRecording,
          color: const Color(0x33ffffff),
        ),
      ),
      body: SafeArea(
        top: false,
        child: _FillScroll(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClinicalPatientContextPill(label: _patientLabel),
              const Spacer(),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: paused
                        ? const Color(0x14ffffff)
                        : const Color(0x26ff3b30),
                    borderRadius: BorderRadius.circular(ClinicalRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!paused) ...[
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: ClinicalColors.destructive,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        status,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: paused
                              ? Colors.white70
                              : ClinicalColors.destructive,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Semantics(
                label: 'Tiempo grabado $timer',
                excludeSemantics: true,
                child: Text(
                  timer,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                    color: Colors.white,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _Waveform(levels: _dictation.levels(), active: !paused),
              const Spacer(),
              if (_dictation.canPause)
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: paused
                      ? _dictation.resumeRecording
                      : _dictation.pauseRecording,
                  child: Text(
                    paused ? 'Reanudar grabación' : 'Pausar grabación',
                  ),
                ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                  backgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Color(0x66ffffff)),
                ),
                onPressed: _finishRecording,
                icon: const Icon(Icons.stop),
                label: const Text('Detener dictado'),
              ),
              TextButton(
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                onPressed: _confirmDiscardRecording,
                child: const Text('Descartar registro'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Paso 3: Procesando registro --------------------------------------------

  Widget _buildProcessing(BuildContext context) {
    final steps = [
      if (_mode == MilestoneInputMethod.audio)
        ('Transcribiendo audio', 'Convirtiendo voz a texto en el dispositivo…'),
      (
        'Estructurando evento',
        _structuringAvailable
            ? 'Mejorando la redacción con la IA local…'
            : 'Ayuda de redacción no disponible; se usa tu texto.',
      ),
      ('Preparando revisión', 'Listo para que valides el registro.'),
    ];
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: _FillScroll(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),
              const SizedBox(
                width: 90,
                height: 90,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 32),
              const Text(
                'Procesando registro',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Carer-Record está preparando una propuesta para su revisión.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: ClinicalColors.secondary),
              ),
              const SizedBox(height: 40),
              for (var i = 0; i < steps.length; i++)
                _ProcessingStep(
                  label: steps[i].$1,
                  detail: steps[i].$2,
                  state: i < _processingStep
                      ? _StepState.done
                      : i == _processingStep
                      ? _StepState.active
                      : _StepState.pending,
                ),
              const Spacer(),
              const Text(
                'Este proceso no constituye diagnóstico clínico.',
                style: TextStyle(fontSize: 12, color: ClinicalColors.tertiary),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // Paso 4: Revisar y publicar ---------------------------------------------

  Widget _buildReview(BuildContext context) {
    final theme = Theme.of(context);
    final iam = ref.watch(iamContextProvider).valueOrNull;
    final profession = Profession.fromWire(iam?.profession);
    final now = DateTime.now();
    final locked = _publication.isPublicationLocked;
    final transcript = _session.transcript;
    return Scaffold(
      backgroundColor: ClinicalColors.canvas,
      appBar: clinicalAppBar(
        title: 'Revisar y publicar',
        leadingWidth: 60,
        leading: _closeButton(onPressed: _isBusy ? null : _cancel),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ClinicalColors.softMint,
                  borderRadius: BorderRadius.circular(ClinicalRadii.control),
                  border: Border.all(color: const Color(0x404eddb3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 18,
                      color: ClinicalColors.mintText,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Revise la información antes de incorporarla al historial. La IA sugiere, usted valida.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: ClinicalColors.mintText,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ClinicalCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (_mode == MilestoneInputMethod.audio
                                          ? 'Transcripción sugerida'
                                          : 'Texto del evento')
                                      .toUpperCase(),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    letterSpacing: .5,
                                    fontWeight: FontWeight.w600,
                                    color: ClinicalColors.secondary,
                                  ),
                                ),
                                if (_aiSuggested) ...[
                                  const SizedBox(height: 4),
                                  const _AiBadge(),
                                ],
                              ],
                            ),
                          ),
                          TextButton.icon(
                            onPressed: locked || _isBusy
                                ? null
                                : () => setState(() => _editing = !_editing),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: Text(_editing ? 'Listo' : 'Editar'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (transcript?.hasUncertainSegments == true)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: Text(
                          'Algunas palabras pueden ser incorrectas. Revisa el texto.',
                          style: TextStyle(
                            fontSize: 13,
                            color: ClinicalColors.attention,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _editing
                          ? TextField(
                              key: const Key('review-text'),
                              controller: _textController,
                              autofocus: true,
                              minLines: 4,
                              maxLines: 12,
                              decoration:
                                  clinicalInputDecoration(
                                    labelText: 'Nota',
                                  ).copyWith(
                                    helperText:
                                        transcript?.hasUncertainSegments == true
                                        ? null
                                        : 'Revisa el texto antes de guardar.',
                                  ),
                              onChanged: _mode == MilestoneInputMethod.audio
                                  ? _dictation.updateDraft
                                  : null,
                            )
                          : GestureDetector(
                              onTap: locked
                                  ? null
                                  : () => setState(() => _editing = true),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _textController.text,
                                    style: ClinicalTextStyles.body,
                                  ),
                                  if (!locked) ...[
                                    const SizedBox(height: 8),
                                    const Text(
                                      'Toque para editar',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: ClinicalColors.tertiary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ClinicalCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Categoría'.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        letterSpacing: .5,
                        fontWeight: FontWeight.w600,
                        color: ClinicalColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Elige la categoría del evento.',
                      style: ClinicalTextStyles.subhead,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in EventCategory.values)
                          _CategoryButton(
                            category: category,
                            selected: _category == category,
                            onTap: locked
                                ? null
                                : () => setState(() => _category = category),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ClinicalCard(
                padding: const EdgeInsets.all(16),
                child: _photo == null
                    ? Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Foto de curación (opcional)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Tomar foto',
                            onPressed: locked
                                ? null
                                : () => _pickPhoto(ImageSource.camera),
                            icon: const Icon(Icons.photo_camera_outlined),
                          ),
                          IconButton(
                            tooltip: 'Elegir de la galería',
                            onPressed: locked
                                ? null
                                : () => _pickPhoto(ImageSource.gallery),
                            icon: const Icon(Icons.photo_library_outlined),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(
                              ClinicalRadii.control,
                            ),
                            child: Image.memory(
                              _photo!,
                              height: 180,
                              fit: BoxFit.cover,
                              semanticLabel: 'Vista previa de la foto',
                            ),
                          ),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: TextButton(
                              onPressed: locked
                                  ? null
                                  : () => setState(() {
                                      _photo = null;
                                      _photoType = null;
                                    }),
                              child: const Text('Quitar foto'),
                            ),
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              ClinicalCard(
                elevated: false,
                border: Border.all(color: ClinicalColors.separator),
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: _Meta(
                        'Autor',
                        [
                          iam?.displayName ?? 'Profesional',
                          ?profession?.roleLabel,
                        ].join(' · '),
                      ),
                    ),
                    Expanded(child: _Meta('Hora', formatClinicalTime(now))),
                    Expanded(child: _Meta('Turno', clinicalShiftLabel(now))),
                  ],
                ),
              ),
              if (_formError != null || locked) _errorText(theme),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                onPressed:
                    _isBusy ||
                        _textController.text.trim().isEmpty ||
                        (_category == null && !locked)
                    ? null
                    : _save,
                icon: _isBusy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  locked ? 'Reintentar guardado' : 'Confirmar y publicar',
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: locked || _isBusy
                    ? null
                    : () => setState(() => _editing = true),
                child: const Text('Editar'),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: ClinicalColors.destructive,
                  minimumSize: const Size(0, 44),
                ),
                onPressed: _isBusy ? null : _cancel,
                child: const Text('Descartar evento'),
              ),
              const Text(
                'Una vez guardada, no podrás editarla.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: ClinicalColors.tertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Paso 5: Evento publicado -----------------------------------------------

  Widget _buildPublished(BuildContext context) {
    final iam = ref.watch(iamContextProvider).valueOrNull;
    final at = _publishedAt ?? DateTime.now();
    final category = _category ?? EventCategory.notaClinica;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 104,
                  height: 104,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: ClinicalColors.softMint,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: ClinicalColors.mint,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Evento publicado',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'El registro fue incorporado a la bitácora del paciente.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: ClinicalColors.secondary),
              ),
              const SizedBox(height: 32),
              ClinicalCard(
                border: Border.all(color: ClinicalColors.separator),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${formatClinicalTime(at)} · ${iam?.displayName ?? 'Profesional'}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: ClinicalColors.secondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: ClinicalBadge(
                              label: category.label,
                              color: category.tint.background,
                              textColor: category.tint.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _publishedContent ?? '',
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      color: ClinicalColors.softMint,
                      child: Row(
                        children: [
                          const Icon(
                            Icons.circle,
                            size: 6,
                            color: ClinicalColors.mintDark,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Incorporado a la bitácora',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: ClinicalColors.mintText,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Turno ${clinicalShiftLabel(at)}',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                fontSize: 12,
                                color: ClinicalColors.mintText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (_photo != null) ...[
                const SizedBox(height: 12),
                if (_uploadingPhoto)
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Text('Adjuntando foto a la ficha clínica…'),
                    ],
                  )
                else if (_photoFailed)
                  Column(
                    children: [
                      const Text(
                        'La nota quedó publicada, pero no se pudo adjuntar la foto.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: ClinicalColors.attention),
                      ),
                      TextButton(
                        onPressed: _uploadPhoto,
                        child: const Text('Reintentar foto'),
                      ),
                    ],
                  )
                else
                  const Text(
                    'Foto adjuntada a la ficha clínica.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: ClinicalColors.mintText),
                  ),
              ],
              const SizedBox(height: 32),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(0, 56)),
                onPressed: _uploadingPhoto ? null : _leave,
                child: const Text('Volver a la bitácora'),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _uploadingPhoto ? null : _registerAnother,
                child: const Text('Registrar otro evento'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// JPEG or PNG content type from the file signature, or null.
String? _imageType(Uint8List bytes) {
  if (bytes.length > 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff) {
    return 'image/jpeg';
  }
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length > png.length &&
      [for (var i = 0; i < png.length; i++) bytes[i] == png[i]]
          .every((x) => x)) {
    return 'image/png';
  }
  return null;
}

class _Waveform extends StatefulWidget {
  const _Waveform({required this.levels, required this.active});
  final Stream<double> levels;
  final bool active;

  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform> {
  static const _bars = 24;
  final List<double> _history = List.filled(_bars, 0.1);
  StreamSubscription<double>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = widget.levels.listen((level) {
      if (!mounted || !widget.active) return;
      setState(() {
        _history
          ..removeAt(0)
          ..add(level.clamp(0.08, 1.0));
      });
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox(
      height: 56,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final level in _history)
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 3,
              height: 4 + 52 * level,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: widget.active
                    ? ClinicalColors.mint
                    : ClinicalColors.mint.withValues(alpha: .4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
        ],
      ),
    ),
  );
}

enum _StepState { done, active, pending }

class _ProcessingStep extends StatelessWidget {
  const _ProcessingStep({
    required this.label,
    required this.detail,
    required this.state,
  });
  final String label;
  final String detail;
  final _StepState state;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: state == _StepState.pending ? .35 : 1,
    child: Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: switch (state) {
                _StepState.done => ClinicalColors.mint,
                _StepState.active => ClinicalColors.softMint,
                _StepState.pending => ClinicalColors.fillSubtle,
              },
              shape: BoxShape.circle,
            ),
            child: switch (state) {
              _StepState.done => const Icon(
                Icons.check_rounded,
                size: 16,
                color: Colors.white,
              ),
              _StepState.active => const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              _StepState.pending => const Icon(
                Icons.circle,
                size: 8,
                color: ClinicalColors.tertiary,
              ),
            },
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (state != _StepState.pending)
                  Text(
                    state == _StepState.done ? 'Completado' : detail,
                    style: TextStyle(
                      fontSize: 12,
                      color: state == _StepState.done
                          ? ClinicalColors.mintText
                          : ClinicalColors.secondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _AiBadge extends StatelessWidget {
  const _AiBadge();

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: ClinicalColors.softMint,
      borderRadius: BorderRadius.circular(ClinicalRadii.pill),
      border: Border.all(color: const Color(0x404eddb3)),
    ),
    child: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.auto_awesome, size: 12, color: ClinicalColors.mintText),
        SizedBox(width: 6),
        Flexible(
          child: Text(
            'Sugerido por IA',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: ClinicalColors.mintText,
            ),
          ),
        ),
      ],
    ),
  );
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.category,
    required this.selected,
    required this.onTap,
  });
  final EventCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tint = category.tint;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected ? tint.color : tint.background,
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? tint.color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                ],
                Flexible(
                  child: Text(
                    category.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : tint.color,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: ClinicalTextStyles.footnote),
      const SizedBox(height: 2),
      Text(
        value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
      ),
    ],
  );
}

class _DeferredMilestoneWriter implements ConfirmedMilestoneWriter {
  const _DeferredMilestoneWriter(this._save);
  final Future<void> Function(ContextNoteMilestone) _save;

  @override
  Future<void> saveMilestone(ContextNoteMilestone milestone) =>
      _save(milestone);
}

/// Fills the screen like a Column with Spacers, but scrolls when the content
/// does not fit (small screens or large text).
class _FillScroll extends StatelessWidget {
  const _FillScroll({required this.padding, required this.child});
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      padding: padding,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: (constraints.maxHeight - padding.vertical).clamp(
            0,
            double.infinity,
          ),
        ),
        child: IntrinsicHeight(child: child),
      ),
    ),
  );
}
