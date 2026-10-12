import 'package:carer_record_app/core/time/clinical_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatClinicalDateTime', () {
    test('converts UTC instants to the demo institution time zone', () {
      expect(
        formatClinicalDateTime(DateTime.utc(2024, 7, 1, 3, 30)),
        '30-06-2024 · 23:30',
      );
    });

    test('uses the applicable offset on each side of a DST transition', () {
      expect(
        formatClinicalDateTime(DateTime.utc(2024, 4, 7, 2, 30)),
        '06-04-2024 · 23:30',
      );
      expect(
        formatClinicalDateTime(DateTime.utc(2024, 4, 7, 4, 30)),
        '07-04-2024 · 00:30',
      );
    });
  });

  group('formatClinicalDate', () {
    test('keeps a date without time as its original calendar date', () {
      expect(formatClinicalDate(DateTime.parse('1984-05-16')), '16-05-1984');
    });

    test('returns the absent-value label when the date is unavailable', () {
      expect(formatClinicalDate(null), 'No registrada');
    });
  });

  group('formatAssignmentTimeRange', () {
    final assignedAt = DateTime.utc(2024, 7, 1, 3, 30);

    test('formats a non-ended assignment in the institution time zone', () {
      expect(
        formatAssignmentTimeRange(
          validFrom: assignedAt,
          now: DateTime.utc(2024, 7, 2),
        ),
        'Asignado el 30-06-2024 · 23:30',
      );
    });

    test('formats revoked and ended assignments as ranges', () {
      expect(
        formatAssignmentTimeRange(
          validFrom: assignedAt,
          revokedAt: DateTime.utc(2024, 7, 2, 3, 30),
        ),
        'Revocado · 30-06-2024 · 23:30 → 01-07-2024 · 23:30',
      );
      expect(
        formatAssignmentTimeRange(
          validFrom: assignedAt,
          validUntil: DateTime.utc(2024, 7, 2, 3, 30),
          now: DateTime.utc(2024, 7, 3),
        ),
        'Finalizada · 30-06-2024 · 23:30 → 01-07-2024 · 23:30',
      );
    });
  });
}
