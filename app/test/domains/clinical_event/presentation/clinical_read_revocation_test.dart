import 'package:carer_record_app/domains/auth/presentation/auth_providers.dart';
import 'package:carer_record_app/domains/clinical_event/data/clinical_read_client.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_event_providers.dart';
import 'package:carer_record_app/domains/clinical_event/presentation/clinical_read_providers.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:carer_record_app/domains/institutional/presentation/iam_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_providers.dart';
import 'package:carer_record_app/domains/patient/presentation/patient_screens.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const organizationA = '00000000-0000-4000-8000-000000000001';
const organizationB = '00000000-0000-4000-8000-000000000009';
const episodeId = '00000000-0000-4000-8000-000000000002';

void main() {
  test(
    'same episode ID on organization change rereads and never reuses tenant data',
    () async {
      var currentContext = _context(organizationA, {
        'clinical.census.read',
        'clinical.patient.read',
      });
      final fake = TenantClinicalReadClient();
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => _session),
          iamContextProvider.overrideWith((ref) async => currentContext),
          clinicalReadClientProvider.overrideWith((ref) => fake),
        ],
      );
      addTearDown(container.dispose);
      final subscription = container.listen(
        patientProvider(episodeId),
        (_, __) {},
      );
      addTearDown(subscription.close);
      expect(
        (await container.read(patientProvider(episodeId).future))?.fullName,
        'Tenant A Synthetic',
      );

      currentContext = _context(organizationB, {
        'clinical.census.read',
        'clinical.patient.read',
      });
      container.invalidate(iamContextProvider);
      expect(container.read(patientProvider(episodeId)).isLoading, isTrue);
      expect(
        (await container.read(patientProvider(episodeId).future))?.fullName,
        'Tenant B Synthetic',
      );
      expect(fake.organizationReads, [
        organizationA,
        organizationA,
        organizationB,
        organizationB,
      ]);
    },
  );

  testWidgets(
    'manipulated hospitalization path is neutral and performs no query',
    (tester) async {
      final fake = TenantClinicalReadClient();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sessionProvider.overrideWith((ref) => _session),
            iamContextProvider.overrideWith(
              (ref) async => _context(organizationA, {
                'clinical.census.read',
                'clinical.patient.read',
                'clinical.timeline.read',
              }),
            ),
            clinicalReadClientProvider.overrideWith((ref) => fake),
          ],
          child: const MaterialApp(
            home: PatientDetailScreen(hospitalizationId: 'malformed'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Paciente no encontrado.'), findsOneWidget);
      expect(fake.organizationReads, isEmpty);
    },
  );

  test(
    'timeline permission revocation replaces ready summary with empty',
    () async {
      var currentContext = _context(organizationA, {
        'clinical.census.read',
        'clinical.patient.read',
        'clinical.timeline.read',
      });
      final fake = TenantClinicalReadClient()..includeTimeline = true;
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => _session),
          iamContextProvider.overrideWith((ref) async => currentContext),
          clinicalReadClientProvider.overrideWith((ref) => fake),
        ],
      );
      addTearDown(container.dispose);
      final provider = hospitalizationClinicalEventsProvider(episodeId);
      final subscription = container.listen(provider, (_, __) {});
      addTearDown(subscription.close);
      expect(
        (await container.read(provider.future)).single.summary,
        'Previously authorized summary',
      );

      currentContext = _context(organizationA, {
        'clinical.census.read',
        'clinical.patient.read',
      });
      container.invalidate(iamContextProvider);
      expect(container.read(provider).isLoading, isTrue);
      expect(await container.read(provider.future), isEmpty);
      expect(container.read(provider).valueOrNull, isEmpty);
    },
  );

  test(
    'patient permission revocation replaces ready demographics with not-found',
    () async {
      var currentContext = _context(organizationA, {
        'clinical.census.read',
        'clinical.patient.read',
      });
      final container = ProviderContainer(
        overrides: [
          sessionProvider.overrideWith((ref) => _session),
          iamContextProvider.overrideWith((ref) async => currentContext),
          clinicalReadClientProvider.overrideWith(
            (ref) => TenantClinicalReadClient(),
          ),
        ],
      );
      addTearDown(container.dispose);
      final provider = patientProvider(episodeId);
      final subscription = container.listen(provider, (_, __) {});
      addTearDown(subscription.close);
      expect(
        (await container.read(provider.future))?.fullName,
        'Tenant A Synthetic',
      );

      currentContext = _context(organizationA, {'clinical.census.read'});
      container.invalidate(iamContextProvider);
      expect(container.read(provider).isLoading, isTrue);
      expect(await container.read(provider.future), isNull);
      expect(container.read(provider).valueOrNull, isNull);
    },
  );
}

final _session = Session.fromJson({
  'access_token': 'synthetic-token',
  'token_type': 'bearer',
  'user': {
    'id': '00000000-0000-4000-8000-000000000020',
    'aud': 'authenticated',
    'role': 'authenticated',
    'app_metadata': <String, dynamic>{},
    'user_metadata': <String, dynamic>{},
    'created_at': '2026-01-01T00:00:00Z',
  },
});

IamContext _context(String organizationId, Set<String> permissions) =>
    IamContext(
      organizationId: organizationId,
      organizationName: 'Synthetic organization',
      profileId: '00000000-0000-4000-8000-000000000021',
      displayName: 'Synthetic user',
      profileStatus: 'active',
      membershipId: '00000000-0000-4000-8000-000000000022',
      membershipStatus: 'active',
      permissions: permissions,
    );

class TenantClinicalReadClient implements ClinicalReadClient {
  final organizationReads = <String>[];
  bool includeTimeline = false;

  @override
  Future<List<Map<String, dynamic>>> execute(ClinicalReadQuery query) async {
    organizationReads.add(query.organizationId);
    final name =
        query.organizationId == organizationA ? 'Tenant A' : 'Tenant B';
    if (query.view == ClinicalReadView.census) {
      return [_census(query.organizationId, name)];
    }
    if (query.view == ClinicalReadView.demographics) {
      return [_demographics(query.organizationId, name)];
    }
    if (includeTimeline) return [_timeline(query.organizationId)];
    return const [];
  }
}

Map<String, dynamic> _census(String organizationId, String name) => {
  'organization_id': organizationId,
  'hospitalization_id': episodeId,
  'patient_id': '00000000-0000-4000-8000-000000000003',
  'hospitalization_status': 'active',
  'admitted_at': '2026-01-01T00:00:00Z',
  'discharged_at': null,
  'unit_id': '00000000-0000-4000-8000-000000000030',
  'bed_label': '12',
  'given_name': name,
  'family_name': '',
  'birth_date': null,
};

Map<String, dynamic> _demographics(String organizationId, String name) => {
  'organization_id': organizationId,
  'hospitalization_id': episodeId,
  'patient_id': '00000000-0000-4000-8000-000000000003',
  'given_name': name,
  'family_name': 'Synthetic',
  'birth_date': null,
};

Map<String, dynamic> _timeline(String organizationId) => {
  'organization_id': organizationId,
  'hospitalization_id': episodeId,
  'event_id': '00000000-0000-4000-8000-000000000040',
  'kind': 'observation',
  'occurred_at': '2026-01-01T00:00:00Z',
  'summary': 'Previously authorized summary',
  'patient_id': '00000000-0000-4000-8000-000000000003',
  'created_at': '2026-01-01T00:00:00Z',
};
