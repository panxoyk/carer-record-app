import 'package:flutter/foundation.dart';

import '../../domain/period_summary.dart';

enum PeriodSummaryPhase {
  loadingSources,
  ready,
  preview,
  generating,
  saving,
  saveFailed,
  saved,
  cancelled,
  error,
}

class PeriodSummaryController extends ChangeNotifier {
  PeriodSummaryController({
    required this.repository,
    required this.generator,
    required this.organizationId,
    required this.hospitalizationId,
    required this.canContinue,
  });

  final PeriodSummaryRepository repository;
  final PeriodSummaryGenerator generator;
  final String organizationId;
  final String hospitalizationId;
  final bool Function() canContinue;

  PeriodSummaryPhase phase = PeriodSummaryPhase.ready;
  String? errorCode;
  int sourceCount = 0;
  int excludedUndatedCount = 0;
  SummaryDraft? draft;
  PeriodSummary? saved;
  SummarySaveAttempt? _attempt;
  bool _cancelRequested = false;
  bool get cancelRequested => _cancelRequested;
  bool _disposed = false;
  bool get _authorized => !_disposed && canContinue();
  bool get busy =>
      phase == PeriodSummaryPhase.generating ||
      phase == PeriodSummaryPhase.loadingSources ||
      phase == PeriodSummaryPhase.saving;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> preview(
    SummaryWindow window,
    Set<SummarySourceKind> kinds,
  ) async {
    if (busy || phase == PeriodSummaryPhase.saveFailed) return;
    if (!_authorized || kinds.isEmpty) return _deny();
    phase = PeriodSummaryPhase.loadingSources;
    errorCode = null;
    draft = null;
    _attempt = null;
    _notify();
    try {
      final context = await repository.loadContext(
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
      );
      if (!_valid(context, window)) return;
      final batch = await repository.loadSources(
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
        window: window,
        selectedKinds: Set.unmodifiable(kinds),
      );
      if (!_authorized) return _deny();
      if (!batch.complete) {
        throw const PeriodSummaryException('sources_incomplete');
      }
      final prepared = prepareSummary(
        batch.sources,
        window: window,
        selectedKinds: kinds,
      );
      if (prepared.sources.isEmpty) {
        throw const PeriodSummaryException('no_dated_sources');
      }
      sourceCount = prepared.sources.length;
      excludedUndatedCount = prepared.excludedUndatedCount;
      phase = PeriodSummaryPhase.preview;
    } catch (error) {
      _fail(error);
    }
    _notify();
  }

  Future<void> generate(
    SummaryWindow window,
    Set<SummarySourceKind> kinds,
  ) async {
    if (busy || phase == PeriodSummaryPhase.saveFailed) return;
    final selectedKinds = Set<SummarySourceKind>.unmodifiable(kinds);
    if (!_authorized) return _deny();
    _cancelRequested = false;
    phase = PeriodSummaryPhase.generating;
    errorCode = null;
    _notify();
    try {
      final context = await repository.loadContext(
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
      );
      if (!_valid(context, window)) return;
      final result = await generator.generate(
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
        window: window,
        selectedKinds: selectedKinds,
        isCancelled: () => _cancelRequested || !_authorized,
      );
      if (_cancelRequested) {
        phase = PeriodSummaryPhase.cancelled;
        _notify();
        return;
      }
      if (!_authorized) return _deny();
      draft = result;
      _attempt = SummarySaveAttempt(
        draft: result,
        organizationId: organizationId,
        hospitalizationId: hospitalizationId,
        patientId: context.patientId,
        window: window,
        selectedKinds: selectedKinds,
      );
      await retrySave();
    } catch (error) {
      if (!_authorized) {
        _deny();
      } else if (_cancelRequested ||
          (error is PeriodSummaryException &&
              (error.code == 'cancelled' ||
                  error.code == 'synthesis_synthesis_cancelled'))) {
        phase = PeriodSummaryPhase.cancelled;
      } else {
        _fail(error);
      }
      _notify();
    }
  }

  void cancelGeneration() {
    if (phase != PeriodSummaryPhase.generating) return;
    _cancelRequested = true;
  }

  Future<void> retrySave() async {
    if (phase == PeriodSummaryPhase.saving) return;
    final attempt = _attempt;
    if (attempt == null || !_authorized) return _deny();
    phase = PeriodSummaryPhase.saving;
    errorCode = null;
    _notify();
    try {
      saved = await repository.save(attempt);
      if (!_authorized) return _deny();
      phase = PeriodSummaryPhase.saved;
    } catch (error) {
      if (error is PeriodSummaryException &&
          error.code == 'authorization_lost') {
        return invalidateAccess();
      }
      if (!_authorized) return _deny();
      errorCode = error is PeriodSummaryException
          ? error.code
          : 'repository_unavailable';
      phase = PeriodSummaryPhase.saveFailed;
    }
    _notify();
  }

  void invalidateAccess() {
    draft = null;
    saved = null;
    _attempt = null;
    sourceCount = 0;
    excludedUndatedCount = 0;
    errorCode = 'authorization_lost';
    phase = PeriodSummaryPhase.error;
    _notify();
  }

  bool _valid(PeriodSummaryContext context, SummaryWindow window) {
    if (!_authorized) {
      _deny();
      return false;
    }
    if (context.timezone != window.timezone) {
      errorCode = 'timezone_mismatch';
      phase = PeriodSummaryPhase.error;
      _notify();
      return false;
    }
    return true;
  }

  void _deny() => invalidateAccess();
  void _fail(Object error) {
    errorCode = error is PeriodSummaryException
        ? error.code
        : 'repository_unavailable';
    phase = PeriodSummaryPhase.error;
  }

  @override
  void dispose() {
    _disposed = true;
    draft = null;
    saved = null;
    _attempt = null;
    super.dispose();
  }
}
