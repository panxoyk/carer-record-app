import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/authorized_clinical_record.dart';

/// Maximum photo size accepted for clinical photos (ADR-024).
const maxClinicalPhotoBytes = 5000000;

/// Private Supabase Storage bucket for photos taken in the app (ADR-024).
const clinicalPhotosBucket = 'clinical-photos';

/// Where a clinical photo lives: taken in the app (Supabase Storage) or
/// provided by the clinical system (FHIR, read only through the gateway).
enum ClinicalPhotoOrigin { storage, fhir }

/// Identifies one photo of an episode. [reference] is the Storage object path
/// for [ClinicalPhotoOrigin.storage] or the FHIR document id otherwise.
typedef ClinicalPhotoRef = ({
  String hospitalizationId,
  String reference,
  ClinicalPhotoOrigin origin,
});

/// Fixed object path: `<organization>/<hospitalization>/<client event>.ext`.
/// Storage RLS only accepts it for a confirmed note of the uploader.
String clinicalPhotoPath({
  required String organizationId,
  required String hospitalizationId,
  required String clientEventId,
  required String contentType,
}) {
  final extension = switch (contentType) {
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    _ => throw const ClinicalAttachmentException(
      'Formato de foto no admitido.',
    ),
  };
  return '$organizationId/$hospitalizationId/$clientEventId.$extension';
}

abstract interface class ClinicalAttachmentRepository {
  /// Stores [bytes] as the photo of the context note [clientEventId]. Returns
  /// the object path. Retrying after a lost response is safe.
  Future<String> upload({
    required String organizationId,
    required String hospitalizationId,
    required String clientEventId,
    required String contentType,
    required Uint8List bytes,
  });

  /// Downloads a photo taken in the app from Supabase Storage.
  Future<ClinicalPhoto> downloadStored(String path);

  /// Downloads a photo of the clinical system through the FHIR gateway.
  Future<ClinicalPhoto> downloadFhir({
    required String organizationId,
    required String hospitalizationId,
    required String documentId,
  });
}

class ClinicalAttachmentException implements Exception {
  const ClinicalAttachmentException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SupabaseClinicalAttachmentRepository
    implements ClinicalAttachmentRepository {
  SupabaseClinicalAttachmentRepository(this._client);
  final SupabaseClient _client;

  @override
  Future<String> upload({
    required String organizationId,
    required String hospitalizationId,
    required String clientEventId,
    required String contentType,
    required Uint8List bytes,
  }) async {
    final path = clinicalPhotoPath(
      organizationId: organizationId,
      hospitalizationId: hospitalizationId,
      clientEventId: clientEventId,
      contentType: contentType,
    );
    if (bytes.isEmpty || bytes.length > maxClinicalPhotoBytes) {
      throw const ClinicalAttachmentException('La foto supera los 5 MB.');
    }
    try {
      await _client.storage
          .from(clinicalPhotosBucket)
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: contentType),
          );
    } on StorageException catch (error) {
      // The photo already exists: a previous attempt succeeded but its
      // response was lost. Photos are immutable, so it is the same photo.
      if (isDuplicateStorageObject(error)) return path;
      throw const ClinicalAttachmentException('No se pudo adjuntar la foto.');
    }
    return path;
  }

  @override
  Future<ClinicalPhoto> downloadStored(String path) async {
    final contentType = switch (path.split('.').last) {
      'jpg' => 'image/jpeg',
      'png' => 'image/png',
      _ => throw const FormatException('Invalid photo path'),
    };
    final Uint8List bytes;
    try {
      bytes = await _client.storage.from(clinicalPhotosBucket).download(path);
    } on StorageException {
      // Missing or not readable: same answer, never reveal which.
      throw const ClinicalAuthorizationLost(404);
    }
    if (bytes.isEmpty || bytes.length > maxClinicalPhotoBytes) {
      throw const FormatException('Invalid photo size');
    }
    return ClinicalPhoto(contentType: contentType, bytes: bytes);
  }

  @override
  Future<ClinicalPhoto> downloadFhir({
    required String organizationId,
    required String hospitalizationId,
    required String documentId,
  }) async {
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'clinical-record',
        body: {
          'organizationId': organizationId,
          'hospitalizationId': hospitalizationId,
          'purpose': 'attachment',
          'documentId': documentId,
        },
      );
    } on FunctionException catch (error) {
      if (error.status == 401 || error.status == 403 || error.status == 404) {
        throw ClinicalAuthorizationLost(error.status);
      }
      rethrow;
    }
    final data = response.data;
    if (data is! Map) throw const FormatException('Invalid photo response');
    final contentType = data['contentType'];
    final encoded = data['dataBase64'];
    if (!const {'image/jpeg', 'image/png'}.contains(contentType) ||
        encoded is! String) {
      throw const FormatException('Invalid photo response');
    }
    final bytes = base64Decode(encoded);
    if (bytes.length > maxClinicalPhotoBytes) {
      throw const FormatException('Photo too large');
    }
    return ClinicalPhoto(contentType: contentType as String, bytes: bytes);
  }
}

/// Storage answers an existing object with 409 or a "Duplicate" error.
bool isDuplicateStorageObject(StorageException error) =>
    error.statusCode == '409' ||
    error.error == 'Duplicate' ||
    error.message.toLowerCase().contains('already exists');
