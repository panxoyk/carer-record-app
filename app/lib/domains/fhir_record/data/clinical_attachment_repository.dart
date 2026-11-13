import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/authorized_clinical_record.dart';

/// Maximum photo size accepted by the gateway (ADR-022).
const maxClinicalPhotoBytes = 5000000;

/// Clinical photos stored in the FHIR server through the gateway. The app
/// never talks to HAPI: both directions go through authorized Edge Functions.
abstract interface class ClinicalAttachmentRepository {
  /// Attaches [bytes] to the open episode, linked to the context note
  /// [clientEventId]. Returns the FHIR document id.
  Future<String> upload({
    required String organizationId,
    required String hospitalizationId,
    required String clientEventId,
    required String contentType,
    required Uint8List bytes,
    required DateTime takenAt,
  });

  Future<ClinicalPhoto> download({
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
    required DateTime takenAt,
  }) async {
    if (!const {'image/jpeg', 'image/png'}.contains(contentType)) {
      throw const ClinicalAttachmentException('Formato de foto no admitido.');
    }
    if (bytes.isEmpty || bytes.length > maxClinicalPhotoBytes) {
      throw const ClinicalAttachmentException('La foto supera los 5 MB.');
    }
    final FunctionResponse response;
    try {
      response = await _client.functions.invoke(
        'clinical-attachment',
        body: {
          'organizationId': organizationId,
          'hospitalizationId': hospitalizationId,
          'clientEventId': clientEventId,
          'contentType': contentType,
          'dataBase64': base64Encode(bytes),
          'takenAt': _instant(takenAt),
        },
      );
    } on FunctionException catch (error) {
      if (error.status == 401 || error.status == 404) {
        throw const ClinicalAuthorizationLost(404);
      }
      throw const ClinicalAttachmentException('No se pudo adjuntar la foto.');
    }
    final data = response.data;
    final id = data is Map ? data['id'] : null;
    if (id is! String || !RegExp(r'^[A-Za-z0-9.-]{1,64}$').hasMatch(id)) {
      throw const FormatException('Invalid attachment response');
    }
    return id;
  }

  @override
  Future<ClinicalPhoto> download({
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

/// RFC 3339 UTC instant without microseconds, as the gateway expects.
String _instant(DateTime value) {
  final utc = value.toUtc();
  return '${utc.toIso8601String().split('.').first}Z';
}
