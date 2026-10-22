Write-Host "Redirigiendo puertos ADB..." -ForegroundColor Cyan
adb reverse tcp:54321 tcp:54321
adb reverse tcp:8080 tcp:8080
adb reverse --list

Write-Host "Iniciando la app en el dispositivo..." -ForegroundColor Green
fvm flutter run -d ZY22H9DL4R --dart-define=SUPABASE_URL=http://127.0.0.1:54321 --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_ACJWlzQHlZjBrEguHvfOxg_3BJgxAaH --dart-define=FHIR_BASE_URL=http://127.0.0.1:8080/fhir