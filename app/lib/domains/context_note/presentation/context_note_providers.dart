import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/supabase_client.dart';
import '../data/asr_model_manifest.dart';
import '../data/context_note_repository.dart';
import '../data/draft_vault.dart';
import '../data/sherpa_asr_engine.dart';
import '../domain/asr_engine.dart';

final contextNoteRepositoryProvider =
    Provider.autoDispose<ContextNoteRepository>(
      (ref) => ContextNoteRepository(ref.watch(supabaseClientProvider)),
    );

/// Versioned model manifest shipped with the binary. It records origin, licence,
/// version and checksums; the weights are installed separately.
final asrModelManifestProvider = FutureProvider.autoDispose<AsrModelManifest>((
  ref,
) async {
  final source = await rootBundle.loadString('assets/asr_model_manifest.json');
  return AsrModelManifest.parse(source);
});

/// Where the weights live. Application support, not documents: the directory is
/// private to the app and is not exposed to shared storage or backups.
final asrModelDirectoryProvider = FutureProvider.autoDispose<Directory>((
  ref,
) async {
  final base = await getApplicationSupportDirectory();
  final directory = Directory('${base.path}${Platform.pathSeparator}asr');
  if (!directory.existsSync()) await directory.create(recursive: true);
  return directory;
});

/// The local speech engine, or `null` while it cannot be used.
///
/// A missing model leaves this null and the audio milestone unavailable, which is
/// the fail-closed behaviour ADR-016 requires. There is no remote fallback: the
/// text milestone stays available instead.
final asrEngineProvider = FutureProvider.autoDispose<AsrEngine?>((ref) async {
  final manifest = await ref.watch(asrModelManifestProvider.future);
  final directory = await ref.watch(asrModelDirectoryProvider.future);
  final engine = SherpaAsrEngine(manifest: manifest, modelDirectory: directory);
  final ready = await engine.load();
  ref.onDispose(() => engine.dispose());
  return ready ? engine : null;
});

final draftVaultProvider = Provider.autoDispose<DraftVault>((ref) {
  final vault = DraftVault();
  // A crash must not leave recordings or transcripts behind: sweep whatever
  // outlived its local lifetime before a new dictation can start. Failures here
  // never block a milestone; the next purge retries.
  unawaited(vault.sweepExpired().catchError((Object _) => 0));
  return vault;
});
