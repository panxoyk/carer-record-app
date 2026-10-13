import 'package:carer_record_app/core/router/app_router.dart';
import 'package:carer_record_app/core/router/administration_navigation.dart';
import 'package:carer_record_app/domains/institutional/data/iam_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manually entered administration routes redirect without effective permissions', () {
    final clinician = _context({
      'clinical.census.read',
      'clinical.patient.read',
    });
    expect(permissionRedirectForLocation(clinician, '/users'), '/settings');
    expect(
      permissionRedirectForLocation(clinician, '/assignments'),
      '/settings',
    );
    expect(permissionRedirectForLocation(clinician, '/patients'), isNull);
    expect(
      permissionRedirectForLocation(
        _context({'clinical.census.read'}),
        '/patients',
      ),
      '/settings',
    );
    expect(
      permissionRedirectForLocation(clinician, '/hospitalizations/fabricated'),
      '/settings',
    );
    expect(
      permissionRedirectForLocation(
        _context({
          'clinical.census.read',
          'clinical.patient.read',
          'clinical.timeline.read',
        }),
        '/hospitalizations/fabricated',
      ),
      isNull,
    );
    expect(
      permissionRedirectForLocation(
        clinician,
        '/hospitalizations/fabricated/details',
      ),
      isNull,
    );
    expect(
      permissionRedirectForLocation(
        _context({'clinical.census.read', 'clinical.patient.read'}),
        '/hospitalizations/fabricated',
      ),
      '/settings',
    );
  });

  test('effective IAM permissions determine institutional route access', () {
    final administrator = _context({
      'iam.membership.read',
      'clinical.assignment.manage',
      'clinical.census.read',
      'clinical.patient.read',
    });
    expect(permissionRedirectForLocation(administrator, '/users'), isNull);
    expect(
      permissionRedirectForLocation(administrator, '/assignments'),
      isNull,
    );
    expect(permissionRedirectForLocation(administrator, '/'), '/patients');
    expect(
      permissionRedirectForLocation(_context({'iam.membership.read'}), '/'),
      '/settings',
    );
  });

  test(
    'settings navigation offers only destinations allowed by IAM permissions',
    () {
      expect(
        administrationNavigationFor(_context({})).map((item) => item.location),
        isEmpty,
      );
      expect(
        administrationNavigationFor(
          _context({
            'iam.role.read',
            'iam.role.manage',
            'clinical.assignment.manage',
            'clinical.census.read',
            'clinical.patient.read',
          }),
        ).map((item) => item.location),
        ['/roles', '/assignments'],
      );
      expect(
        administrationNavigationFor(_context({'iam.role.read'}))
            .map((item) => item.location),
        isEmpty,
      );
    },
  );

  test(
    'roles requires both explicit IAM permissions, never display identity',
    () {
      final permitted = _context({'iam.role.read', 'iam.role.manage'});
      expect(permissionRedirectForLocation(permitted, '/roles'), isNull);
      expect(
        permissionRedirectForLocation(_context({'iam.role.read'}), '/roles'),
        '/settings',
      );
      expect(
        permissionRedirectForLocation(_context({'iam.role.manage'}), '/roles'),
        '/settings',
      );
      expect(
        permissionRedirectForLocation(_context({}), '/roles'),
        '/settings',
      );
      final apparentAdmin = IamContext(
        organizationId: 'org',
        organizationName: 'Synthetic organization',
        profileId: 'profile',
        displayName: 'Administrador',
        profileStatus: 'active',
        membershipId: 'membership',
        membershipStatus: 'active',
        permissions: const {},
      );
      expect(
        permissionRedirectForLocation(apparentAdmin, '/roles'),
        '/settings',
      );
    },
  );

  test('multiple organizations require selection and route permissions stay scoped', () {
    final hospitalAdmin = _context({
      'iam.membership.read',
    }, organizationId: 'org-a');
    final clinician = _context({
      'clinical.census.read',
      'clinical.patient.read',
    }, organizationId: 'org-b');
    final contexts = [hospitalAdmin, clinician];

    expect(
      organizationSelectionRedirect(contexts, null, 'user-1', '/patients'),
      '/select-organization',
    );
    expect(
      organizationSelectionRedirect(
        contexts,
        null,
        'user-1',
        '/select-organization',
      ),
      isNull,
    );
    const selection = OrganizationSelection(
      userId: 'user-1',
      organizationId: 'org-a',
    );
    final selected = contextForOrganizationSelection(
      contexts,
      selection,
      'user-1',
    );
    expect(selected?.organizationId, 'org-a');
    expect(permissionRedirectForLocation(selected!, '/patients'), '/settings');
    expect(
      organizationSelectionRedirect(
        contexts,
        selection,
        'other-user',
        '/patients',
      ),
      '/select-organization',
    );
    expect(
      organizationSelectionRedirect(contexts, selection, 'user-1', '/users'),
      isNull,
    );
  });
}

IamContext _context(Set<String> permissions, {String organizationId = 'org'}) =>
    IamContext(
      organizationId: organizationId,
      organizationName: 'Synthetic organization',
      profileId: 'profile',
      displayName: 'Synthetic user',
      profileStatus: 'active',
      membershipId: 'membership',
      membershipStatus: 'active',
      permissions: permissions,
    );
