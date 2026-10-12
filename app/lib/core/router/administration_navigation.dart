import '../../domains/institutional/data/iam_models.dart';

List<({String location, String label})> administrationNavigationFor(
  IamContext context,
) => [
  if (context.allows('iam.membership.read'))
    (location: '/users', label: 'Gestionar usuarios'),
  if (context.allows('iam.role.read') && context.allows('iam.role.manage'))
    (location: '/roles', label: 'Roles y permisos'),
  if (context.allows('clinical.assignment.manage'))
    (location: '/assignments', label: 'Asignaciones asistenciales'),
];
