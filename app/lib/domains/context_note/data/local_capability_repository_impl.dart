import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../domain/local_capability_repository.dart';
import 'asr_model_installer.dart';
import 'asr_model_manifest.dart';
import 'llm_model_installer.dart';
import 'llm_model_manifest.dart';

/// Filesystem-backed inventory and lifecycle adapter for the shipped manifests.
/// Query intentionally checks identity and lengths only; [verify] is the
/// explicit, potentially expensive integrity pass.
class LocalCapabilityRepositoryImpl implements LocalCapabilityRepository {
  LocalCapabilityRepositoryImpl({
    required this.speech,
    required this.writing,
    required this.speechDirectory,
    required this.writingDirectory,
    AsrModelInstaller? speechInstaller,
    LlmModelInstaller? writingInstaller,
  }) : speechInstaller = speechInstaller ?? const AsrModelInstaller(),
       writingInstaller = writingInstaller ?? const LlmModelInstaller();

  final AsrModelManifest speech;
  final LlmModelManifest writing;
  final Directory speechDirectory;
  final Directory writingDirectory;
  final AsrModelInstaller speechInstaller;
  final LlmModelInstaller writingInstaller;
  final Set<LocalCapability> _busy = {};

  @override
  Future<List<LocalCapabilitySnapshot>> query() async => [
    await _snapshot(LocalCapability.transcription),
    await _snapshot(LocalCapability.textAssistance),
  ];

  Future<LocalCapabilitySnapshot> _snapshot(LocalCapability capability) async {
    var ready = await _quickPresent(capability);
    if (!ready && await _filesPresent(capability)) {
      // Existing installations from before the sidecar are adopted exactly
      // once. Subsequent startup checks use only identity and file lengths.
      ready = await verify(capability);
    }
    final model = capability == LocalCapability.transcription
        ? LocalModelIdentity(
            id: speech.id,
            version: speech.version,
            runtime: speech.engine,
            checksum: _speechChecksum,
          )
        : LocalModelIdentity(
            id: writing.id,
            version: writing.file,
            runtime: writing.runtime,
            checksum: writing.sha256,
          );
    return LocalCapabilitySnapshot(
      capability: capability,
      model: model,
      status: ready
          ? LocalCapabilityStatus.ready
          : LocalCapabilityStatus.missing,
    );
  }

  String get _speechChecksum {
    final entries = speech.files.map((f) => '${f.name}:${f.sha256}').toList()
      ..sort();
    return entries.join('|');
  }

  Future<bool> _quickPresent(LocalCapability capability) async {
    final registration = _registrationFile(capability);
    final identity = _identity(capability);
    if (!await registration.exists()) return false;
    try {
      final saved = jsonDecode(await registration.readAsString());
      final savedIdentity = saved is Map ? saved['identity'] : null;
      if (savedIdentity is! Map ||
          savedIdentity.length != identity.length ||
          identity.entries.any(
            (entry) => savedIdentity[entry.key] != entry.value,
          )) {
        return false;
      }
    } on FormatException {
      return false;
    }
    return _filesPresent(capability);
  }

  Map<String, Object?> _identity(LocalCapability capability) => {
    'id': capability == LocalCapability.transcription ? speech.id : writing.id,
    'version': capability == LocalCapability.transcription
        ? speech.version
        : writing.fileName,
    'sha256': capability == LocalCapability.transcription
        ? _speechChecksum
        : writing.sha256,
    'path': capability == LocalCapability.transcription
        ? speechDirectory.path
        : writingDirectory.path,
  };

  File _registrationFile(LocalCapability capability) {
    final directory = capability == LocalCapability.transcription
        ? speechDirectory
        : writingDirectory;
    return File(
      '${directory.path}${Platform.pathSeparator}.verified-model.json',
    );
  }

  Future<void> _saveRegistration(LocalCapability capability) async {
    final file = _registrationFile(capability);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(
      jsonEncode({'identity': _identity(capability)}),
    );
    await temporary.rename(file.path);
  }

  Future<bool> _filesPresent(LocalCapability capability) async {
    if (capability == LocalCapability.transcription) {
      if (!speech.isUsable || speech.files.isEmpty) return false;
      for (final part in speech.files) {
        final file = File(
          '${speechDirectory.path}${Platform.pathSeparator}${part.name}',
        );
        if (!await file.exists() ||
            (part.bytes > 0 && await file.length() != part.bytes)) {
          return false;
        }
      }
      return true;
    }
    if (!writing.isUsable) return false;
    final file = File(
      '${writingDirectory.path}${Platform.pathSeparator}${writing.fileName}',
    );
    return await file.exists() &&
        (writing.bytes <= 0 || await file.length() == writing.bytes);
  }

  @override
  Future<bool> verify(LocalCapability capability) async {
    _claim(capability);
    try {
      return await _verify(capability);
    } finally {
      _busy.remove(capability);
    }
  }

  Future<bool> _verify(LocalCapability capability) async {
    final valid = capability == LocalCapability.transcription
        ? await speechInstaller.isInstalled(speech, speechDirectory)
        : await writingInstaller.isInstalled(writing, writingDirectory);
    if (valid) {
      await _saveRegistration(capability);
    } else {
      final registration = _registrationFile(capability);
      if (await registration.exists()) await registration.delete();
    }
    return valid;
  }

  @override
  Stream<LocalModelProgress> install(LocalCapability capability) =>
      Stream<LocalModelProgress>.multi((controller) async {
        try {
          _claim(capability);
        } on StateError catch (error, stack) {
          controller.addError(error, stack);
          controller.close();
          return;
        }
        void emit(LocalModelProgress progress) => controller.addSync(progress);
        try {
          if (await _quickPresent(capability)) {
            emit(
              LocalModelProgress(
                capability: capability,
                status: LocalCapabilityStatus.ready,
                stage: LocalModelProgressStage.verifying,
                fraction: 1,
              ),
            );
            return;
          }
          emit(
            LocalModelProgress(
              capability: capability,
              status: LocalCapabilityStatus.installing,
              stage: LocalModelProgressStage.preparing,
            ),
          );
          try {
            if (capability == LocalCapability.transcription) {
              await speechInstaller.install(
                speech,
                speechDirectory,
                onProgress: (p) => emit(
                  LocalModelProgress(
                    capability: capability,
                    status: LocalCapabilityStatus.installing,
                    stage: _stage(p.stage),
                    fraction: p.fraction,
                    receivedBytes: p.received,
                    totalBytes: p.total > 0 ? p.total : null,
                  ),
                ),
              );
            } else {
              await writingInstaller.install(
                writing,
                writingDirectory,
                onProgress: (p) => emit(
                  LocalModelProgress(
                    capability: capability,
                    status: LocalCapabilityStatus.installing,
                    stage: _stage(p.stage),
                    fraction: p.fraction,
                    receivedBytes: p.received,
                    totalBytes: p.total > 0 ? p.total : null,
                  ),
                ),
              );
            }
            if (!await _verify(capability)) {
              throw const FormatException(
                'La verificación del modelo instalado falló.',
              );
            }
            emit(
              LocalModelProgress(
                capability: capability,
                status: LocalCapabilityStatus.ready,
                stage: LocalModelProgressStage.installing,
                fraction: 1,
              ),
            );
          } catch (error, stack) {
            emit(
              LocalModelProgress(
                capability: capability,
                status: LocalCapabilityStatus.failed,
                stage: LocalModelProgressStage.installing,
              ),
            );
            controller.addError(error, stack);
          }
        } finally {
          _busy.remove(capability);
          controller.close();
        }
      });

  LocalModelProgressStage _stage(String value) => switch (value) {
    'descargando' => LocalModelProgressStage.downloading,
    'verificando' => LocalModelProgressStage.verifying,
    'descomprimiendo' || 'extrayendo' => LocalModelProgressStage.extracting,
    _ => LocalModelProgressStage.installing,
  };

  @override
  Future<void> clean(LocalCapability capability) async {
    _claim(capability);
    try {
      if (capability == LocalCapability.transcription) {
        for (final part in speech.files) {
          final file = File(
            '${speechDirectory.path}${Platform.pathSeparator}${part.name}',
          );
          if (await file.exists()) await file.delete();
        }
        await _deleteTemporary(
          File(
            '${speechDirectory.path}${Platform.pathSeparator}${speech.id}.tar.bz2',
          ),
        );
        await _deleteTemporary(
          File(
            '${speechDirectory.path}${Platform.pathSeparator}${speech.id}.tar.bz2.tar',
          ),
        );
      } else {
        await writingInstaller.remove(writing, writingDirectory);
        await _deleteTemporary(
          File(
            '${writingDirectory.path}${Platform.pathSeparator}${writing.fileName}.part',
          ),
        );
      }
      final registration = _registrationFile(capability);
      if (await registration.exists()) await registration.delete();
    } finally {
      _busy.remove(capability);
    }
  }

  void _claim(LocalCapability capability) {
    if (!_busy.add(capability)) {
      throw StateError('Ya existe una operación para este modelo.');
    }
  }

  Future<void> _deleteTemporary(File file) async {
    if (await file.exists()) await file.delete();
  }
}
