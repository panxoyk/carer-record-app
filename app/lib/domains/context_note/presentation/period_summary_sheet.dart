import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../on_device_ai/presentation/local_ai_providers.dart';
import '../domain/usecases/summarize_period.dart';

/// Bottom sheet that produces an editable local summary of a period's notes.
Future<void> showPeriodSummarySheet(
  BuildContext context, {
  required List<String> notes,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _PeriodSummarySheet(notes: notes),
  );
}

class _PeriodSummarySheet extends ConsumerStatefulWidget {
  const _PeriodSummarySheet({required this.notes});

  final List<String> notes;

  @override
  ConsumerState<_PeriodSummarySheet> createState() => _PeriodSummarySheetState();
}

class _PeriodSummarySheetState extends ConsumerState<_PeriodSummarySheet> {
  bool _busy = false;
  String? _summary;
  String? _error;

  Future<void> _generate() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final provider = await ref.read(synthesisProviderProvider.future);
      if (provider == null) {
        setState(() => _error = 'Ayuda de redacción no disponible.');
        return;
      }
      final outcome = await SummarizePeriod(provider: provider)(
        notes: widget.notes,
      );
      if (!mounted) return;
      if (!outcome.hasSuggestion) {
        setState(() => _error = 'No se pudo generar el resumen.');
        return;
      }
      setState(() => _summary = outcome.suggestion);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Resumen del periodo',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_busy)
            const Center(child: CircularProgressIndicator())
          else if (_summary != null)
            SelectableText(_summary!)
          else if (_error != null)
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))
          else
            const Text('Genera un resumen local de las notas del periodo.'),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _busy ? null : _generate,
            child: const Text('Generar resumen'),
          ),
        ],
      ),
    );
  }
}
