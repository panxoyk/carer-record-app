import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef SessionArtifactCleanup = Future<void> Function();

/// Generic session-bound local cleanup; domains compose their implementation at startup.
final sessionArtifactCleanupProvider = Provider<SessionArtifactCleanup>(
  (ref) => () async {},
);
