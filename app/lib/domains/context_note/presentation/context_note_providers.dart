import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/supabase_client.dart';
import '../data/asr_model_manifest.dart';
import '../data/context_note_repository.dart';
import '../data/draft_vault.dart';
import '../data/llama_gguf_synthesis_provider.dart';
import '../data/llm_model_manifest.dart';
import '../data/local_capability_repository_impl.dart';
import '../domain/local_capability_repository.dart';
import '../data/sherpa_asr_engine.dart';
import '../domain/asr_engine.dart';
import '../domain/synthesis_provider.dart';

/// Plain mutable activity flag: teardown can release it synchronously without
/// notifying a ProviderContainer that may already be disposing.
class MilestoneEditorActivity {
  bool active = false;
}

final milestoneEditorActiveProvider = Provider<MilestoneEditorActivity>(
  (ref) => MilestoneEditorActivity(),
);

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

/// Versioned manifest of the local text-assistance model.
final llmModelManifestProvider = FutureProvider.autoDispose<LlmModelManifest>((
  ref,
) async {
  final source = await rootBundle.loadString('assets/llm_model_manifest.json');
  return LlmModelManifest.parse(source);
});

final llmModelDirectoryProvider = FutureProvider.autoDispose<Directory>((
  ref,
) async {
  final base = await getApplicationSupportDirectory();
  final directory = Directory('${base.path}${Platform.pathSeparator}llm');
  if (!directory.existsSync()) await directory.create(recursive: true);
  return directory;
});

final localCapabilityRepositoryProvider =
    Provider<Future<LocalCapabilityRepository>>(
      (ref) async => LocalCapabilityRepositoryImpl(
        speech: await ref.watch(asrModelManifestProvider.future),
        writing: await ref.watch(llmModelManifestProvider.future),
        speechDirectory: await ref.watch(asrModelDirectoryProvider.future),
        writingDirectory: await ref.watch(llmModelDirectoryProvider.future),
      ),
    );

/// Local text assistance, or `null` when the model is not installed.
///
/// A missing model leaves this null and the milestone is published with the
/// author's own text. Assistance never blocks clinical writing (ADR-017).
final synthesisProviderProvider =
    FutureProvider.autoDispose<SynthesisProvider?>((ref) async {
      final manifest = await ref.watch(llmModelManifestProvider.future);
      final directory = await ref.watch(llmModelDirectoryProvider.future);
      final provider = LlamaGgufSynthesisProvider(
        manifest: manifest,
        modelDirectory: directory,
      );
      final ready = await provider.load();
      ref.onDispose(() => provider.dispose());
      return ready ? provider : null;
    });
