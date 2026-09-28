import 'package:timezone/data/latest.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;

/// Zona horaria IANA de la institución de demostración.
const demoInstitutionTimeZone = 'America/Santiago';

var _timeZonesInitialized = false;

void initializeClinicalTimeZones() {
  if (_timeZonesInitialized) return;
  timezone_data.initializeTimeZones();
  _timeZonesInitialized = true;
}

String formatClinicalDate(DateTime? value) {
  if (value == null) return 'No registrada';
  return _formatDate(value);
}

String formatClinicalDateTime(DateTime value) {
  initializeClinicalTimeZones();
  final location = timezone.getLocation(demoInstitutionTimeZone);
  final localValue = timezone.TZDateTime.from(value.toUtc(), location);
  return '${_formatDate(localValue)} · ${_twoDigits(localValue.hour)}:${_twoDigits(localValue.minute)}';
}

String _formatDate(DateTime value) =>
    '${_twoDigits(value.day)}-${_twoDigits(value.month)}-${value.year}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');
