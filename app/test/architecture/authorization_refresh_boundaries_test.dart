import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Analyze Dart import/export edges after resolving relative and package URIs.
// Keep the checks scoped to B's boundaries; this is not a global layering
// or acyclicity rule.
final _directive = RegExp(r'''(?:import|export)\s+['"]([^'"]+)['"]''');
final _lib = Directory('lib').absolute;

List<File> _dartFiles(Directory directory) => directory
    .listSync(recursive: true)
    .whereType<File>()
    .where((file) => file.path.endsWith('.dart'))
    .toList();

List<Uri> _directives(File file) => _directive
    .allMatches(file.readAsStringSync())
    .map((match) => Uri.parse(match.group(1)!))
    .toList();

File? _resolve(File source, Uri uri) {
  if (uri.scheme == 'package' && uri.pathSegments.first == 'carer_record_app') {
    return File.fromUri(_lib.uri.resolve(uri.pathSegments.skip(1).join('/')));
  }
  if (!uri.hasScheme && uri.path.isNotEmpty) {
    return File.fromUri(source.absolute.uri.resolveUri(uri));
  }
  return null;
}

String _path(File file) => Uri.file(file.absolute.path).normalizePath().path;

bool _within(File file, String fragment) => _path(file).contains(fragment);

Set<File> _reachable(File start) {
  final visited = <String>{};
  final pending = <File>[start];
  while (pending.isNotEmpty) {
    final file = pending.removeLast();
    final path = _path(file);
    if (!visited.add(path) || !file.existsSync()) continue;
    for (final uri in _directives(file)) {
      final target = _resolve(file, uri);
      if (target != null && target.absolute.path.startsWith(_lib.path)) {
        pending.add(target);
      }
    }
  }
  return visited.map(File.new).toSet();
}

void main() {
  test('import resolver resolves sibling, parent and package URIs', () {
    final source = File('lib/domains/institutional/presentation/iam.dart');
    expect(
      _path(_resolve(source, Uri.parse('local_facade.dart'))!),
      endsWith('/lib/domains/institutional/presentation/local_facade.dart'),
    );
    expect(
      _path(_resolve(source, Uri.parse('../domain/iam_entities.dart'))!),
      endsWith('/lib/domains/institutional/domain/iam_entities.dart'),
    );
    expect(
      _path(
        _resolve(
          source,
          Uri.parse('package:carer_record_app/domains/users/ports.dart'),
        )!,
      ),
      endsWith('/lib/domains/users/ports.dart'),
    );
  });

  test(
    'IAM source has no clinical or app-composition path, even transitively',
    () {
      final iam = File(
        'lib/domains/institutional/presentation/iam_providers.dart',
      );
      for (final file in _reachable(iam)) {
        expect(
          _within(file, '/domains/patient/'),
          isFalse,
          reason: _path(file),
        );
        expect(
          _within(file, '/domains/clinical_event/'),
          isFalse,
          reason: _path(file),
        );
        expect(_within(file, '/lib/app/'), isFalse, reason: _path(file));
      }
    },
  );

  test('institutional domain is Dart-pure and independent of other layers', () {
    final domain = Directory('lib/domains/institutional/domain');
    for (final file in _dartFiles(domain)) {
      for (final uri in _directives(file)) {
        final target = _resolve(file, uri);
        if (target != null) {
          expect(
            _within(target, '/data/'),
            isFalse,
            reason: '$uri in ${file.path}',
          );
          expect(
            _within(target, '/presentation/'),
            isFalse,
            reason: '$uri in ${file.path}',
          );
          expect(
            _within(target, '/lib/app/'),
            isFalse,
            reason: '$uri in ${file.path}',
          );
        }
        expect(uri.toString(), isNot(startsWith('package:flutter/')));
        expect(uri.toString(), isNot(startsWith('package:flutter_riverpod/')));
        expect(uri.toString(), isNot(startsWith('package:supabase')));
      }
    }
  });

  test('IAM providers do not import clinical providers or app composition', () {
    final iam = File(
      'lib/domains/institutional/presentation/iam_providers.dart',
    );
    for (final uri in _directives(iam)) {
      final target = _resolve(iam, uri);
      if (target == null) continue;
      expect(
        _within(target, '/domains/patient/'),
        isFalse,
        reason: uri.toString(),
      );
      expect(
        _within(target, '/domains/clinical_event/'),
        isFalse,
        reason: uri.toString(),
      );
      expect(_within(target, '/lib/app/'), isFalse, reason: uri.toString());
    }
  });

  test(
    'users controllers depend on domain and neutral core, not UI/SDK/data',
    () {
      for (final file in _dartFiles(
        Directory('lib/domains/users/presentation/controllers'),
      )) {
        final source = file.readAsStringSync();
        expect(source, isNot(contains('WidgetRef')), reason: file.path);
        for (final uri in _directives(file)) {
          final target = _resolve(file, uri);
          if (target != null) {
            expect(
              _within(target, '/presentation/'),
              isFalse,
              reason: '$uri in ${file.path}',
            );
            expect(
              _within(target, '/data/'),
              isFalse,
              reason: '$uri in ${file.path}',
            );
            expect(
              _within(target, '/lib/app/'),
              isFalse,
              reason: '$uri in ${file.path}',
            );
          }
          expect(
            uri.toString(),
            anyOf(
              'package:flutter/foundation.dart',
              isNot(startsWith('package:flutter/')),
            ),
          );
          expect(
            uri.toString(),
            isNot(startsWith('package:flutter_riverpod/')),
          );
          expect(uri.toString(), isNot(startsWith('package:supabase')));
        }
      }
    },
  );

  test(
    'user screens do not import data/repositories or construct attempts',
    () {
      for (final file in _dartFiles(
        Directory('lib/domains/users/presentation'),
      ).where((file) => !file.path.contains('/controllers/'))) {
        final source = file.readAsStringSync();
        for (final uri in _directives(file)) {
          final target = _resolve(file, uri);
          if (target != null) {
            expect(
              _within(target, '/data/'),
              isFalse,
              reason: '$uri in ${file.path}',
            );
          }
        }
        expect(
          source,
          isNot(matches(RegExp(r'\b[A-Za-z_]\w*Attempt\s*\('))),
          reason: file.path,
        );
      }
    },
  );

  test('feature domains do not import app composition', () {
    for (final file in _dartFiles(Directory('lib/domains'))) {
      for (final uri in _directives(file)) {
        final target = _resolve(file, uri);
        if (target != null) {
          expect(
            _within(target, '/lib/app/'),
            isFalse,
            reason: '$uri in ${file.path}',
          );
        }
      }
    }
  });

  test('navigation policy does not depend on widgets or Riverpod', () {
    final policy = File('lib/app/router/navigation_policy.dart');
    for (final uri in _directives(policy)) {
      expect(uri.toString(), isNot(startsWith('package:flutter/')));
      expect(uri.toString(), isNot(startsWith('package:flutter_riverpod/')));
      final target = _resolve(policy, uri);
      if (target != null) {
        expect(
          _within(target, '/presentation/'),
          isFalse,
          reason: uri.toString(),
        );
      }
    }
  });
}
