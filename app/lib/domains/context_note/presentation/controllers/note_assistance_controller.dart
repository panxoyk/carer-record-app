import 'package:flutter/foundation.dart';

import '../../../on_device_ai/domain/synthesis_provider.dart';
import '../../domain/usecases/synthesis_usecases.dart';

typedef ImproveNoteDraftLoader = Future<ImproveNoteDraft?> Function();

class NoteAssistanceController extends ChangeNotifier {
  NoteAssistanceController({required this.load});

  final ImproveNoteDraftLoader load;
  int _generation = 0;
  bool _closed = false;
  bool busy = false;
  String? errorCode;
  SynthesisOutcome? outcome;
  bool get isClosed => _closed;

  void invalidate() {
    _generation++;
    busy = false;
    outcome = null;
    errorCode = null;
    if (!_closed) notifyListeners();
  }

  Future<SynthesisOutcome?> improve(
    String text, {
    String? idempotencyKey,
  }) async {
    if (_closed || busy) return null;
    final revision = ++_generation;
    busy = true;
    outcome = null;
    errorCode = null;
    notifyListeners();
    SynthesisOutcome? result;
    try {
      final useCase = await load();
      result = useCase == null
          ? SynthesisOutcome(
              fallback: text.trim(),
              errorCode: SynthesisErrorCode.unavailable,
            )
          : await useCase(
              text: text,
              idempotencyKey: idempotencyKey,
              isCancelled: () => _closed || revision != _generation,
            );
    } catch (_) {
      result = SynthesisOutcome(
        fallback: text.trim(),
        errorCode: SynthesisErrorCode.internal,
      );
    }
    if (_closed || revision != _generation) return null;
    busy = false;
    outcome = result;
    errorCode = result.errorCode;
    notifyListeners();
    return result;
  }

  @override
  void dispose() {
    _generation++;
    _closed = true;
    super.dispose();
  }
}
