import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'clinical_tokens.dart';

final GlobalKey<OverlayState> _clinicalToastOverlayKey =
    GlobalKey<OverlayState>();

/// Places the toast overlay above navigator routes, including dialogs.
class ClinicalToastHost extends StatefulWidget {
  const ClinicalToastHost({required this.child, super.key});

  final Widget child;

  @override
  State<ClinicalToastHost> createState() => _ClinicalToastHostState();
}

class _ClinicalToastHostState extends State<ClinicalToastHost> {
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      Positioned.fill(
        child: Overlay(
          key: _clinicalToastOverlayKey,
          initialEntries: [
            OverlayEntry(builder: (_) => const SizedBox.expand()),
          ],
        ),
      ),
    ],
  );

  @override
  void dispose() {
    ClinicalToast._disposeHost();
    super.dispose();
  }
}

/// App-wide, presentation-only notifications shown above navigator routes.
abstract final class ClinicalToast {
  static const int maxVisible = 1;
  static ValueNotifier<List<_ToastRecord>> _records = ValueNotifier([]);
  static OverlayEntry? _overlayEntry;
  static int _sequence = 0;
  static _ToastRecord? _current;

  static void success(
    BuildContext context, {
    required String message,
    String? identifier,
    bool withDetails = false,
  }) => _show(
    context,
    message: message,
    identifier: identifier,
    isFailure: false,
    withDetails: withDetails,
  );

  static void failure(
    BuildContext context, {
    required String message,
    String? identifier,
    bool withDetails = false,
  }) {
    _show(
      context,
      message: message,
      identifier: identifier,
      isFailure: true,
      withDetails: withDetails,
    );
  }

  static void _show(
    BuildContext context, {
    required String message,
    required String? identifier,
    required bool isFailure,
    required bool withDetails,
  }) {
    if (!context.mounted) return;
    final id = identifier ?? 'clinical-toast-${_sequence++}';
    _current?.timer?.cancel();
    final record = _ToastRecord(
      id: id,
      message: message,
      isFailure: isFailure,
      duration: Duration(seconds: withDetails ? 4 : 3),
    );
    _current = record;
    _publish();
    _ensureOverlayEntry(context);
  }

  static void _startLifetime(_ToastRecord record) {
    if (!identical(record, _current) || record.timer != null) {
      return;
    }
    record.timer = Timer(record.duration, () => _remove(record));
  }

  static void _ensureOverlayEntry(BuildContext context) {
    if (_overlayEntry != null) {
      _overlayEntry!.markNeedsBuild();
      return;
    }
    final overlay =
        _clinicalToastOverlayKey.currentState ??
        Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    _overlayEntry = OverlayEntry(
      builder: (context) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: Material(
            type: MaterialType.transparency,
            child: ValueListenableBuilder<List<_ToastRecord>>(
              valueListenable: _records,
              builder: (context, records, _) => _ToastPresenter(
                records: records,
                reduceMotion: MediaQuery.disableAnimationsOf(context),
              ),
            ),
          ),
        ),
      ),
    );
    overlay.insert(_overlayEntry!);
  }

  static void _remove(_ToastRecord record) {
    if (!identical(record, _current)) return;
    _removeRecord(record);
    _current = null;
    _publish();
    _removeOverlayEntry();
  }

  static void _removeRecord(_ToastRecord record) {
    record.timer?.cancel();
    record.timer = null;
  }

  static void _publish() {
    _records.value = _current == null ? const [] : [_current!];
  }

  static void dismissAll() {
    _current?.timer?.cancel();
    _current = null;
    _publish();
    _removeOverlayEntry();
  }

  static void _disposeHost() {
    // Stop timers before removing the overlay during host teardown.
    _current?.timer?.cancel();
    _current = null;
    _disposeOverlayEntry();
    // The overlay is being torn down with its host, so do not publish here.
    _records.dispose();
    _records = ValueNotifier([]);
  }

  static void _removeOverlayEntry() {
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }

  static void _disposeOverlayEntry() {
    final entry = _overlayEntry;
    _overlayEntry = null;
    if (entry != null) {
      entry.remove();
      entry.dispose();
    }
  }
}

class _ToastRecord {
  _ToastRecord({
    required this.id,
    required this.message,
    required this.isFailure,
    required this.duration,
  });
  final String id, message;
  final bool isFailure;
  final Duration duration;
  Timer? timer;
}

class _ToastPresenter extends StatefulWidget {
  const _ToastPresenter({required this.records, required this.reduceMotion});
  final List<_ToastRecord> records;
  final bool reduceMotion;

  @override
  State<_ToastPresenter> createState() => _ToastPresenterState();
}

class _ToastPresenterState extends State<_ToastPresenter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
    _sync(newRecord: true);
  }

  @override
  void didUpdateWidget(_ToastPresenter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(
      newRecord: oldWidget.records.firstOrNull != widget.records.firstOrNull,
    );
  }

  void _sync({required bool newRecord}) {
    if (widget.records.isEmpty) {
      _controller.stop();
      return;
    }
    if (newRecord) {
      _controller.value = widget.reduceMotion ? 1 : 0;
      ClinicalToast._startLifetime(widget.records.single);
      if (!widget.reduceMotion) _controller.forward();
    } else if (widget.reduceMotion) {
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _opacity.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.records.isEmpty) return const SizedBox.shrink();
    final front = widget.records.single;
    return FadeTransition(
      opacity: _opacity,
      child: _ToastContent(
        key: ValueKey(front.id),
        message: front.message,
        isFailure: front.isFailure,
        onClose: () => ClinicalToast._remove(front),
      ),
    );
  }
}

class _ToastContent extends StatelessWidget {
  const _ToastContent({
    super.key,
    required this.message,
    required this.isFailure,
    required this.onClose,
  });

  final String message;
  final bool isFailure;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height),
      child: SingleChildScrollView(
        child: SizedBox(
          width: math.min(560, MediaQuery.sizeOf(context).width),
          child: Container(
            margin: const EdgeInsets.fromLTRB(
              ClinicalSpacing.item,
              ClinicalSpacing.compact,
              ClinicalSpacing.item,
              ClinicalSpacing.compact,
            ),
            decoration: BoxDecoration(
              color: isFailure
                  ? ClinicalColors.softAttention
                  : ClinicalColors.softMint,
              borderRadius: BorderRadius.circular(ClinicalRadii.card),
              border: Border.all(color: ClinicalColors.separator),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x26000000),
                  blurRadius: 16,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(ClinicalSpacing.item),
            child: Row(
              children: [
                Icon(
                  isFailure
                      ? Icons.warning_amber_rounded
                      : Icons.check_circle_rounded,
                  color: isFailure
                      ? ClinicalColors.attention
                      : ClinicalColors.mintText,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        message,
                        style: Theme.of(context).textTheme.bodyLarge,
                        softWrap: true,
                        maxLines: null,
                        overflow: TextOverflow.visible,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Cerrar aviso',
                  style: IconButton.styleFrom(
                    foregroundColor: ClinicalColors.ink,
                  ),
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
