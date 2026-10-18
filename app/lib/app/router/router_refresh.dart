import 'package:flutter/foundation.dart';

class RouterRefresh extends ChangeNotifier {
  RouterRefresh(this._gate) {
    _gate.addListener(notifyListeners);
  }

  final ChangeNotifier _gate;

  void refresh() => notifyListeners();

  @override
  void dispose() {
    _gate.removeListener(notifyListeners);
    super.dispose();
  }
}
