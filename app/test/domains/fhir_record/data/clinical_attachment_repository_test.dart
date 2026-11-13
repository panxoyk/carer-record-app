// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:typed_data';

import 'package:carer_record_app/domains/fhir_record/data/clinical_attachment_repository.dart';
import 'package:carer_record_app/domains/fhir_record/domain/authorized_clinical_record.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _org = '67ec8000-a79b-4e0a-af97-2e67b69db608';
const _episode = '0848f2fd-3997-5fc2-b0ef-e0655a91bff8';
const _event = '32f1a239-47ed-4e62-8368-99540a2347bf';
final _jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

SupabaseClient _client(
  List<http.BaseRequest> requests,
  http.Response Function(http.BaseRequest request) reply,
) => SupabaseClient(
  'http://synthetic.test',
  'synthetic-key',
  authOptions: const AuthClientOptions(autoRefreshToken: false),
  httpClient: MockClient((request) async {
    requests.add(request);
    return reply(request);
  }),
);

http.Response _json(Object body, int status, http.BaseRequest request) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request as http.Request,
    );

void main() {
  test('photo path is fixed per note and content type', () {
    expect(
      clinicalPhotoPath(
        organizationId: _org,
        hospitalizationId: _episode,
        clientEventId: _event,
        contentType: 'image/png',
      ),
      '$_org/$_episode/$_event.png',
    );
    expect(
      () => clinicalPhotoPath(
        organizationId: _org,
        hospitalizationId: _episode,
        clientEventId: _event,
        contentType: 'image/gif',
      ),
      throwsA(isA<ClinicalAttachmentException>()),
    );
  });

  test(
    'upload stores the photo in the private bucket without upsert',
    () async {
      final requests = <http.BaseRequest>[];
      final repository = SupabaseClinicalAttachmentRepository(
        _client(
          requests,
          (request) => _json({'Key': 'clinical-photos/x'}, 200, request),
        ),
      );
      final path = await repository.upload(
        organizationId: _org,
        hospitalizationId: _episode,
        clientEventId: _event,
        contentType: 'image/jpeg',
        bytes: _jpeg,
      );
      expect(path, '$_org/$_episode/$_event.jpg');
      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.path,
        '/storage/v1/object/clinical-photos/$_org/$_episode/$_event.jpg',
      );
      expect(request.headers['x-upsert'], 'false');
      expect(request.url.toString(), isNot(contains('functions')));
    },
  );

  test('a duplicate after a lost response counts as uploaded', () async {
    final repository = SupabaseClinicalAttachmentRepository(
      _client(
        [],
        (request) => _json(
          {
            'statusCode': '409',
            'error': 'Duplicate',
            'message': 'The resource already exists',
          },
          400,
          request,
        ),
      ),
    );
    expect(
      await repository.upload(
        organizationId: _org,
        hospitalizationId: _episode,
        clientEventId: _event,
        contentType: 'image/jpeg',
        bytes: _jpeg,
      ),
      '$_org/$_episode/$_event.jpg',
    );
  });

  test('upload rejected by storage RLS reports a retryable failure', () async {
    final repository = SupabaseClinicalAttachmentRepository(
      _client(
        [],
        (request) => _json(
          {
            'statusCode': '403',
            'error': 'Unauthorized',
            'message': 'new row violates row-level security policy',
          },
          400,
          request,
        ),
      ),
    );
    expect(
      repository.upload(
        organizationId: _org,
        hospitalizationId: _episode,
        clientEventId: _event,
        contentType: 'image/jpeg',
        bytes: _jpeg,
      ),
      throwsA(isA<ClinicalAttachmentException>()),
    );
  });

  test('upload validates size before any request', () async {
    final requests = <http.BaseRequest>[];
    final repository = SupabaseClinicalAttachmentRepository(
      _client(requests, (request) => _json({}, 200, request)),
    );
    await expectLater(
      repository.upload(
        organizationId: _org,
        hospitalizationId: _episode,
        clientEventId: _event,
        contentType: 'image/jpeg',
        bytes: Uint8List(maxClinicalPhotoBytes + 1),
      ),
      throwsA(isA<ClinicalAttachmentException>()),
    );
    expect(requests, isEmpty);
  });

  test(
    'stored photo downloads from the private bucket with the session',
    () async {
      final requests = <http.BaseRequest>[];
      final repository = SupabaseClinicalAttachmentRepository(
        _client(
          requests,
          (request) =>
              http.Response.bytes(_jpeg, 200, request: request as http.Request),
        ),
      );
      final photo = await repository.downloadStored(
        '$_org/$_episode/$_event.jpg',
      );
      expect(photo.contentType, 'image/jpeg');
      expect(photo.bytes, _jpeg);
      expect(
        requests.single.url.path,
        '/storage/v1/object/clinical-photos/$_org/$_episode/$_event.jpg',
      );
    },
  );

  test('unreadable stored photo is treated as unavailable', () async {
    final repository = SupabaseClinicalAttachmentRepository(
      _client(
        [],
        (request) => _json(
          {
            'statusCode': '404',
            'error': 'not_found',
            'message': 'Object not found',
          },
          400,
          request,
        ),
      ),
    );
    expect(
      repository.downloadStored('$_org/$_episode/$_event.jpg'),
      throwsA(isA<ClinicalAuthorizationLost>()),
    );
  });
}
