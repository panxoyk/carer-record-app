import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:http/http.dart' as http;

import '../domain/fhir_record_entities.dart';

/// URL base del servidor HAPI FHIR, inyectada con --dart-define.
/// Android Emulator -> host Windows: http://10.0.2.2:8080/fhir
const fhirBaseUrl = String.fromEnvironment(
  'FHIR_BASE_URL',
  defaultValue: 'http://10.0.2.2:8080/fhir',
);

/// Cliente mínimo de lectura. Devuelve JSON FHIR crudo; el mapeo al modelo
/// interno ocurre en FhirMapper (frontera anticorrupción).
class FhirClient {
  FhirClient({
    String baseUrl = fhirBaseUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _base = Uri.parse(
         baseUrl.endsWith('/')
             ? baseUrl.substring(0, baseUrl.length - 1)
             : baseUrl,
       ),
       _http = httpClient ?? http.Client();

  final Uri _base;
  final http.Client _http;
  final Duration timeout;

  static const _headers = {'Accept': 'application/fhir+json'};

  Future<Map<String, dynamic>> _getJson(Uri uri, {Duration? timeout}) async {
    try {
      final res = await _http
          .get(uri, headers: _headers)
          .timeout(timeout ?? this.timeout);
      if (res.statusCode != 200) {
        throw FhirException('El servidor FHIR respondió ${res.statusCode}.');
      }
      return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on TimeoutException {
      developer.log('GET $uri superó el tiempo de espera', name: 'FhirClient');
      throw const FhirException('El servidor FHIR no respondió a tiempo.');
    } on FhirException {
      rethrow;
    } catch (e, st) {
      // El detalle real queda en la consola de `flutter run`.
      developer.log(
        'GET $uri falló',
        name: 'FhirClient',
        error: e,
        stackTrace: st,
      );
      throw FhirException(
        'No se pudo conectar con el servidor FHIR (${e.runtimeType}).',
      );
    }
  }

  Uri _resource(String path, [Map<String, dynamic>? query]) => _base.replace(
    pathSegments: [..._base.pathSegments, ...path.split('/')],
    queryParameters: query,
  );

  /// Cambia solo el origen de un link `next` del servidor: HAPI puede
  /// devolver http://localhost:8080 que el emulador no alcanza.
  Uri _rebase(String link) {
    final u = Uri.parse(link);
    return u.replace(scheme: _base.scheme, host: _base.host, port: _base.port);
  }

  /// Busca pacientes por nombre (prefijo de nombre o apellido) o identificador.
  Future<List<Map<String, dynamic>>> searchPatients(
    String query, {
    int count = 20,
  }) async {
    final q = query.trim();
    // UUID (MRN de Synthea) o número con guiones (SSN, RUN): se busca por
    // identificador; cualquier otra cosa se trata como nombre.
    final isIdentifier = RegExp(
      r'^([0-9a-fA-F]{8}-[0-9a-fA-F-]*|\d[\d.\-]{4,}[\dkK]?)$',
    ).hasMatch(q);
    // Cada palabra va como un parámetro `name` repetido (AND): "Angel Upton"
    // encuentra a Angel97 Upton904. Un solo parámetro con espacio no coincide.
    final tokens = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final bundle = await _getJson(
      _resource('Patient', {
        if (isIdentifier) 'identifier': q else 'name': tokens,
        '_count': '$count',
      }),
    );
    return _entries(bundle);
  }

  /// La primera página de $everything es lenta en HAPI: calcula toda la
  /// compartment del paciente. Las siguientes salen de caché.
  static const everythingTimeout = Duration(seconds: 180);

  /// Ficha completa vía Patient/{id}/$everything, siguiendo la paginación.
  Future<({List<Map<String, dynamic>> resources, bool truncated})> everything(
    String patientId, {
    int pageSize = 200,
    int maxPages = 60,
  }) async {
    final resources = <Map<String, dynamic>>[];
    var uri = _resource('Patient/$patientId/\$everything', {
      '_count': '$pageSize',
    });
    for (var page = 0; page < maxPages; page++) {
      final watch = Stopwatch()..start();
      final bundle = await _getJson(uri, timeout: everythingTimeout);
      final entries = _entries(bundle);
      resources.addAll(entries);
      developer.log(
        'página ${page + 1}: ${entries.length} recursos en '
        '${watch.elapsedMilliseconds} ms (acumulado ${resources.length})',
        name: 'FhirClient',
      );
      final next = _nextLink(bundle);
      if (next == null) return (resources: resources, truncated: false);
      uri = _rebase(next);
    }
    return (resources: resources, truncated: true);
  }

  List<Map<String, dynamic>> _entries(Map<String, dynamic> bundle) {
    final entries = (bundle['entry'] as List?) ?? const [];
    return [
      for (final e in entries)
        if ((e as Map)['resource'] is Map)
          Map<String, dynamic>.from(e['resource'] as Map),
    ];
  }

  String? _nextLink(Map<String, dynamic> bundle) {
    for (final l in (bundle['link'] as List?) ?? const []) {
      if (l is Map && l['relation'] == 'next') return l['url'] as String?;
    }
    return null;
  }

  void close() => _http.close();
}
