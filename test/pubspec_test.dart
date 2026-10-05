import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Names listed under `dependencies:` in pubspec.yaml (without the Flutter SDK entry).
List<String> _dependencies() {
  final names = <String>[];
  var inDependencies = false;
  for (final line in File('pubspec.yaml').readAsLinesSync()) {
    if (line.startsWith('dependencies:')) {
      inDependencies = true;
      continue;
    }
    if (!inDependencies) continue;
    if (line.isNotEmpty && !line.startsWith(' ')) break;
    final match = RegExp(r'^  ([a-z_0-9]+):').firstMatch(line);
    if (match != null && match.group(1) != 'flutter') names.add(match.group(1)!);
  }
  return names;
}

void main() {
  test('every dependency of pubspec.yaml is imported by some file in lib', () {
    final source = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .map((f) => f.readAsStringSync())
        .join('\n');

    final unused = _dependencies().where((name) => !source.contains("package:$name/")).toList();

    expect(unused, isEmpty, reason: 'remove these from pubspec.yaml (or use them)');
  });

  test('the SDK lower bound allows the APIs the code uses (Color.withValues needs Dart 3.6)', () {
    final constraint = RegExp(r"sdk: '>=(\d+)\.(\d+)").firstMatch(File('pubspec.yaml').readAsStringSync())!;
    final major = int.parse(constraint.group(1)!);
    final minor = int.parse(constraint.group(2)!);

    expect(major > 3 || (major == 3 && minor >= 6), isTrue);
  });

  test('a packages folder only exists when pubspec.yaml refers to it', () {
    if (!Directory('packages').existsSync()) return;

    expect(File('pubspec.yaml').readAsStringSync(), contains('packages/'));
  });
}
