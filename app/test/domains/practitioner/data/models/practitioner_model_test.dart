import 'package:carer_record_app/domains/practitioner/data/models/practitioner_model.dart';
import 'package:carer_record_app/domains/practitioner/domain/entities/practitioner.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps database enum values to practitioner enums', () {
    final practitioner = PractitionerModel.fromJson({
      'id': 'practitioner-id',
      'display_name': 'Test Practitioner',
      'role': 'nurse',
      'status': 'suspended',
    });

    expect(practitioner.role, PractitionerRole.nurse);
    expect(practitioner.status, PractitionerStatus.suspended);
  });
}
